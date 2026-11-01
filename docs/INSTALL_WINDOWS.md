# Installing Dreamsign from a Windows PC

You don't need a Mac. GitHub's Mac servers build the app for you on every push. A sideloading tool on Windows (**iLoader**, or **Sideloadly** as a backup) signs that build with your Apple ID and installs it on your iPhone over USB.

## One-time setup

1. **iTunes for Windows** from Apple's website, **not** the Microsoft Store. It provides the USB drivers. Sideloadly also wants iCloud for Windows from Apple's website.
2. **iLoader** ([github.com/nab138/iloader](https://github.com/nab138/iloader)) if you already use it. **Sideloadly** ([sideloadly.io](https://sideloadly.io)) is the backup; its developer has confirmed iOS 27 support.
3. On the iPhone: **Settings › Privacy & Security › Developer Mode** → On, then restart. Sideloaded apps won't open without it.
4. Plug the iPhone into the PC and tap **Trust** on the phone.

## Get the app

1. Open the repo on GitHub → **Actions** → the latest green **iOS** run on your branch.
2. Under **Artifacts**, download **Dreamsign-ipa**, then unzip it to get `Dreamsign.ipa`.

Every push builds a fresh one. Artifacts are kept for 30 days.

## Install with iLoader

Sign in with your Apple ID as you did before, choose to install another app / an IPA (not SideStore), and pick `Dreamsign.ipa`. Then do steps 4–5 below: trust your Apple ID on the phone, and allow alarms.

> iLoader's tracker has open iOS 27 reports, notably apps that crash immediately at launch after an iLoader install while the same app installed another way works. If Dreamsign closes the instant you open it, reinstall it with Sideloadly.

## Install with Sideloadly

1. Open Sideloadly. Your iPhone shows in the device list.
2. Drag `Dreamsign.ipa` onto the window.
3. Enter your Apple ID and press **Start**. A free Apple ID works, and Sideloadly signs the app for your device. Many people use a secondary Apple ID for sideloading.
4. On the iPhone: **Settings › General › VPN & Device Management** → tap your Apple ID → **Trust**.
5. Open Dreamsign and tap **Allow alarms**.

## Keeping it running (free Apple ID)

- **Builds signed with a free Apple ID expire after 7 days.** Once it expires the app won't open, and the **Wake Up** button can't open it either. Re-sign it every few days.
- **To re-sign:** install the same `.ipa` again with the same Apple ID and the same tool. It installs over the existing app, so your alarms and journal stay. Sideloadly can also refresh automatically over Wi-Fi while the PC is on (advanced options).
- **Limits:** a free Apple ID can have at most 3 sideloaded apps installed at once.

## When you have the paid developer account

Switch to **TestFlight**. GitHub builds, signs and uploads each version for you, and you install it from the TestFlight app on the phone. There's no PC, no 7-day expiry (TestFlight builds last 90 days), and it's the same path you'd use for the App Store later.

What's needed: an App Store Connect API key (Issuer ID, Key ID and the `.p8` file) saved as GitHub repository secrets, plus your Team ID. Then add a CI job that archives, signs and uploads.

> Moving from the sideloaded build to TestFlight changes who signs the app, so iOS will make you delete the old one first. **Deleting the app deletes its journal.** Treat entries as test data until then, or export them first.

## If something goes wrong

- **"Unable to verify app" / it won't open:** trust your Apple ID under VPN & Device Management, and check that Developer Mode is on.
- **It closes the instant it opens (after an iLoader install):** that's the open iOS 27 code-signing issue. Reinstall with Sideloadly.
- **The app crashes:** go to **Settings › Privacy & Security › Analytics & Improvements › Analytics Data**, find entries starting with `Dreamsign`, and share them. They're the crash reports.
- **Sideloadly can't see the phone:** reinstall iTunes from Apple's website (not the Microsoft Store), unlock the phone, and re-trust the PC.
