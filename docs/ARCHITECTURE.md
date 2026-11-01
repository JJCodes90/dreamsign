# Dreamsign — Architecture

Personal-first iOS alarm + lucid dreaming app. Everything stays on device: no accounts, analytics, network or ads.

- **Platform:** iOS 26.0+, iPhone, including full iPhone Duo support. Dark only. Built with Xcode 27.1+.
- **Stack:** Swift, SwiftUI, SwiftData, AlarmKit, CoreMotion, NaturalLanguage, Swift Charts, Swift Testing

---

## 1. AlarmKit — verified facts

Checked against Apple's AlarmKit reference, the *Scheduling an alarm with AlarmKit* sample and WWDC25 session 230 (fetched Nov 2026).

| Topic | Finding | Consequence for Dreamsign |
|---|---|---|
| Info.plist | `NSAlarmKitUsageDescription` is required. If it's missing or empty, the app can't schedule alarms. | Set in `Dreamsign/Info.plist`. |
| Authorization | `AlarmManager.shared.requestAuthorization()` returns `.authorized`, `.denied` or `.notDetermined`. If the app never asks, the system asks when the first alarm is scheduled. `authorizationUpdates` streams changes, and people can revoke it in Settings. | We ask during onboarding. The Alarms tab shows a banner with a Settings deep link when access is denied. |
| Silent / Focus | Alarms break through silent mode and the current Focus. They're also forwarded to a paired Apple Watch and show in StandBy. | No extra entitlement needed. |
| **Stop button** | "The system provides a stop button automatically." `init(title:stopButton:…)` is deprecated, and `init(title:secondaryButton:secondaryButtonBehavior:)` (iOS 26.1+) has no stop parameter. **The stop button can't be hidden.** | We need an alarm chain (§2). On iOS 26.0 we fall back to the deprecated initializer. |
| Secondary button | `.custom` behavior runs a `LiveActivityIntent`. An intent with `supportedModes = .foreground` opens the app. It's only available after first unlock. | The **Wake Up** button opens the app straight into the challenges. |
| Stop intent | `stopIntent` runs when Stop is tapped. The intent runs in the app's process, which is launched in the background if needed. | It quiets sibling rings and re-arms the chain. It never cancels it. |
| Widget extension | It's required only for countdown or paused presentations ("…the system may unexpectedly dismiss alarms and fail to alert"). The system draws the alerting UI itself. | We don't use countdown or snooze, so there's **no widget extension** in the MVP. If snooze is ever added, a Live Activity has to come with it. |
| Limits | No fixed count. Scheduling throws `AlarmError.maximumLimitReached` depending on device state and resources. | The chain is capped at **40 armed rings globally**, soonest first. A truncated chain is reported in the UI. |
| Schedules | `.relative(time, repeats: .never / .weekly([Locale.Weekday]))` follows the device time zone. `.fixed(Date)` is absolute. | The primary alarm uses `.relative` (system-managed and survives the app never launching). Chain rings use `.fixed`. |
| Lifecycle | A one-shot alarm is deleted from the daemon once it fires and is stopped. A repeating alarm is rescheduled. Anything missing from `alarms` / `alarmUpdates` is no longer scheduled. | We keep our own registry and diff it against `AlarmManager.alarms`. |
| Sounds | `AlertConfiguration.AlertSound.named("file")` loads from the main bundle or `Library/Sounds`. Community reports say files must be under 30 s (`.caf/.aiff/.wav`) and that custom sounds may play **once** rather than loop (unverified). | Bundled sounds are 28 s and escalate inside the file. The default sound is the system alarm. **Verify on device** (see DEVICE_TESTING.md). |
| Positioning | Apple: alarms are for wake-ups and timers, not a replacement for critical or time-sensitive alerts. | This is exactly our use. |

---

## 2. The alarm chain

**Goal:** the alarm keeps coming back every 60 s until every dismissal challenge is done in the app, whatever the user does with the system Stop button.

A single scheduled alarm can't do this, and neither can the stop intent alone, because the app isn't guaranteed to run when an alarm fires. So each occurrence has its chain **pre-armed** when it's scheduled.

```
occurrence D (07:00)
 ├─ primary   relative, weekly repeat, id = WakeAlarm.id           07:00
 ├─ ring 1    fixed                                                07:01
 ├─ ring 2    fixed                                                07:02
 │   …
 └─ ring N    fixed  (N = "keep ringing" minutes, default 15)      07:15
```

| Event | What happens |
|---|---|
| Alarm saved / app launch / foreground / time-zone change / background refresh | `resync()`: ensures each enabled alarm's primary exists and its **next** occurrence has rings armed (within the global budget). Stale rings are cancelled. Orphans are cancelled. |
| User taps **Stop** (any ring) | `StopRingIntent` stops any *other* alerting ring of the same occurrence (so rings never stack) and re-syncs. The chain keeps going: the next ring is ≤ 60 s away. |
| User taps **Wake Up** | `WakeUpIntent` does the same, records a pending wake, and opens the app into the wake flow. |
| App comes to the foreground while an occurrence is active | The wake flow is presented. "Active" means `fireDate ≤ now ≤ lastRing + 3 min` and not completed. This is inferred from the schedule too, so it works even if no intent ran. |
| User is doing challenges | Pending rings are pushed out to **now + 2 min**. The push is refreshed on interaction (throttled to every 20 s). If they fall back asleep with the app open, or leave the app, the chain resumes within 2 min. |
| All enforced challenges complete | Remaining rings are cancelled, the occurrence is marked complete and the next one is armed. A one-shot alarm disables itself. |

WBTB is the same mechanism with a gentler sound. Its only enforced step is the journal. MILD and back-to-sleep must never be interrupted by a ring.

---

## 3. Project structure

```
Dreamsign.xcodeproj            synchronized folders (Xcode 16+ format) — add files on disk, no project edits
Dreamsign/
  App/                         DreamsignApp, AppModel (routing), RootView, onboarding
  Core/                        pure Swift, no UI: unit-tested
    Scheduling/                WeekdaySet, AlarmTime, OccurrenceMath, ChainPlanner, ChainState
    Journal/                   JournalValidator, KeyboardGeometry, Stopwords, lexicon protocols
    Challenges/                MathProblemGenerator, ShakeDetector
    Insights/                  JournalStats (streaks, weekly buckets, top signs)
  Alarms/                      AlarmKitClient, AlarmCoordinator, intents, sounds, list + editor UI
  Wake/                        WakeFlow + Shake / Math / Journal challenges, completion
  WBTB/                        settings, MILD rehearsal, back-to-sleep, audio hooks (stubbed)
  Journal/                     list, detail, editor, dream-sign tagging
  Insights/                    stats dashboard
  Models/                      SwiftData: WakeAlarm, DreamEntry, DreamSign
  DesignSystem/                palette, type, backgrounds, buttons, components
  Resources/                   Assets.xcassets, Sounds/
DreamsignTests/                Swift Testing suites (validator, scheduling, chain, math, shake, stats)
scripts/                       sound + icon generators (reproducible assets)
docs/                          this file, DEVICE_TESTING.md, RESEARCH.md
```

**Boundaries.** `Core/` imports only Foundation (plus NaturalLanguage/UIKit behind protocols), so every rule that matters can be tested on the simulator. The AlarmKit layer works on `AlarmSpec` snapshots, not SwiftData objects, so the App Intents (running in the background) never need the model container.

---

## 4. Data model (SwiftData)

```swift
@Model WakeAlarm                       // one per alarm; the single WBTB plan is kind == .wbtb
  id: UUID                             // also the AlarmKit id of the primary alarm
  hour, minute: Int
  weekdaysRaw: Int                     // WeekdaySet bitmask, 0 = one-shot
  label: String
  soundRaw: String                     // AlarmSound
  isEnabled: Bool
  chainMinutes: Int                    // "keep ringing" length (rings, 1/min)
  challengesData: Data                 // [Challenge] JSON (shake/math/journal + config, ordered)
  kindRaw: String                      // wake | wbtb
  revision: Int, createdAt, modifiedAt
  // WBTB only
  bedtimeHour, bedtimeMinute, wbtbOffsetMinutes, mildMinutes: Int

@Model DreamEntry
  id: UUID, createdAt: Date
  text: String
  isNoRecall: Bool                     // "first thoughts on waking" entry
  isLucid: Bool
  sourceRaw: String                    // alarm | wbtb | manual
  signs: [DreamSign]                   // many-to-many

@Model DreamSign
  key: String (unique, normalized)     name: String
  categoryRaw: String                  // person | place | theme
  entries: [DreamEntry]
```

Non-SwiftData state, `ChainState` (JSON in UserDefaults): an alarm-spec snapshot, armed occurrences + ring ids, primary fingerprints, pending wake. It's owned by `AlarmCoordinator` and readable from the intents.

**The "night" of an entry** is `startOfDay(createdAt + 6h)`. A 3 AM WBTB entry and a 7 AM entry count as the same morning, and streaks follow that.

---

## 5. Layout: iPhone Duo and every other size

Layouts are driven by the space a view has, never by device idiom or orientation. Apple: *"the inner display doesn't honor your supported interface orientations."*

- **`FoldAwareSplit`** (`DesignSystem/FoldAware.swift`) handles any screen with a "look at" part and a "tap" part. Tall and unfolded, it shows a natural stacked layout. Wide, or folded, it uses `ArrangementView` with the `.split` style (iOS 27.1). That puts the parts side by side when the device is folded like a book and top/bottom when it's folded like a laptop, each clear of the crease. Before iOS 27.1, it falls back to a size-based `HStack`.
- **`FoldAvoiding`** applies Apple's displacement pattern to single-block screens. It reads the active *division* reserved region (`GeometryProxy.reservedRegions(kind: .division)`) and moves the content to one side. In book pose that's trailing, where content continues when the device closes. In laptop pose it's top or bottom, by purpose.
- **Bars.** Every toolbar item has an icon and a title (`Label`, or `Button(role: .cancel / .confirm / .close)`), so the system can move it into the Duo's vertical side bar. Confirm actions use `.topBarPinnedTrailing` on iOS 27.
- **Containers.** Journal uses `NavigationSplitView`, and the tab view uses system tabs. Both adapt to every pose automatically.

## 6. Journal anti-spam validator

The rules are pure and deterministic, with injected `Lexicon` and `WordTokenizer`:

1. Tokenize with `NLTokenizer(.word)`. Detect the language with `NLLanguageRecognizer`. Names come from `NLTagger(.nameType)`.
2. Classify each token (single characters and numbers are ignored):
   - **repeated** if it has a run of 3+ identical letters
   - **mashed** if it's unknown and also a keyboard-row run (`asdf`), ≥ 70 % physically adjacent key pairs, or a near-vowelless string
   - **known** if `NLEmbedding` or `UITextChecker` knows it
   - **name** if it's tagged as a name and isn't mashed
   - **unknown** otherwise (typos: they don't count, but don't block on their own)
3. Count **distinct real words** (known + names). This drives the progress meter.
4. Blockers: ≥ 2 repeated tokens · mashed tokens ≥ max(2, 10 %) · unknown + mashed > 40 % · distinct/total < 45 % (≥ 10 tokens) · too few content words (non-stopwords ≥ max(3, min/4)).

Defaults: dream 15 words · no-recall ("first thoughts and feelings") 8 · WBTB quick journal 10.
