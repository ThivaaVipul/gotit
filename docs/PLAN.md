# Gotit plan

Living document, updated as work proceeds. Last updated: 2026-11-10.
Status: **M1 done (2026-11-10).** v0.1.1 updated both apps by themselves. **M2 grilled (2026-11-10). M2a, the look, shipped as v0.2.0; M2b1, the PC shell, is built.**

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

### Connecting, text and the switch (M2 grilling, 2026-11-10)

- **Look pass:** one local HTML page, outside the repo, with 3 directions. Each is shown on the phone home screen, the pairing code and the PC window, in light and dark, with a matching icon. The pick is written into the docs and the page is deleted.
- **Icon:** the chosen one goes on the phone launcher (adaptive, plus Android's themed icon), the PC window and taskbar, the installer, and the tray, with an on and a greyed-out off version.
- **Theme:** follows each device's system setting, light or dark.
- **QR fallback:** built in M2.
  - The PC window has "Show QR code", and the phone has "Scan QR code" under its list.
  - The QR carries the PC's address, its certificate fingerprint and a one-time token, so scanning pairs at once: no code to compare and no Accept.
- **Phone first run:** pairing first, so PC-to-phone copying works right away. Then a checklist on the home screen walks through the setup steps for phone-to-PC copying, and stays until they're done.
- **PC name:** the Windows name at first, renamable in the PC app's settings. The phone shows its own device name.
- **Sent sign:** quiet. The phone's notification text changes to "Sent to <PC>" with no sound or pop-up; the PC's tray icon shows a check for about a second. Arrivals stay silent.
- **Four pull requests, each a release, each checked on the devices before the next:**
  - **M2a** the look and the icon;
  - **M2b** the tray, starting with Windows, and pairing (find-and-tap and QR);
  - **M2c** text both ways: the phone's copy watcher, its notification and the setup checklist;
  - **M2d** the shared switch: app, tile, notification and tray.
- **The look, picked (2026-11-10, after two rounds of mockups):**
  - **Slate:** dark-first and precise, like a pro tool. Inter, 12 px corners, hairlines, and an indigo-to-violet gradient for anything live. Light and dark follow the system.
  - **Motion:** a light beam runs along the link between the two devices when a copy crosses. A slow sweep circles the connected card, and pairing digits sharpen into focus. A spring switch, a live ring around the other device, and setup checks that draw themselves. Timings are in ARCHITECTURE.md under "Look".
  - **Icon: Catch,** a ball flying into a C-shaped catch: the moment a copy lands. A white C and an indigo ball on a deep slate tile.
  - Round 1 (Ink, Pulse, Native) and the other round 2 directions (Aurora, Signal) and icons were turned down.
- **Defaults** (change any of them):
  - A pairing request brings the PC window to the front with the code and Accept / Decline; it expires after 60 seconds.
  - Forget, in the settings on either side, unpairs both.
  - The PC window opens on first run. After that Gotit starts hidden in the tray at sign-in (on by default, a switch in settings). Closing the window hides it; Quit is in the tray menu.
  - The phone keeps one quiet notification: "Connected to <PC>", "Looking for <PC>" or "Sharing off", with Send and Turn off (Turn on while off).
  - Text crosses as plain text. Its sensitive flag goes along, so the receiving side keeps it out of Windows clipboard history and hides Android's clipboard preview. The dots in the recent list come in M5.
  - If the two apps' link versions differ, both say "Update Gotit on <device>" and sharing waits.

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
- [x] **M1 Foundation** (decisions above, under Foundation), in two pull requests:
  - [x] **M1a Project:** the repo, one Flutter app for Android and Windows with a stand-in screen, CLAUDE.md, the Claude tooling, and slim CI. No release. Built and checked locally on 2026-11-09:
    - the app: Flutter 3.44.2, `app.gotit`, Android 10 or later, a 420x640 window on Windows;
    - a stand-in screen showing the name and the version (package_info_plus);
    - strict analysis, clean; 1 widget test;
    - a debug APK, and a Windows debug build that started and showed its "Gotit" window.

    It goes in as the first commit on main, since a new repo has nothing to open a pull request against.
  - [x] **M1b Releases,** in two pull requests, so the pipeline is proven before anything ships:
    - [x] **M1b1 The pipeline** (PR #1; a build-only run on GitHub built and checked both apps):
      - the signing key, kept outside the repo, and a release-signed APK;
      - the version tooling (17 tests);
      - a per-user Windows installer (Inno Setup);
      - `release.yml`, which builds the APK on Ubuntu and the installer on Windows, checks the APK's certificate, and publishes both with checksums.

      Checked locally on 2026-11-09: a 14.5 MB arm64 APK at version 0.1.0 (code 1000), carrying the release certificate, and a 10.2 MB installer. No release from this change. Once merged and the secrets are added, a build-only run tests it on GitHub.
    - [x] **M1b2 Self-updates** (PR #2, released as v0.1.0): silent on the PC, a banner on the phone. Ships as v0.1.0. Built locally on 2026-11-09, in plain Dart with small platform parts:
      - **Checks:** both apps ask GitHub for the latest release at start and every 6 hours.
      - **Downloads:** each download is checked against `SHA256SUMS.txt` and discarded on a mismatch.
      - **The phone:** shows "Version x is ready" with an Update button, then hands the APK to Android's installer. The first time, Android asks to allow installs from Gotit, and the screen says so.
      - **The PC:** runs the new setup silently and steps aside; the setup restarts Gotit, which then shows "Updated". A proper notice comes with the tray in M2.
      - **Local builds (0.0.0)** never update.
      - **Checks:** 20 tests, analysis clean, and Android and Windows builds pass.
- [x] **M2 Connecting, text and the switch** (decisions above), in four pull requests:
  - [x] **M2a Look** (PR #4, released as v0.2.0, which both apps installed by themselves): three directions on one HTML page, then the chosen theme (light and dark) and the icon everywhere. Picked Slate with the Catch icon. Built on 2026-11-10:
    - the Slate theme (`lib/app/theme/`): palette, Inter, motion timings, light and dark;
    - the Catch icon on the Android launcher (vector, with a themed version), the splash, the Windows window, taskbar and installer;
    - `CatchMark`, which draws the icon in the app and plays the catch on the stand-in home screen;
    - 26 tests, analysis clean, and Android and Windows debug builds pass. The Windows window was checked by eye.
  - [x] **M2b Pairing** (PR #5 and PR #6, released as v0.3.0 and v0.4.0): the tray and starting with Windows; discovery, find-and-tap pairing with the 4-digit code, and the QR fallback; the encrypted link. Plan (2026-11-10):
    - **Checked first:**
      - Flutter here and in CI is 3.44.2 (Dart 3.12). The newest bonsoir, tray_manager and window_manager need Flutter 3.47, so M2b uses the newest that fit: bonsoir 7.1.5, tray_manager 0.6.1 and window_manager 0.5.2. Moving Flutter itself is a separate change.
      - A throwaway test of `dart:io` TLS with self-signed certificates on this PC passed:
        - a pairing connection where only the PC proves itself, and the phone pins its certificate;
        - mutual TLS where each side trusts only the other's certificate;
        - a stranger's certificate, a missing one and a wrong server were all refused.

        A server can't ask for a client certificate it doesn't know yet without refusing it. While building M2b2 it turned out that it can ask without requiring one: a pairing phone shows no certificate, and the paired phone shows its pinned one. So it's one TLS port with no mode byte (details in ARCHITECTURE.md, "The link").
    - **M2b1, the PC shell** (its own pull request, a release):
      - **Tray icon** with Open and Quit (tray_manager). The sharing switch joins the menu in M2d.
      - **Closing the window** hides it to the tray.
      - **Only one copy runs** (windows_single_instance). Opening Gotit again brings the window back.
      - **Starting with Windows,** on by default (a Run key value; see below). It starts hidden in the tray.
      - **Settings:** the PC's name (the Windows name at first) and start with Windows.
      - This also proves the desktop packages build on GitHub's Windows runner with the C++ tools alone.
      - Built locally on 2026-11-10 and checked on this PC with debug and release builds:
        - a normal start shows the window, and `--hidden` keeps it in the tray;
        - closing hides it, and a second launch brings the first copy back and quits;
        - a tray click shows the window, and Quit ends the app in 0.16 seconds;
        - the tray icon's first tooltip reads "Gotit".

        Two quirks were found and fixed (details in ARCHITECTURE.md, "Window and tray"):
        - the plugin added the tray icon with garbage tooltip text;
        - a normal quit kept the window up for about 9 seconds.

        `launch_at_startup` clashed with `package_info_plus` over `win32`, so the Run key is written directly. 38 tests, analysis clean, and Android and Windows builds pass.
    - **M2b2, pairing and the link** (its own pull request, a release):
      - **Identity:** each device makes an EC P-256 key and a self-signed certificate on first run (basic_utils). The key is kept sealed: by DPAPI on the PC, and by an Android Keystore key on the phone. (flutter_secure_storage was dropped: its Windows part needs Visual Studio's ATL headers.)
      - **Discovery:** the PC advertises `_gotit._tcp` (bonsoir) with its ID, name and link version. The phone lists what it finds.
      - **Pairing by tap:**
        1. The phone connects in "pair" mode and records the PC's certificate.
        2. It sends its own certificate and name inside the encrypted channel.
        3. Both show a 4-digit code made from a hash of both certificates. A device in the middle can't make the two codes match.
        4. You tap Accept on the PC, the window having come to the front. Each side then pins the other.
      - **Pairing by QR:**
        - The PC shows a code holding its addresses, port, certificate fingerprint and a one-time token that expires in 5 minutes.
        - The phone scans it (mobile_scanner, using Google Play services' scanner, so the APK stays small). It checks the fingerprint and sends the token, and they're paired with no code to compare.
        - The camera is asked for only when you tap Scan.
      - **Session:** mutual TLS in "session" mode.
        - A hello carries the link version. If the versions differ, both apps say to update.
        - A ping every 30 seconds keeps the link alive.
        - The phone reconnects with backoff, using mDNS and the last address that worked.
        - In M2b2 the phone keeps the link only while the app is open. The background service comes with M2c.
      - **Screens:**
        - Phone: the nearby-PCs list with Scan QR code, the pairing code, and home with the PC's name and the live link.
        - PC: waiting for your phone with Show QR code, the pairing request, and home with the phone's name.
        - Forget is in settings on both, and tells the other side.
      - **The first time,** Windows asks whether Gotit may use private networks. Allow it, or the phone can't reach the PC.
      - **Tests:** framing, pairing codes, the QR payload, identity making, and two link ends over localhost TLS, covering pair, accept, decline, a stranger, a wrong code and a version mismatch.
      - **Built locally on 2026-11-10:**
        - the link (`lib/core/link/`) and mDNS (`lib/core/platform/mdns.dart`);
        - the screens: on the phone, nearby PCs, the code, the scanner and home; on the PC, waiting with its QR code, the request sheet and home; Forget in Settings;
        - the Slate motion from the mockups: the live ring around a connected device, the light sweeping the connected card, digits sharpening into focus, and the code lighting up once paired.

        Found on the way:
        - certificate dates must end before 2050 (a 2060 end read back as 1960);
        - four code cells shared one key, which broke the code display; caught by the screen tests.

        78 tests pass, analysis is clean, and the Android and Windows builds pass. The scanner uses Google Play services' barcode model, so the APK stays small.
      - **Checked on the phone and this PC on 2026-11-10** with test builds. The phone build was signed with the release key, as 0.3.1, so v0.4.0 updates over it. All of these worked:
        - the phone found the PC by mDNS;
        - pairing by code with Accept, and pairing by QR code;
        - a rename reaching the phone, and Forget from the phone;
        - the phone linking again 2 to 4 seconds after the PC restarted.

        Two fixes came out of it:
        - the phone's name: MIUI keeps the model code in the standard setting and the real name in the Bluetooth name;
        - a connection reset that went unhandled on the phone.
  - [x] **M2c Text** (M2c1 in PR #7, released as v0.5.0; M2c2 in PR #9, released as v0.6.0): copied text both ways; the phone's copy watcher and its notification; the setup checklist. Plan (2026-11-11), in two pull requests, each a release:
    - **M2c1, the background link and text from the PC:**
      - **One engine for the app's life:** the phone's Flutter engine starts with the app's process and outlives its window, so the link keeps running in the background. A foreground service of type "connected device" holds the ongoing notification.
      - **The notification:** it shows the link's state and has a Send button that reads the clipboard through an invisible screen (proven in M0). It changes to "Sent to <PC>" with no sound.
      - **PC to phone:**
        - A few lines of C++ in the Windows runner listen for clipboard changes and write the phone's text.
        - Gotit's own writes carry a private mark, so they never bounce back. A short memory of recent texts guards the other direction too.
        - Copies that password managers mark "keep away from clipboard watchers" still cross, as sensitive: your decision that passwords cross wins.
        - Sensitive text stays out of Windows clipboard history and is flagged sensitive on Android.
      - **Tray:** a check for about a second when a PC copy reaches the phone.
      - **Checklist (first part):** notifications, and the battery exemption. The exemption also lets the service start again in the background after MIUI kills the app (an official exemption from Android's background-start limit).
      - **Checked on the phone and this PC on 2026-11-11** with test builds (the phone build signed with the release key, as 0.4.2, so the next release updates over it). All of these worked:
        - a PC copy pasted on the phone, with the app open and after it was swiped away from recents (the service and the link stayed up);
        - a phone copy sent with Send and pasted on the PC, with "Sent to" in the notification for a minute;
        - the checklist ticking both steps and then going away.

        Two fixes came out of it:
        - the notification never appeared after notifications were allowed: Android drops a notification posted before that, so the app posts it again whenever its window comes back;
        - MIUI opens its own battery saver page for the exemption and saves "No restrictions" a moment after closing it, so the checklist reads its steps again 1 and 3 seconds after the app comes back.

        99 tests pass and analysis is clean.
    - **M2c2, automatic copies from the phone:**
      - the M0 copy watcher, ported from the test app's source;
      - polling only in apps that don't report taps, learned per app;
      - the checklist's copy-watcher item, with the "Allow restricted settings" tip for apps installed outside a store;
      - Autostart and lock in recents (Xiaomi only, marked done by you);
      - a warning when MIUI has stopped the watcher.
      - **Checked on the phone and this PC on 2026-11-11** with test builds (the phone build signed with the release key, as 0.5.2). All of these worked:
        - the checklist from start to finish: restricted settings, the accessibility switch, Autostart and the lock;
        - six copies, none sent by hand, each on the PC well within a second of being caught: long-press Copy, Brave's Copy link, two WhatsApp copies, and in Google Messages a whole message (found by the screen check) and a number;
        - the watcher staying on through an app update;
        - the warning in the notification and the checklist after a force-stop, clearing once switched back on.

        The watcher used 7 seconds of CPU in 14 minutes, copy tests included. Found and fixed on the way:
        - after a swipe-away without Autostart, Android switched the watcher off altogether (M0 had seen it stay on but crashed), so Gotit also warns when a watcher that ran is switched off;
        - apps can't read "Allow restricted settings" (a `SecurityException`), so App info is offered whenever the watcher is off;
        - MIUI keeps Autostart in its Security app, not in App info, and apps can't open a single accessibility service's page.

        106 tests pass and analysis is clean.

        Also found: the home screen's always-running animations (the live ring and the light sweeping the connected card) cost about 55% of a CPU core while the window is open. A separate fix follows M2c2.
  - [x] **M2d Switch:** the shared switch in the app, the tile, the notification and the tray. Grilled 2026-11-11, one pull request, released as v0.7.0:
    - **Plain on/off:** off stays off until turned on again, from either device, and is remembered across restarts. No timed pause.
    - **Shared:** flipping it on either device, even while the other is away, turns sharing on or off for both; after a reconnect the later change wins (ties by device ID).
    - **Off stops everything:** the copy watcher reads nothing, PC copies don't reach the phone, and the notification's Send becomes Turn on. The link stays up, so either side can turn sharing back on.
    - **App (both):** the mockup's "Sharing" row with a switch under the link card ("Copies cross both ways", or "Paused on both devices"). While off, the status reads "Sharing off", the devices dim, and the ring and sweep don't play.
    - **Phone notification:** Send and Turn off while on; "Sharing off" with Turn on while off.
    - **Quick settings tile:** "Gotit", on or off; unavailable until paired; works while the PC is away.
    - **Adding the tile:** a last checklist step, "Quick settings tile", with Android's own prompt. It counts as done once the prompt was answered either way; Gotit's Settings keeps an Add button.
    - **PC tray:** a Sharing item in the menu, and a greyed tray icon while off.
    - **Checked on the phone and this PC on 2026-11-11** with test builds. All of these worked:
      - adding the tile from the checklist with Android's prompt;
      - turning sharing off and on from the app, the notification's buttons, the tile and the PC tray, each followed by the other device;
      - while off, nothing crossed either way, and the copy watcher read nothing;
      - a change made on the phone while the PC was closed won when the PC came back.

      125 tests pass and analysis is clean.
- [x] **M3 Images:** copied images both ways, and new phone screenshots to the PC. Grilled 2026-11-11, one pull request, released as v0.8.0:
  - **Copied images, both ways, as PNG:** PC to phone covers snips (Win+Shift+S) and "Copy image" in browsers; on the phone the image goes on the clipboard as a file link, so it pastes where apps accept images. Phone to PC: the watcher catches "Copy image" like any copy, and Send sends an image too.
  - **Up to 25 MB:** bigger images stay where they were copied (M4 can send them as files).
  - **Same rules as text:** nothing crosses while sharing is off or the devices are apart, and nothing bounces back.
  - **Phone screenshots:** a new one goes onto the PC's clipboard, with the quiet "Sent to" sign. On by default: a checklist step, "Screenshots to PC", asks for Photos access, and Gotit opens only brand-new files in the Screenshots folder. A Settings switch turns it off.
  - **Built:** image clips (PNG) in the link, whose frames now take 26 MiB, so the link version went to 2; the PC reads the clipboard's PNG or bitmap and writes both PNG and a bitmap, through Windows Imaging Component; the phone reads copied images as PNG off the main thread (skipping anything over 25 MiB or 24 million pixels, which could run it out of memory), writes images through its own read-only provider, and watches the photo library for new screenshots.
  - **Checked on the phone and this PC on 2026-11-12** with test builds, starting from a fresh install (Gotit had been uninstalled from the phone), so pairing and the whole checklist ran again, Photos step included. All of these worked:
    - a phone screenshot on the PC's clipboard (1080x2400), with "Sent to" on the phone;
    - a picture copied on the PC, and a Win+Shift+S snip, pasted on the phone;
    - "Copy image" in a phone browser caught by the watcher and on the PC's clipboard;
    - a screenshot taken while sharing was off staying on the phone;
    - text still crossing both ways.

    One fix came out of it: a screenshot taken while off could still have crossed if sharing came back on within 20 seconds, so one taken while off is now never sent. 135 tests pass and analysis is clean.
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
- 2026-11-10: M1 done.
  - PR #1 added the release pipeline. A build-only run on GitHub built the signed APK and the installer.
  - PR #2 added self-updates and released v0.1.0. Its files were checked after download: checksums, the release certificate, and version 0.1.0 (code 1000).
  - v0.1.0 is installed on the PC and the phone.
  - v0.1.1 leaves out the copies of package:jni's library for other CPUs (0.2 MB), so release APKs are arm64 only. It is also the first update the apps install themselves.
- 2026-11-10: v0.1.1 released. Both apps were put back to 0.1.0 and updated themselves: the PC silently, restarting itself, and the phone through Android's installer. Both then showed "Version 0.1.1 / Updated".
- 2026-11-10: M2 grilled; the decisions are under "Connecting, text and the switch" above. The QR fallback stays in M2, and M2 ships as four pull requests.
- 2026-11-10: Look pass. Round 1 offered Ink, Pulse and Native; you leaned to Pulse but asked for more professional designs with real motion and new icons. Round 2 offered Slate, Aurora and Signal, each animated, plus twelve icon ideas. Picked: Slate with the Catch icon.
- 2026-11-10: M2a merged (PR #4) and released as v0.2.0. Both apps updated themselves and came back in Slate with the Catch icon.
- 2026-11-10: M2b planned in two parts, after checking package versions and testing TLS with self-signed certificates. M2b1, the PC shell, was built and checked on this PC.
- 2026-11-10: M2b1 merged (PR #5, v0.3.0). M2b2 built, tested on both devices, and merged (PR #6, v0.4.0): the phone and the PC pair by code or QR.
- 2026-11-11: M2c planned in two parts (M2c1 background link and text from the PC, M2c2 the automatic copy watcher). Copies that Windows password managers mark as private still cross, as sensitive.
- 2026-11-11: M2c1 built and checked on both devices. Text crosses from the PC by itself and from the phone with Send, also with the app swiped away.
- 2026-11-11: M2c1 merged (PR #7) and released as v0.5.0; both apps updated. The phone app now keeps running in the background, so opening it no longer started an update check: it missed v0.5.0 until restarted. It now checks whenever it comes back to the front, unless it checked in the last 10 minutes.
- 2026-11-11: M2c2 built and checked on the phone: copies made on the phone now reach the PC by themselves. Both dead-watcher cases are covered, after a swipe-away showed Android switching the watcher off rather than leaving it crashed.
- 2026-11-11: M2c2 merged (PR #9) and released as v0.6.0; both apps updated, the phone just by being opened. The update through Android's installer put "Allow restricted settings" back to denied; the watcher stayed on, and the checklist already offers App info if it is ever switched off.
- 2026-11-11: The home screen's live ring and sweep ran forever, costing about 55% of a CPU core while the window was open. They now play when the PC connects and when the app comes back to the front, then rest, and only their own small area redraws: 0% CPU with the window open, measured on the phone.
- 2026-11-11: M2d grilled (plain on/off, the tile offered once in the checklist), built and checked on both devices. With it, M2 is done.
- 2026-11-11: M3 grilled: images both ways up to 25 MB, and phone screenshots to the PC, on by default.
- 2026-11-12: M3 built and checked on both devices, from a fresh install on the phone.
