# Gotit

Shares what you copy between an Android phone and a Windows PC on the same Wi-Fi: copied text and images cross over by themselves, files go when you send them. One Flutter app, built for Android and Windows, with small native parts on each side. The design is in `docs/ARCHITECTURE.md`. Progress and decisions are in `docs/PLAN.md`: tick items as they land and log design changes there.

## Commands

```bash
# From app/
flutter pub get
dart format lib test          # CI fails on unformatted code
flutter analyze               # strict mode, must be clean
flutter test
flutter run -d <device>       # a phone (by its adb serial) or "windows"
flutter build apk --debug
flutter build windows --debug
```

```bash
# Release tooling, from the repo root (standard library only)
python -m unittest discover -s scripts/release
python scripts/release/next_release.py      # what the next release would be

# Windows installer, from the repo root in PowerShell, after a release build in app/
#   flutter build windows --release --build-name 0.1.0
& "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe" "/DAppVersion=0.1.0" installer\gotit.iss
```

Dart tests mirror `lib/` under `app/test/`. Build output (`app/build/`, `dist/`) takes gigabytes: delete it after local checks.

## Architecture rules

- Shared Dart lives in `lib/core/`. The link (discovery, pairing, session, protocol), clips, transfers and the switch are plain Dart with no Flutter imports where possible, and are tested without devices (two link ends over localhost TLS in one test).
- Native code is kept to what Dart can't do: on Android (Kotlin) the copy watcher (an accessibility service), clipboard writes, the share target, MediaStore downloads, screenshots and the quick settings tile; on Windows (C++ in the runner) the clipboard listener and formats, file drops on the window and the Ctrl+F2 hotkey.
- Same network only: devices talk directly, no server, no account. Nothing is queued while they're apart.
- Logs never hold what was copied: lengths, kinds and timings only.
- The copy watcher polls the screen only in apps that don't report taps, and only while the screen is on. Everything else is event-driven.
- Updates come only from this repo's GitHub Releases (`lib/core/update/`): every download is checked against `SHA256SUMS.txt` before use, and local builds (version 0.0.0) never update themselves. The PC installs silently; the phone asks first, through Android's own installer.

## Git workflow and releases

- Branches `feat/...`, `fix/...`, `docs/...`, `chore/...` off `main`; a pull request, CI green, then squash merge with a Conventional Commit title.
- The commit type decides the release: `feat` is minor, `fix`/`perf`/`revert` patch, `!` or `BREAKING CHANGE:` major, everything else none. Pick the type honestly. Only commits that change `app/` count toward releases.
- Never create `v*` tags by hand, and never change the version in `app/pubspec.yaml`: release builds get theirs from the release workflow.
- A release (`release.yml`) builds the signed arm64 APK, checks that it carries the release key's certificate, builds the Windows installer (Inno Setup, per user), and publishes both with `SHA256SUMS.txt` as one GitHub Release, where the apps look for updates. Run it by hand with "build only" to test both builds without publishing.
- Release logic lives in `scripts/release/` (Python, standard library only). Change it test-first.
- The signing key stays outside the repo; the workflow gets it from the `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD` secrets and writes `app/android/key.properties` (git-ignored) at build time.
- The installer's `AppId` in `installer/gotit.iss` never changes.

## Constraints

- Fully free: GitHub Free with a public repo (standard runners cost nothing there), no paid services, nothing that needs a card.
- CI (`ci.yml`) stays one quick job on pull requests that runs only the checks for what changed and builds nothing. Before every push, run those checks locally, plus `flutter build apk --debug` when `app/android/` or the pubspec changed and `flutter build windows --debug` when `app/windows/` changed.
- Workflows pin `ubuntu-24.04`. Moving to a newer runner image is its own change, tested first.
- Android 10 (API 29) or later, arm64 release APK. Windows 10 or 11, x64. Installed from GitHub Releases, never a store.
- Add a package only in the change that first uses it. Declare an Android permission only in the change that uses it.
- Check versions and APIs against current docs (Context7) before adding or upgrading a dependency or a GitHub Action.

## Public repo

The repo is public, and whatever it ever held stays public. Keep it free of anything personal:

- No names, places, phone models, network details or email addresses, and no other projects, in code, comments, docs, commits or pull requests.
- Test data is synthetic: no real clipboard contents, files or device identifiers.
- Secrets live only in GitHub's encrypted secrets; signing keys and `key.properties` never enter the repo. Workflows never use `pull_request_target`, so pull requests from forks get no secrets.

## Conventions

- Flutter: app shell in `lib/app/`, shared code in `lib/core/`, feature-first folders (`lib/features/<feature>/` with `cubit/`, `view/` and `widgets/`), package imports, one Cubit per screen once screens have state.
- UI: Material 3, minimal and calm, short labels, no explanatory paragraphs on screens. After the look pass, colours and text styles come from the theme; widgets don't hard-code either. English only.
- Motion: purposeful and quick, with shared durations and curves from the theme. Respect `MediaQuery.disableAnimations`.
- Plain ASCII punctuation in code, comments, docs and commits (generated files aside): no em or en dashes, arrows, smart quotes or emoji.
- Line endings are LF (enforced by `.gitattributes`).
- Commits: small, imperative subject. Never commit or push without asking.

## Claude tooling

Installed for this project (`.claude/settings.json`, `.claude/skills/`). Use the matching skill before the work it covers. In a session started outside this folder they don't load by themselves: read the SKILL.md at the path below and follow it.

| Work | Skill | SKILL.md |
| --- | --- | --- |
| Layers, routing, layout fixes, widget/integration tests, static analysis, runtime errors | dart-flutter plugin (`flutter-*`, `dart-*`) | `~/.claude/plugins/cache/dart-flutter/dart-flutter/<version>/skills/<name>/` |
| Animations, transitions, springs, reduced motion | flutter-animations | `.claude/skills/flutter-animations/` |
| Colours, type, UX and accessibility review | ui-ux-pro-max (run its `scripts/search.py` with Python) | `~/.claude/plugins/cache/ui-ux-pro-max-skill/ui-ux-pro-max/<version>/.claude/skills/ui-ux-pro-max/` |

Project rules win where a skill disagrees.

Hot reload (the Flutter team's rule): after editing a `.dart` file under `app/lib/` while the app is running, hot reload through the Dart MCP server; hot restart when `initState`, global state or `main()` changed. Skip it for comment-only edits and for files outside `lib/`.

## Testing on a device

- Ask before installing on a phone, and before any adb command against it. With several devices connected, always pass the phone's serial.
- Copy-watching, clipboard writes and staying alive under the maker's battery rules are checked on a real phone; the link and the protocol are checked in tests.
