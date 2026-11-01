# Testing on a physical iPhone

Unit tests cover the logic: scheduling, the chain planner, the journal validator, math, shake counting and stats. Run them with **⌘U** on any iOS 26 simulator. Everything below needs a real iPhone: alarms breaking through Silent/Focus, the lock-screen alert, motion and volume.

## Setup (once)

1. Open `Dreamsign.xcodeproj` in **Xcode 27.1** or later. It's required for iPhone Duo's full-screen layout and fold APIs, and to install on iOS 27.1.
2. Select the **Dreamsign** target, then **Signing & Capabilities**. Pick your Team. A free Apple ID works for personal use, but its builds expire after 7 days. If the bundle ID `com.jjcodes.dreamsign` is taken, change it to your own reverse-DNS ID.
3. On the iPhone (iOS 26+), turn on **Settings › Privacy & Security › Developer Mode** and restart.
4. Plug in the iPhone, choose it as the run destination, and press **⌘R**. The first launch asks you to trust the developer: go to **Settings › General › VPN & Device Management**.
5. Turn **Settings › Sounds & Haptics › Ringer and Alerts** up high. AlarmKit alarms use the ringer volume, not media volume.

> **Tip:** each alarm editor and the Lucid Window sheet has **Test in 10 seconds**. It saves the alarm and schedules a one-off ring with 3 follow-up rings. Lock the phone right after tapping it.

---

## Checklist

Tick each one off. Results marked ⚑ are the ones I need back from you. They decide a couple of defaults.

### 1. Permission
- Fresh install → onboarding → **Allow alarms**.
- **Expect:** the system prompt shows *"Dreamsign wakes you with real alarms…"*. Afterwards, **Settings › Apps › Dreamsign** has an Alarms switch.
- Deny it once (delete the app and reinstall). **Expect:** a red "Alarms are turned off" banner on the Alarms tab, with an **Open Settings** button.

### 2. Breaks through Silent and Focus
- Turn Silent mode on (side switch or Action button) and turn on a Focus such as Sleep.
- Run **Test in 10 seconds** and lock the phone.
- **Expect:** a full-screen alarm with the alarm's label, the system **Stop** control and a **Wake Up** button, and the sound plays out loud. A paired Apple Watch alerts too.

### 3. ⚑ How long does it ring, and does a custom sound loop?
AlarmKit's docs don't say this. One developer report claims custom sounds play **once**.
- For each sound (Classic, Dawn, Tide, Beacon): run a test, don't touch the phone, and time it with another clock.
- **Note:** (a) does the sound loop or stop after ~28 s? (b) how long does the alert stay on screen before the system gives up?
- Why it matters: if custom sounds play once, the chain still re-rings every 60 s, but there's a ~30 s silent gap each minute. In that case keep **Classic** for deep sleep, and I'll tighten the ring interval.

### 4. ⚑ The chain: Stop doesn't end it
- Run a test. When it rings, tap **Stop**.
- **Expect:** within 60 s it rings again, titled *"Not up yet — tap Wake Up"*. Stop again → another ring. With a test there are 3 follow-ups.
- To check **escalation**, set a real alarm 2 minutes ahead with *Keep ringing for 10 min*, and keep tapping Stop. **Expect:** from the 6th follow-up the sound switches to **Beacon**.
- **Expect:** rings never stack. If the original is still ringing when a follow-up starts, tapping Stop on one silences both.

### 5. ⚑ Wake Up from the lock screen
- Let a test ring, then tap **Wake Up** on the lock screen.
- **Expect:** Face ID / passcode → Dreamsign opens straight into the wake flow, and the ringing stops.
- **Note** whether it opened the app directly, or whether you had to tap a notification or banner.

### 6. No rings while you're working, rings if you drift off
- In the wake flow, keep interacting (shaking, typing). **Expect:** no rings, however long the journal takes.
- Stop touching the phone for 2+ minutes mid-challenge. **Expect:** it rings again.
- Leave the app (home screen) mid-challenge. **Expect:** a ring within ~2 minutes. Opening the app returns to the flow.

### 7. Completing ends it
- Finish every challenge → **Good morning** screen.
- Wait 5 minutes. **Expect:** silence.
- **Alarms › ⚙︎ Settings › Follow-up rings armed** should now count the *next* occurrence's chain.

### 8. Resilience
- Start a test. When it rings, swipe Dreamsign out of the app switcher and keep tapping Stop. **Expect:** the chain continues, because the rings were pre-armed and don't depend on the app running.
- Repeating alarm: for one morning, only tap Stop (don't open the app) until the chain ends. The next day, **expect** a full chain again: each Stop re-syncs the schedule, and background refresh helps.
- Restart the phone with an alarm set for a few minutes later, and **don't unlock it**. **Note** whether it rings before first unlock. Apple says the secondary (Wake Up) action only works after first unlock.

### 9. ⚑ Shake feel
- Shake challenge: a brisk shake should count roughly 6 per second. Walking around, or setting the phone down, should count nothing.
- **Note:** too easy or too hard? The threshold is `ShakeDetector.threshold` (1.3 g) in `Dreamsign/Core/Challenges/ShakeDetector.swift`. Lower it for more sensitivity.

### 10. Journal
- Type a real dream → the meter fills; the word count only counts distinct real words.
- Try `asdf jkl qwer`, `sooooo`, or the same word 15 times → it's blocked, with a one-line hint.
- **Dictation** (keyboard mic) should work and count. Names ("Priya", "Lisbon") should count.
- **Can't remember** switches to *First thoughts?* with an 8-word minimum.
- Kill the app mid-entry and reopen it: the draft comes back.
- **Expect:** the saved entry appears in Journal with no extra step.

### 11. Lucid window (WBTB)
- **Lucid window › Test in 10 seconds**, then lock the phone. **Expect:** the soft Dawn sound and a **Begin** button.
- Flow: quick journal (10 words) → **MILD** rehearsal (Recall → Intend → Visualize, every 20 s, breathing orb, timer) → **Back to sleep**. The screen dims and the phone auto-locks normally.
- **Expect:** no follow-up rings once the journal is saved, including during the 3-minute MILD timer.
- With a morning alarm after it, **expect** the morning wake flow to replace the leftover back-to-sleep screen.
- **Going to bed now** on the card schedules tonight's window from the current time; **Cancel tonight** removes it.

### 12. One-shot and time zone
- An alarm with no repeat days switches itself off after you complete it.
- **Settings › General › Date & Time**: turn off automatic and pick another time zone, then reopen Dreamsign. **Expect:** alarms keep their wall-clock time.

---

### 13. ⚑ iPhone Duo poses
Before testing on the device, use the **iPhone Duo** simulator in Xcode 27.1's Device Hub (open, close, rotate, fold). Then on the device:
- **Closed**: every screen fits the outer display with nothing clipped. The Alarms, Journal and Insights toolbars sit in the side bar with icons. Editor sheets show vertical ✕ / ✓.
- **Open, flat**: Alarms shows two columns (overview | alarms) and Insights two columns. Journal shows the list beside the selected entry. Delete an entry from the detail and the selection clears with no crash.
- **Wake flow, open**: Math shows the problem beside the keypad. MILD shows the orb beside the cue.
- **Book fold** (partially open, held like a book): no button or key sits in the crease. Single screens (Shake, Back to sleep) move to the right half.
- **Laptop fold** (inner display facing you, bottom half on the table): Math puts the problem on top and the keypad on the bottom half. While journaling, the text is above the fold and the keyboard below. Shake's ring is on top.
- **Fold or unfold mid-challenge**: progress isn't lost, nothing restarts, and no extra ring fires.
- **Tent / landscape** on the nightstand: the alarm alert and the wake flow both work.
- **Note** any pose where something lands in the crease or gets cut off.

## Simulator notes

- The Shake challenge shows a **Count a shake** button on the simulator.
- AlarmKit scheduling works in the simulator for development, but use a device to judge Silent/Focus, the lock screen and volume.
- Previews use in-memory sample data (`PreviewData.swift`).

## Reporting back

Send me the results for **3, 4, 5, 9 and 13**, plus anything that looked off. These decide the default sound, the ring interval and the shake threshold.
