# Gotit plan

Living document, updated as work proceeds. Last updated: 2026-11-09.
Status: **M0 passed (2026-11-09): phone-to-PC copying can be automatic.** [ARCHITECTURE.md](ARCHITECTURE.md) is drafted, for review now that M0 is done. M1 is next. No repo yet.

Gotit shares what you copy between your Android phone and your Windows PC. Copy text or an image on one and it is ready to paste on the other; send files on purpose from either side. The two talk directly over the same Wi-Fi, with no server. Personal use, on free tools only.

## Decisions (2026-11-09, grilling session)

- **Purpose:** a personal app for one phone and one Windows PC, paired one to one. Not on the Play Store or the Microsoft Store.
- **Copying is automatic both ways** for copied text and images. Files are only ever sent on purpose.
  - PC to phone: automatic. Android lets a background app write the clipboard.
  - Phone to PC: automatic if M0 proves the easy method works on the phone. Otherwise it takes one tap on the phone's notification button.
- **Effortless setup:** normal Settings switches only. Never Developer options, adb or helper apps. The apps walk you through each switch and open the right Settings page in one tap.
- **Connecting:** open both apps on the same Wi-Fi and the phone lists the PC by name. Tap it, check that both screens show the same 4-digit code, and click Accept on the PC. No camera, nothing typed. A QR code shows only as a fallback when the network hides devices from each other. After that the two trust only each other's keys, and everything between them is encrypted.
- **One sharing switch, shared by both apps:**
  - Flipping it on either device turns sharing on or off for both. After a reconnect, the last change wins.
  - Off stops everything: copies, screenshots and files. Sending a file while it is off offers to turn sharing back on.
  - Phone: in the app, a quick settings tile and the notification. PC: the tray menu and the window, with the tray icon greyed out while off.
  - While off, the phone keeps a small "Sharing off" notification, so the PC can still turn sharing back on.
- **Network:** same Wi-Fi only, device to device, no server. Copies made while the two are not on the same network are dropped, never queued.
- **Recent list:** the last 20 or so items on each side, sent either way. Tap one to copy it again, open a file or share an image. No search or pins.
- **Sending files:**
  - From the PC: drag onto the app window (a folder is zipped), Explorer's Send to > Gotit (on Windows 11 it is under "Show more options"), or Ctrl+C the files in Explorer and press a hotkey. The hotkey is picked in M4, and it cannot be Ctrl+Alt+V, which is Office's Paste Special.
  - From the phone: the share sheet.
- **Passwords and one-time codes** cross like anything else. Password managers and some code-copying apps mark their copies as sensitive, with a flag both Windows and Android carry. Those items show as dots in the recent list and leave it after a minute.
- **Extras:**
  - A new phone screenshot lands on the PC's clipboard.
  - An image sent on purpose is saved, and also put on the other side's clipboard.
  - A copied link that crosses shows a notice with an Open button.
- **Tech:** Flutter for both apps, one Dart codebase. The native parts stay small: Kotlin on Android and C++ in the Windows runner. No Rust.
- **Repo and installs:** a public GitHub repo. Each release puts a signed APK and a per-user Windows installer on GitHub Releases, and both apps offer updates themselves. Nothing personal goes in the repo.
- **Name:** Gotit ("got it"). Android ID `app.gotit`.

### Defaults (change any of them)

1. **Finding each other:** mDNS (DNS-SD) on the local network, plus the last address that worked.
2. **PC app:** lives in the tray and starts with Windows (per user, no admin). A small window shows the connection state, the switch, a drop zone and the recent list. Only one copy runs at a time; Send to and the hotkey hand files to the running app.
3. **Phone app:** a quiet ongoing notification keeps the link alive (a foreground service). The guided setup covers MIUI's Autostart and battery settings.
4. **Arrivals:** copied text and images go onto the clipboard silently. Files land in `Downloads\Gotit` on the PC and `Download/Gotit` on the phone, with a notice to open them. Big files show progress, and there is no size limit.
5. **Language:** English only.
6. **Look:** minimal and calm. A short look pass, a few rendered directions to pick from, comes before M2's screens.
7. **Project setup:** CLAUDE.md, strict analysis, slim CI on pull requests, Conventional Commits and automatic releases. Every git step waits for your OK.

### Phone copy test (M0 grilling, 2026-11-09)

- **Copies to test:** the ones you make most.
  - Long-press > Copy in any app.
  - Chrome: copied text, and "Copy link".
  - WhatsApp messages.
  - SMS codes: the Copy button on a code's notification, or copying the code in Messages.
- **Pass bar:**
  - If the accessibility method catches most of them, phone to PC is automatic for what it catches, and the notification's Send button covers the rest.
  - If it catches too little to be useful, phone to PC is one tap only.
- **Install:** the test app goes on the phone over wireless debugging from the PC, so its own log can be read live while you copy. This is your call for this test only; Gotit itself never needs Developer options. The test app is uninstalled afterwards.

### Foundation (M1 grilling, 2026-11-09)

- **Repo:** public, `ThivaaVipul/gotit`, built from this folder.
- **Updates:**
  - The PC app updates itself. It downloads the new installer, checks it against `SHA256SUMS.txt`, and installs it silently the next time nothing is being sent. Gotit restarts in a couple of seconds, and a small notice says it updated.
  - The phone shows an Update banner, then Android's own install prompt.
- **Claude tooling, for this project only:** the official dart-flutter plugin (Flutter and Dart skills, plus the Dart MCP server), ui-ux-pro-max, and the flutter-animations skill.
- **Defaults** (change any of them):
  - The Flutter app lives in `app/`, for Android and Windows, with ID `app.gotit`. Android needs version 10 (API 29) or later, and releases ship as arm64 APKs. On the PC: Windows 10 or 11, x64.
  - Two pull requests:
    - **M1a:** the project, CLAUDE.md and CI. No release.
    - **M1b:** the release pipeline and self-updates, shipping v0.1.0.
  - The stand-in screen on both shows the name, the version and the update state.
  - The Android signing key stays outside the repo, in a private folder on the PC, with a backup. You add its secrets to GitHub.
  - The Windows installer is built with Inno Setup and installs per user, so no admin is needed. It isn't code-signed, so SmartScreen warns only on the first install from the browser.
  - CI on pull requests is one quick Ubuntu job: format, analyze and tests. Release builds run on Ubuntu (the APK) and on Windows (the installer).
  - Every git step waits for your OK: init, commits, creating the repo, pushes.

### Phone copy test results (M0, 2026-11-09)

Run on the phone (MIUI 14, Android 13) with the test app and its live log.

- **The method works, and you can't see it:**
  - An accessibility service notices a copy.
  - A 1-pixel invisible accessibility overlay then takes focus for a moment, which lets Android allow the clipboard read. The read lands 0.3 to 0.6 seconds after the copy.
  - No "pasted from your clipboard" notice appeared, the keyboard didn't blink, and no selection was lost.
  - Fallback: an invisible activity, never needed.
- **Three signals are needed:**
  - **A tap on a Copy button or menu item.** Covers the selection toolbar, WhatsApp's copy icon, MIUI Notes, Brave's toolbar and Share > Copy link, and Google Messages' number and date toolbar. A long label that starts with "Copy" counts too, like Brave's "Copy link <url>".
  - **A "Copied" notice,** such as WhatsApp's "Message copied".
  - **A Copy item leaving the screen,** for apps that don't report taps:
    - Google Messages draws its whole-message menu inside the screen with Jetpack Compose and announces nothing at all, so the screen is checked about 3 times a second while it's on.
    - The same check caught a Flutter app's copy and WhatsApp's newer popup.
- **Caught after the fixes:**
  - long-press Copy;
  - Brave Copy link;
  - WhatsApp, both the icon and the popup;
  - Google Messages, both a number and the whole message (5 of 5 once polling was in);
  - a Flutter app.

  An SMS code's Copy button wasn't tested, because no code arrived.
- **Costs and pitfalls:**
  - Polling took about 6% of one CPU core while in use. So Gotit polls only in apps that don't report taps (learned per app) and backs off when nothing happens.
  - The "Copy item went away" signal also fires when a menu closes without a copy. That costs a harmless extra read, so it's limited to those same apps.
  - Two bugs were found and fixed during the test:
    - a selection toolbar showing "Copy" set off a loop, so "Copy" now only counts when tapped;
    - every read now has a short cooldown.
- **PC to phone works:** a text and a PNG image, written to the clipboard from the background, both pasted into WhatsApp.
- **The Send button works:** the notification's button read the clipboard in 0.09 seconds.
- **MIUI and staying alive:**
  - Swiping the app away kills it.
  - With **Autostart off**, Android then marks the accessibility service as crashed, and it stays off until the switch is toggled. With **Autostart on**, Android restarts it by itself about 12 seconds later.
  - Locking the app in recents protects it from Clear all, but not from a deliberate swipe.
  - So Gotit's setup asks for the accessibility switch, Autostart, the battery set to No restrictions, and the lock. Gotit also notices a dead watcher and offers one tap back to the switch.
- **MIUI's accessibility shortcut:** MIUI can make the app the target of its floating accessibility button, and each tap on that button switches the watcher off or on. Gotit's setup says to turn on the main switch only.
- **After a phone restart,** the watcher started by itself about a minute after boot, without the app being opened. The first copy was caught through the backup: the overlay got no focus while the phone was still busy, so the invisible activity read the clipboard after 2.7 seconds.
- **Verdict: pass.** Phone-to-PC copying is automatic, with the Send button as the backup (your pass bar).

## What we know (research, 2026-11-09)

- **Android's clipboard:**
  - Since Android 10 an app can read the clipboard only while it has focus, or while it is the default keyboard. Writing is not restricted, which is why PC to phone can be automatic.
  - Android 12 and later show a "pasted from your clipboard" notice when an app reads another app's copy. M0 checks how often that shows.
- **The workarounds that need setup**, and why they are out:
  - Log watching, used by KDE Connect: a log permission granted over adb, plus an invisible window. From Android 13 it asks for approval again after every app restart. On MIUI the grant also needs "USB debugging (Security settings)", which asks for a Mi account and a SIM.
  - Shizuku: has to be restarted after every reboot.
  - Both break the "normal Settings only" rule.
- **The candidate is an accessibility service.** It is a normal Settings switch. An app installed from outside an app store first needs "Allow restricted settings" in its app info page on Android 13. On a copy, the service would briefly take focus with an invisible overlay and read the clipboard. Whether it catches copies reliably on MIUI is unproven, hence M0.
- **Other tools:**
  - Microsoft Phone Link's cross-device copy and paste supports only some phones: Samsung, plus select HONOR, OPPO, ASUS and vivo models and Xiaomi's 14T series.
  - KDE Connect and LocalSend cover parts of this, but not automatic phone-to-PC copying without adb.
- **No server is needed.** Firebase's Cloud Storage has needed the paid Blaze plan since 2026-02-03; Gotit doesn't use it.
- **Windows side:**
  - Flutter and the Visual Studio C++ build tools are installed; Rust and the .NET SDK are not.
  - `super_clipboard`, the usual Flutter package for images and files on the clipboard, builds Rust. So the Windows clipboard work lives in the runner's C++ instead: `WM_CLIPBOARDUPDATE`, plus text, image (DIB and PNG) and file-list formats.
- **Sensitive flags:**
  - Windows password managers mark copies with clipboard formats such as `ExcludeClipboardContentFromMonitorProcessing` and `CanIncludeInClipboardHistory`.
  - Android 13 and later use `ClipDescription.EXTRA_IS_SENSITIVE`.
- **The home network:** Android's wireless debugging, which also uses mDNS, already reaches the PC there. So discovery and direct connections get through.

## Milestones

Each milestone gets a short grilling of its details before code.

- [x] **M0 Phone copy test** (passed 2026-11-09; results above): a throwaway Android app, outside the repo, that catches copies with an accessibility service. It checks:
  - which copies it catches: a long-press Copy, apps' Copy buttons, Share > Copy and the keyboard's clipboard;
  - how fast, and which notices Android or MIUI show;
  - whether it survives a reboot and MIUI's cleanup;
  - writing text and an image to the clipboard from the background, for PC to phone.

  The result decides phone to PC: automatic with this method, or one tap on the notification.
- [ ] **M1 Foundation** (decisions above, under Foundation), in two pull requests:
  - [ ] **M1a Project:** the repo, one Flutter app for Android and Windows with a stand-in screen, CLAUDE.md, the Claude tooling, and slim CI. No release. Built and checked locally on 2026-11-09:
    - the app: Flutter 3.44.2, `app.gotit`, Android 10 or later, a 420x640 window on Windows;
    - a stand-in screen showing the name and the version (package_info_plus);
    - strict analysis, clean; 1 widget test;
    - a debug APK, and a Windows debug build that started and showed its "Gotit" window.

    It goes in as the first commit on main, since a new repo has nothing to open a pull request against.
  - [ ] **M1b Releases,** in two pull requests, so the pipeline is proven before anything ships:
    - [ ] **M1b1 The pipeline:**
      - the signing key, kept outside the repo, and a release-signed APK;
      - the version tooling (17 tests);
      - a per-user Windows installer (Inno Setup);
      - `release.yml`, which builds the APK on Ubuntu and the installer on Windows, checks the APK's certificate, and publishes both with checksums.

      Checked locally on 2026-11-09: a 14.5 MB arm64 APK at version 0.1.0 (code 1000), carrying the release certificate, and a 10.2 MB installer. No release from this change. Once merged and the secrets are added, a build-only run tests it on GitHub.
    - [ ] **M1b2 Self-updates:** silent on the PC, a banner on the phone. Ships as v0.1.0. Built locally on 2026-11-09, in plain Dart with small platform parts:
      - **Checks:** both apps ask GitHub for the latest release at start and every 6 hours.
      - **Downloads:** each download is checked against `SHA256SUMS.txt` and discarded on a mismatch.
      - **The phone:** shows "Version x is ready" with an Update button, then hands the APK to Android's installer. The first time, Android asks to allow installs from Gotit, and the screen says so.
      - **The PC:** runs the new setup silently and steps aside; the setup restarts Gotit, which then shows "Updated". A proper notice comes with the tray in M2.
      - **Local builds (0.0.0)** never update.
      - **Checks:** 20 tests, analysis clean, and Android and Windows builds pass.
- [ ] **M2 Connecting, text and the switch:** starts with the look pass. Then:
  - discovery, and find-and-tap pairing with the 4-digit code (QR fallback);
  - the encrypted link, and copied text both ways;
  - the shared switch: app, tile, notification and tray;
  - the phone's guided setup, and starting with Windows.
- [ ] **M3 Images:** copied images both ways, and new phone screenshots to the PC.
- [ ] **M4 Files:**
  - phone: the share sheet;
  - PC: drag onto the window, Send to and the hotkey;
  - the `Downloads\Gotit` and `Download/Gotit` folders, progress, and sent images also on the clipboard.
- [ ] **M5 Recent list and polish:**
  - the recent list on both sides;
  - the Open button for links;
  - sensitive items shown as dots and dropped after a minute;
  - a last polish pass.

## Risks

- **Phone-to-PC copying:** if the accessibility method fails on MIUI, phone to PC stays one tap. There is no developer-step fallback, by decision.
- **MIUI's background limits:** MIUI stops background apps beyond Android's own rules. The phone app needs Autostart on and the battery saver set to "No restrictions", both part of the guided setup. MIUI may also switch an accessibility service off after the app is killed or updated; M0 checks this.
- **Networks that keep devices apart:** some Wi-Fi networks, such as guest networks or networks with client isolation, block discovery or direct connections. The QR fallback gets past hidden discovery. A network that blocks device-to-device traffic outright can't be worked around without a server, which is out of scope.
- **Windows SmartScreen:** the installer has no paid code-signing certificate, so Windows warns on the first run ("More info", then "Run anyway").
- **Pasting images on the phone:** Android puts an image on the clipboard as a link to the file, so only apps that accept pasted images can paste it (most keyboards' clipboard panels, some chat apps). The recent list's Share is the fallback.
- **Battery:** the phone keeps a small connection open, even while sharing is off. Measured in M2.

## Log

- 2026-11-09: Your idea (share copied text, images and files between the phone and the PC), grilled. Decided:
  - copying is automatic both ways, on the same Wi-Fi only, between one phone and one PC;
  - a short recent list, and copies made while apart are dropped;
  - three ways to send files from the PC;
  - passwords cross but aren't kept, plus three extras;
  - Flutter on both, a public repo with releases, and the name Gotit.

  After the first summary you added the shared on/off switch and an effortless setup: find-and-tap pairing, and normal Settings only. So M0 now tests just the accessibility method. Plan written.
- 2026-11-09: Plan reviewed ("continue"). M0 grilled; the decisions are under "Phone copy test" above.
- 2026-11-09: M0's test app built and installed on the phone over wireless debugging. It is a throwaway plain Kotlin app, outside the repo, with no libraries:
  - an accessibility service that reads the clipboard through an invisible overlay, falling back to an invisible activity;
  - the Send notification;
  - test writes of a text and an image;
  - a log that never holds what was copied.

  The test was run with you the same afternoon. The method was improved four times along the way:
  1. "Copy" only counts when tapped.
  2. A cooldown after each read.
  3. A check for a Copy item leaving the screen.
  4. Polling for menus that announce nothing.

  It passed, including after swipe-away (with Autostart) and after a restart.

  While waiting for the test, the architecture was drafted in ARCHITECTURE.md:
  - the link: mDNS, mutual TLS with pinned certificates, length-prefixed frames;
  - the shared switch;
  - the native parts on each side;
  - releases with an APK and a Windows installer.
- 2026-11-09: M0 passed (results above). M1 grilled; the decisions are under "Foundation" above. M1a built locally:
  - the Flutter app for Android and Windows, with a stand-in screen;
  - CLAUDE.md, README, CI on pull requests, and the Claude tooling;
  - LF endings, plain ASCII, nothing personal.
