# Installing Dreamsign from a Windows PC

You don't need a Mac. GitHub's Mac servers build the app for you on every push. **Sideloadly** on Windows signs that build with your Apple ID and installs it on your iPhone over USB.

## One-time setup

1. **iTunes and iCloud for Windows.** Install them from Apple's website, **not** the Microsoft Store. Sideloadly needs the website versions for the USB drivers and sign-in.
2. **Sideloadly** from [sideloadly.io](https://sideloadly.io). Its developer has confirmed iOS 27 support.
3. On the iPhone: **Settings › Privacy & Security › Developer Mode** → On, then restart. Sideloaded apps won't open without it.
4. Plug the iPhone into the PC and tap **Trust** on the phone.

> **iLoader?** It's mainly an installer for SideStore. At the time of writing there's an open report of installs failing on iOS 27 ("provisioning profile is banned"), so use Sideloadly for now.

## Get the app

1. Open the repo on GitHub → **Actions** → the latest green **iOS** run on your branch.
2. Under **Artifacts**, download **Dreamsign-ipa**, then unzip it to get `Dreamsign.ipa`.

Every push builds a fresh one. Artifacts are kept for 30 days.

## Install

1. Open Sideloadly. Your iPhone shows in the device list.
2. Drag `Dreamsign.ipa` onto the window.
3. Enter your Apple ID and press **Start**. A free Apple ID works, and Sideloadly signs the app for your device. Many people use a secondary Apple ID for sideloading.
4. On the iPhone: **Settings › General › VPN & Device Management** → tap your Apple ID → **Trust**.
5. Open Dreamsign and tap **Allow alarms**.

## Keeping it running (free Apple ID)

- **Builds signed with a free Apple ID expire after 7 days.** Once it expires the app won't open, and the **Wake Up** button can't open it either. Re-sign it every few days.
- **To re-sign:** install the same `.ipa` again with the same Apple ID. It installs over the existing app, so your alarms and journal stay. In Sideloadly's advanced options you can turn on automatic refresh over Wi-Fi while the PC is on.
- **Limits:** a free Apple ID can have at most 3 sideloaded apps installed at once.

## When you have the paid developer account

Switch to **TestFlight**. GitHub builds, signs and uploads each version for you, and you install it from the TestFlight app on the phone. There's no PC, no 7-day expiry (TestFlight builds last 90 days), and it's the same path you'd use for the App Store later.

What's needed: an App Store Connect API key (Issuer ID, Key ID and the `.p8` file) saved as GitHub repository secrets, plus your Team ID. Then add a CI job that archives, signs and uploads.

> Moving from the sideloaded build to TestFlight changes who signs the app, so iOS will make you delete the old one first. **Deleting the app deletes its journal.** Treat entries as test data until then, or export them first.

## If something goes wrong

- **"Unable to verify app" / it won't open:** trust your Apple ID under VPN & Device Management, and check that Developer Mode is on.
- **The app crashes:** go to **Settings › Privacy & Security › Analytics & Improvements › Analytics Data**, find entries starting with `Dreamsign`, and share them. They're the crash reports.
- **Sideloadly can't see the phone:** reinstall iTunes from Apple's website (not the Microsoft Store), unlock the phone, and re-trust the PC.
