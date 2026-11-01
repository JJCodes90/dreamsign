# Dreamsign

An alarm for deep sleepers that doubles as a lucid-dreaming practice. It keeps ringing until you've proven you're awake. It catches your dream before it fades, and it guides wake-back-to-bed + MILD.

- **No accounts, ads, analytics or network. Everything stays on the iPhone.**
- **iOS 27.1+** (iPhone). Build with **Xcode 27.1+**.
- Swift, SwiftUI, SwiftData, AlarmKit, CoreMotion, NaturalLanguage, Swift Charts.
- **Full iPhone Duo support**: closed, open, rotated, and folded like a book or a laptop (see below).

## What's in the MVP

| | |
|---|---|
| **Alarms** | AlarmKit alarms that ring through Silent mode and Focus. Repeat days, label, sound, and ordered dismissal challenges. iOS always shows a Stop button, so each alarm pre-arms a **chain** of follow-up rings every 60 s. Only finishing the challenges in the app ends it. Rings switch to the loudest sound after 5 minutes. |
| **Challenges** | **Shake** (CoreMotion, count target, progress ring) · **Math** (3 difficulties, N in a row, a wrong answer resets) · **Dream journal** (minimum distinct real words, with anti-mashing checks and a "can't remember → first thoughts" path; entries save automatically). |
| **Lucid window (WBTB)** | A gentle alarm 4½–6 h after bedtime → quick journal → timed MILD rehearsal → a dim back-to-sleep screen. Includes "Going to bed now" for irregular nights. Audio hooks are stubbed (`SleepAudio`). |
| **Journal** | Entries grouped by morning, search, detail and edit, lucid flag, and dream-sign tagging (people, places, themes). |
| **Insights** | Recall streak, entries per week, top dream signs, lucid count, recall rate. |

## iPhone Duo

| Pose | What Dreamsign does |
|---|---|
| **Closed** (outer display) | Compact layouts sized for the wider, shorter screen. Toolbar items carry an icon and a title, so the system can move them into the vertical side bar. |
| **Open** (inner display) | Alarms and Insights become two columns. Journal becomes a split view (entries beside the open entry). The wake flow puts the problem beside the keypad, and the orb beside the MILD cue. |
| **Folded like a book** | Each half of a screen sits on its own side of the crease, using `ArrangementView` and the fold's reserved region. Single-purpose screens move to the trailing side. |
| **Folded like a laptop** (on a table) | Things to look at go on the top half, things to tap on the bottom: the keypad sits on the stable base. While journaling, the text stays above the fold and the keyboard sits below. |
| **Rotated / tent** | Landscape is supported. The inner display ignores orientation locks, so every layout is size-driven, never orientation-driven. |

Simulate every pose with the iPhone Duo simulator in Xcode 27.1's Device Hub.

## Getting started

**On Windows (no Mac needed):** GitHub Actions builds `Dreamsign.ipa` on every push, and you install it with Sideloadly. See [`docs/INSTALL_WINDOWS.md`](docs/INSTALL_WINDOWS.md).

**On a Mac:**

1. Open `Dreamsign.xcodeproj` in Xcode 27.1 or later.
2. Set your Team under the **Dreamsign** target, in **Signing & Capabilities**. Change the bundle ID if needed.
3. Run on an iPhone (⌘R). Run the tests on a simulator (⌘U).

The project uses **synchronized folders**: add files under `Dreamsign/` or `DreamsignTests/` on disk and they're in the build. There are no project-file edits.

## Docs

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) covers the verified AlarmKit constraints, the alarm-chain design, project structure, data model and validator rules.
- [`docs/INSTALL_WINDOWS.md`](docs/INSTALL_WINDOWS.md) explains how to install from a Windows PC with Sideloadly, and how to move to TestFlight with a paid account.
- [`docs/DEVICE_TESTING.md`](docs/DEVICE_TESTING.md) is the step-by-step checklist for what only a real iPhone can verify.
- [`docs/RESEARCH.md`](docs/RESEARCH.md) explains which studies shaped which design decisions.

## Layout

```
Dreamsign/
  App/            entry point, routing, onboarding, settings, preview data
  Core/           pure, unit-tested logic (scheduling, chain planner, validator, challenges, stats)
  Alarms/         AlarmKit client + coordinator + intents, alarm list/editor, sounds
  Wake/           wake flow and challenge screens
  WBTB/           lucid window settings, MILD, back to sleep, audio hooks
  Journal/        list, detail, editor, dream-sign tagging
  Insights/       stats
  Models/         SwiftData models
  DesignSystem/   palette, backgrounds, components
  Resources/      assets, alarm sounds
DreamsignTests/   Swift Testing suites
scripts/          generate_icon.py, generate_sounds.py (reproducible assets)
```

## Tests and CI

`DreamsignTests` (Swift Testing) covers the anti-spam journal validator (including the real on-device dictionaries), occurrence math across DST, the chain planner (budgeting, inference, stop/wake-up handling, deferral, completion, one-offs), math generation, shake detection and journal stats.

`.github/workflows/ios.yml` builds and runs the tests with Xcode 27.1 on the **iPhone Duo simulator** (GitHub's `xcode-27` runner) for every push and pull request.

## Regenerating assets

```sh
python3 scripts/generate_icon.py     # needs numpy + Pillow
python3 scripts/generate_sounds.py   # needs numpy
```
