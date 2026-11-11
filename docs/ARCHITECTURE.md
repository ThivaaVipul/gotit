# Gotit architecture

Status: **draft (2026-11-09), ready for review.** The phone-to-PC copy part is updated with M0's results, and the look with M2a's (2026-11-10). Package versions are from pub.dev on 2026-11-09 and get checked against current docs before each is added.

## Overview

One Flutter app, built for Android and Windows. Most of the code is shared Dart; each platform adds a thin native layer for what Dart can't do.

```
 Phone (Android)                               PC (Windows)
 +----------------------------------+          +----------------------------------+
 | Flutter UI                       |          | Flutter UI (small tray window)   |
 | Link task (foreground service)   |<- TLS ->-| Link server                      |
 |   shared Dart: link, clips,      |  same    |   shared Dart: link, clips,      |
 |   files, switch, recent list     |  Wi-Fi   |   files, switch, recent list     |
 | Kotlin: copy watcher, clipboard  |          | C++ runner: clipboard listener,  |
 |   writes, tile, share sheet,     |          |   clipboard formats, images      |
 |   screenshots, updates           |          | Packages: tray, hotkey, drop,    |
 +----------------------------------+          |   single instance, start at login|
                                               +----------------------------------+
```

The PC is the server: it is plugged in, on one network and always on. The phone finds it with mDNS and keeps one connection open while both are on the same Wi-Fi.

## Repo layout

```
app/                    the Flutter app (android/ and windows/ runners)
  lib/app/              shell, routes, theme
  lib/core/link/        discovery, pairing, session, protocol (plain Dart)
  lib/core/clip/        clip model, echo guard, sensitive rules (plain Dart)
  lib/core/transfer/    file send and receive, zipping folders
  lib/core/state/       the shared switch, the recent list, settings
  lib/core/platform/    Dart side of the native channels
  lib/features/         home, pairing, setup guide, settings
  test/                 mirrors lib/; the link is tested end to end on localhost
installer/              Inno Setup script for the Windows installer
scripts/release/        version and release notes from Conventional Commits
.github/workflows/      ci.yml (pull requests), release.yml (main)
docs/                   PLAN.md, ARCHITECTURE.md
docs/brand/             the icon's sources (SVG)
```

## Look

Slate, picked in the look pass on 2026-11-10: dark-first and precise, with an indigo-to-violet gradient for anything live. Light and dark follow the system.

- **Where it lives:** `lib/app/theme/`.
  - `GotitColors` is the palette, kept as a theme extension.
  - `GotitMotion` holds the timings.
  - `gotitTheme(brightness)` builds Material 3 on top of both.

  Widgets take colours, text styles and timings from these, never hard-coded values.
- **Palette:**

  | Token | Light | Dark | Used for |
  | --- | --- | --- | --- |
  | bg | `#F7F7F9` | `#0A0B0E` | window and screen background |
  | surface | `#FFFFFF` | `#111318` | cards and lists |
  | surface2 | `#F1F2F5` | `#181B22` | raised surfaces, tracks |
  | fg | `#0B0C10` | `#ECEEF2` | text |
  | muted | `#5F6576` | `#8A90A2` | secondary text and icons |
  | line | `#E4E5EA` | `#22262F` | hairlines and borders |
  | accent | `#4F5BEF` | `#7C86FF` | actions, links, live things |
  | accent2 | `#8B5CF6` | `#B18CFF` | the violet end of the live gradient |
  | ok | `#12A150` | `#3DD68C` | connected, done |

- **Type:** Inter 4.1 in four static weights (400, 500, 600, 700).
  - Each is subset to Latin with fonttools' `pyftsubset`: Basic Latin through Latin Extended-A, plus punctuation, currency signs and arrows. Layout features are kept, so tabular figures work. That brings each weight to about 110 KB.
  - Other scripts fall back to the system font.
  - The font's licence (`assets/fonts/OFL.txt`) ships with it and appears on the app's licence page.
- **Shape:** 12 px corners on cards, 10 px on controls, 1 px hairlines, no shadows.
- **Motion** (`GotitMotion`). When the system asks for less motion, every duration is zero and loops stop.

  | Motion | Time | Curve | Where |
  | --- | --- | --- | --- |
  | A copy crossing | 900 ms | `move` (easeInOutCubic) | a light beam along the link, then a small bump on the other device |
  | Switch | 320 ms | `spring` (easeOutBack) | sharing on and off |
  | Arrive | 280 ms | `arrive` (easeOutCubic) | notes, new recent items, toasts |
  | Leave | 180 ms | `leave` (easeInCubic) | the same, going away |
  | Tick | 300 ms | `move` | setup checks drawing in, progress growing |
  | Stagger | 70 ms apart | | pairing digits sharpening into focus |
  | Catch | 1 s | | the icon's ball flying in, once, on the home screen |
  | Live ring | 2.4 s, 3 beats | | around the other device when it connects and when the app comes back to the front, then gone |
  | Sweep | 6 s, one turn | linear | a light circling the connected card at the same moments, then resting as a glint |

- **Icon: Catch,** a ball flying into a C-shaped catch: a white C, two trail lines and an indigo ball on a slate tile.
  - **Sources:** `docs/brand/icon.svg` (the tile) and `docs/brand/glyph.svg` (one colour).
  - **Android:** a vector adaptive icon with no PNGs. It has the gradient background, the glyph in front, and a monochrome layer for Android 13's themed icons. The splash is the icon on the theme's background.
  - **Windows:** `windows/runner/resources/app_icon.ico`, 16 to 256 px, which is also the installer's icon. It is made by rendering `icon.svg` at 1024 px on a transparent background and saving it as an ICO with Pillow.
  - **In the app:** `CatchMark` draws the icon in Flutter and plays the catch once on the home screen.

## The link

Built in M2b2, as plain Dart in `lib/core/link/`, and tested end to end with two link ends talking TLS over localhost.

- **Discovery** (`bonsoir` 7.1.5; `lib/core/platform/mdns.dart`):
  - The PC advertises `_gotit._tcp` under its name, with its device ID and link version in the TXT record.
  - The phone browses while the app runs: to list PCs before pairing, and to find the paired PC again if its address changes. It also remembers the last address that worked.
  - Only resolved IPv4 addresses, and IPv6 ones that aren't link-local, are dialled.
- **Identity** (`identity.dart`):
  - On first run each device makes an EC P-256 key and a self-signed certificate with `basic_utils` 5.8.2 (pure Dart, off the UI thread).
  - It is kept sealed in the app's own folder (`lib/core/platform/secrets.dart`):
    - on the PC, by DPAPI through `win32` (only this Windows user can open it);
    - on the phone, by an AES-GCM key that never leaves the Android Keystore (`Sealer.kt`).

    `flutter_secure_storage` was the plan, but its Windows part needs Visual Studio's ATL headers. The app has no cloud backup, since a restored key wouldn't open anyway.
  - The certificate is valid from 2020 to the end of 2049. Clocks that disagree can't make it look not yet valid, and 2049 is the last year a certificate stores in two digits. A 2060 end date reads back as 1960, which made every certificate look expired.
- **One TLS port** (`pc_link.dart`), 47331 when free, with any free port as a fallback.
  - The PC asks every connection for a client certificate but doesn't require one.
  - A phone that is pairing shows none and can only ask to pair.
  - The paired phone shows its pinned certificate: TLS checks it against the PC's trust list, then the PC checks the pin as well.
  - A certificate the PC doesn't trust ends the handshake. Pairing adds the new phone to the live trust list, so no restart is needed.
- **Pairing, by tap** (`phone_link.dart`, `pairing.dart`):
  1. The phone connects without a certificate and records the PC's certificate.
  2. Inside TLS it sends `pair.req` with its ID, name, certificate and link version.
  3. The PC answers `pair.wait`. Both now show the same 4-digit code, made from a hash of both certificates' fingerprints. A device in the middle has its own certificate, so the two codes wouldn't match (1 in 10,000).
  4. Accept on the PC sends `pair.ok`, and each side keeps the other's certificate. Decline, 60 seconds without an answer, or a second phone asking at the same time ends it with `pair.no`.
  5. Pairing again replaces the old pair: it is one to one.
- **Pairing, by QR code:**
  - The PC's code holds its addresses, port, certificate fingerprint and a one-time token that lasts 5 minutes.
  - The phone connects only to a PC with that fingerprint and sends the token, and the PC pairs at once, with no code and no Accept. A used or expired token gets `pair.no`.
- **Session:**
  - Mutual TLS, then a `hello` from each side with its ID, name and link version (`LinkSpec.version`, now 1).
  - Different versions keep the link up but share nothing, and both screens say which device to update.
  - A ping every 30 seconds, and 75 seconds of silence counts as a lost link.
  - The phone reconnects with backoff (1, 2, 5, 10, 20, then every 30 seconds), and tries again at once when the app comes to the front or mDNS sees the PC.
  - Forget on either side sends `bye`, and the other side forgets too.
- **Frames** (`frame.dart`):
  - Each frame is a 4-byte header length, a JSON header whose `t` is the type, a 4-byte body length, and the body.
  - Headers are capped at 64 KiB and bodies at 2 MiB. Anything malformed ends the connection.

  | Frame | Carries |
  | --- | --- |
  | `pair.req`, `pair.wait`, `pair.ok`, `pair.no` | pairing, above |
  | `hello` | device ID, name and link version |
  | `bye` | the other side forgot this pairing |
  | `ping`, `pong` | liveness |
  | `switch` (M2d) | on or off, when it changed, which device changed it |
  | `clip` (M2c, M3) | text or PNG image, copied-at time, a sensitive flag, a link flag |
  | `file.offer`, `file.chunk`, `file.done` (SHA-256), `file.cancel` (M4) | a file in 256 KiB chunks |

  Text clips are capped at 1 MiB. A bigger image goes as a file.
- **Live only:** nothing is queued. A copy made while the two aren't connected is dropped (PLAN decision).
- **Echo guard:** the receiving side remembers the fingerprint of each clip it writes. When its own watcher then sees that change, it doesn't send it back. On Windows, Gotit's own writes also carry a private clipboard format.

## The switch

- **State:** `{on, changedAt, by}` (`lib/core/sharing/`), kept in each device's settings. Each time the link comes up, both send their state in a `sharing` frame, and the later change wins (ties go by device ID). Flipping the switch on either side sends the frame too; flipped while apart, it crosses on the next link-up. An older peer ignores the frame, so the link version didn't change.
- **While off:**
  - Copies are dropped both ways (the clip bridge checks the switch on both sides), and the phone's copy watcher reads nothing. Screenshots and files will be refused; sending a file offers "Turn on and send".
  - The link itself stays up, so either side can turn sharing back on.
  - The home screens say "Sharing off": the other device dims, and the ring and sweep don't play.
  - On the phone, the ongoing notification reads "Sharing off" with a Turn on button (Send and Turn off while on). On the PC, the tray icon is greyed out (`assets/tray/gotit-off.ico`, made from `gotit.ico` in greyscale) and the menu's Sharing item is unticked.
- **Outside the app on the phone:** Dart owns the switch. Kotlin keeps a copy (`Sharing`, also saved, so it is right before Dart starts) for the quick settings tile and the copy watcher. Taps on the tile and the notification's buttons go back to Dart; a tile tap that starts the app waits in Kotlin until Dart listens. The tile is unavailable until paired and works while the PC is away. Android 13's own "Add tile?" prompt is offered once in the setup checklist and again in Settings.

## Phone app (Android)

- **Background:** the Flutter engine starts with the app's process and outlives its window, and a small Kotlin foreground service (`LinkService`, type `connectedDevice`) keeps the process running while paired. That service owns the ongoing notification, which has Send and, from M2d, the switch. The guided setup covers notifications, MIUI's Autostart and battery set to "No restrictions", so Doze doesn't cut the connection.
- **Phone to PC (copies),** as proven in M0:
  - **Watching:** an accessibility service (Kotlin) looks for three signals:
    - a tap on a Copy label (a long label that starts with "Copy" counts too);
    - a "copied" notice;
    - a Copy item leaving the screen.
  - **Reading:** once a signal fires, the service reads the clipboard through a 1-pixel invisible accessibility overlay that takes focus for a moment. An invisible activity is the backup. It reads only while paired (the link service is running).
  - **Which reads count:** a clip copied more than 3 seconds before the signal is the previous one, so it gets one more look 0.7 seconds later and is otherwise dropped. Gotit's own writes (text from the PC, labelled "Gotit") never go back, and one copy that fires several signals crosses once.
  - **Polling:** some apps never report taps (Compose and Flutter apps; Google Messages' message menu announces nothing at all). Those get a light screen check about 3 times a second while they're in front, and on their screen changes. Gotit learns which apps those are: an app that has reported a tap isn't checked, unless a copy there was once caught only by the screen check. Google Messages is always checked. Popup windows with a Copy item are tracked in every app, since that costs little. Polling everything cost about 6% of a CPU core.
  - **Handing over:** the service runs in the app's process and passes each clip to Dart through the clipboard channel, where the same guard as Send applies.
  - **Setup:** the guided setup asks for:
    - the accessibility main switch (not its shortcut);
    - Autostart;
    - the battery set to No restrictions;
    - the lock in recents.
  - **The checklist** reads the watcher's state. On Android 13 and later the switch may be greyed out until "Allow restricted settings" is chosen in App info. Apps can't read that setting (asking throws a `SecurityException`), so while the watcher is switched off the checklist offers App info, with a hint until the watcher has run once. Autostart (MIUI's list in its Security app) and the lock are Xiaomi only, and you mark them done yourself, since no app can read them.
  - **A dead watcher:** a swipe-away without Autostart force-stops the app. Android then either marks the service as crashed (switched on, not running; seen in M0) or switches it off altogether (seen in M2c2). Gotit spots both: switched on but not running 20 seconds after the process started, or switched off after it had run. It says so in the ongoing notification and the checklist, and opens the switch in one tap.
  - **The Send button:** the notification's Send button always works, through the invisible activity.
- **PC to phone (copies):** the link task writes the clipboard from the service. Text goes in as plain text. An image is saved to the app's cache, and its content URI is put on the clipboard through a `FileProvider`, so apps that accept images can paste it.
- **Screenshots:** a `ContentObserver` on MediaStore picks up new files in the Screenshots folder (photo access: `READ_MEDIA_IMAGES`) and sends each one as an image clip.
- **Files:**
  - Sending: a transparent share target activity receives the share sheet's items and passes their content URIs to the link task, which streams them.
  - Receiving: received files go to `Download/Gotit` through MediaStore, with no storage permission needed. A notification offers Open and Share.
- **Quick settings tile:** the switch.

## PC app (Windows)

- **Window and tray** (`lib/app/desktop_shell.dart`, M2b1):
  - **Packages:** `tray_manager` 0.5.3 and `window_manager` 0.5.2. Newer releases need Flutter 3.47, and `tray_manager` 0.6 was withdrawn.
  - **Window:** the runner no longer shows the window by itself. Dart shows it, unless Gotit started with Windows (`--hidden`), when it stays in the tray. Closing the window hides it.
  - **Tray:** clicking the icon brings the window back, and the menu has Open, the Sharing switch (ticked while on) and Quit. The icon is greyed out while sharing is off. Windows 11 puts a new tray icon in the overflow (the ^ arrow) until you drag it out or turn it on under Settings, Taskbar, Other system tray icons.
  - **Two quirks, handled:**
    - `tray_manager` adds the icon with whatever tooltip text it holds, and Windows keeps that first text as the app's name in its tray-icon list. So the tooltip is set before the icon.
    - The engine's own teardown keeps the window on screen for about 9 seconds after a normal quit. So Quit hides the window, removes the tray icon and ends with `exit()`, as the self-update already does.
  - **Updates:** the self-update passes `/RUNARGS=--hidden` to the setup when Gotit was in the tray, so the new version starts there too.
- **Clipboard:** a small C++ plugin in the runner.
  - It listens with `AddClipboardFormatListener` (`WM_CLIPBOARDUPDATE`).
  - It reads text (`CF_UNICODETEXT`), images (the `PNG` format, or `CF_DIBV5` converted to PNG with WIC) and file lists (`CF_HDROP`), and writes text and images back.
  - A copy carrying `ExcludeClipboardContentFromMonitorProcessing`, or with `CanIncludeInClipboardHistory` set to 0, counts as sensitive and still crosses (the PLAN decision that passwords cross wins over the mark).
  - No Rust and no extra packages.
- **Sending files:**
  - Drag onto the window: `desktop_drop` 0.9.2.
  - Explorer's Send to: the installer adds a "Gotit" shortcut to the SendTo folder. Its second launch hands the paths to the running app through `windows_single_instance` 1.2.0 (in since M2b1, where a second launch shows the running window), then exits.
  - The hotkey: `hotkey_manager` 0.3.0 registers it, and the C++ plugin reads the copied file list. Folders are zipped before sending.
- **Receiving files:** received files go to `Downloads\Gotit`. A toast with Open comes through `flutter_local_notifications` 23.0.0, whose Windows part supports buttons. Toasts need the installer's Start menu shortcut with Gotit's AppUserModelID.
- **Start with Windows** (`lib/core/platform/start_with_windows.dart`, M2b1):
  - **How:** a value named Gotit in the per-user Run key, written with `win32_registry` 3.0.3. No admin is needed. (`launch_at_startup` needs an older `win32` than `package_info_plus` does, so it can't be used.)
  - **Default:** the first launch of an installed copy turns it on. After that the setting in Settings sticks, and each launch rewrites the value so the path stays current.
  - **Local builds** (0.0.0) never touch the Run key.
  - **Uninstall:** the uninstaller removes the value.
- **Package check:** the leanflutter desktop packages are moving to native code built by build hooks, in releases that need Flutter 3.47. Gotit stays on their classic releases until it moves Flutter. M2b1's release proves they build on GitHub's Windows runner with the C++ tools alone.

## What each device keeps

- Its identity (key and certificate), in the platform's secure storage, and in `settings.json` the paired device's ID, name and certificate (plus, on the phone, the PC's last address).
- The switch state.
- The recent list: the last 20 items as JSON, holding kind, direction, time, a short preview (never for sensitive items) and the file location. Sensitive items are dropped after a minute.
- Settings (`settings.json` in the app's support folder): the PC's name, start with Windows, and later the hotkey.

Nothing else is stored, and nothing leaves the local network except the update check with GitHub. Logs never hold what was copied.

## Updates and releases

- **Versions:** a push to main with a `feat` or `fix` commit releases. `scripts/release` reads the Conventional Commits. Android's version code is `major * 1000000 + minor * 1000 + patch`.
- **`release.yml`:**
  - One job builds the signed arm64 APK on `ubuntu-24.04`, with the signing key in GitHub secrets.
  - Another builds the Windows app and its Inno Setup installer on a Windows runner. Is Inno Setup preinstalled on the image? M1 checks.
  - A last job publishes one GitHub Release with `gotit-<v>.apk`, `gotit-<v>-setup.exe` and `SHA256SUMS.txt`.
- **In-app updates:** both apps check GitHub's latest release every 6 hours and when asked. A download is checked against `SHA256SUMS.txt`.
  - Android hands the APK to the system installer (`REQUEST_INSTALL_PACKAGES`).
  - Windows runs the installer silently, and the installer starts Gotit again. A file the app downloads itself carries no "downloaded from the internet" mark, so SmartScreen warns only on the very first install from the browser.

## Testing

- **Plain Dart, no devices:** the link, the protocol framing, pairing codes, the switch merge, the echo guard and the recent list rules. Two link ends talk over localhost TLS inside one test.
- **Platform code:** checked by hand on the phone and this PC at each milestone, with logs that never hold clip contents.
- **CI on pull requests:** one quick Ubuntu job (format, analyze, tests). Windows and Android builds run locally before a push and in the release workflow.

## To check before or during M1 and M2

- Mutual TLS with self-signed certificates in `dart:io`: each side trusting exactly the other's certificate, on both platforms.
- `bonsoir` on Windows. Advertising uses the DNS-SD API in Windows 10 and later.
- The leanflutter packages' build hooks on the Windows runner, and Inno Setup on the runner image.
- How Doze treats the connection over a long idle stretch, with and without the battery exemption. (The `connectedDevice` service itself was checked on Android 13 under MIUI in M2c1, including a swipe-away.)
- The battery cost of the copy watcher over a normal day, polling only the apps that need it.
