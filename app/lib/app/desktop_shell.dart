import 'dart:async';
import 'dart:io' show exit;
import 'dart:ui' show Size;

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Gotit on Windows lives in the tray: closing the window hides it, the tray
/// icon brings it back, and the sharing switch and Quit are in the tray menu.
/// The icon is greyed out while sharing is off.
class DesktopShell with TrayListener, WindowListener {
  DesktopShell._();

  static const _open = 'open';
  static const _sharing = 'sharing';
  static const _quit = 'quit';
  static const _icon = 'assets/tray/gotit.ico';
  static const _offIcon = 'assets/tray/gotit-off.ico';
  static const _sentIcon = 'assets/tray/gotit-sent.ico';

  Timer? _sentTimer;
  bool _sharingOn = true;

  /// The tray menu's Sharing item was clicked: turn sharing on or off.
  void Function({required bool on})? onSharing;

  String get _restingIcon => _sharingOn ? _icon : _offIcon;

  /// Sets up the window and the tray. With [hidden] (a start with Windows)
  /// the window stays in the tray until it is opened.
  static Future<DesktopShell> start({required bool hidden}) async {
    final shell = DesktopShell._();
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(shell);
    unawaited(
      windowManager.waitUntilReadyToShow(
        const WindowOptions(
          size: Size(420, 640),
          minimumSize: Size(380, 560),
          center: true,
          title: 'Gotit',
        ),
        () async {
          if (!hidden) await shell.showWindow();
        },
      ),
    );

    trayManager.addListener(shell);
    // The tooltip goes first: tray_manager adds the icon with whatever text it
    // holds, and Windows keeps that first text as the app's name in its list
    // of tray icons. Set it again once the icon exists.
    await trayManager.setToolTip('Gotit');
    await trayManager.setIcon(_icon);
    await trayManager.setToolTip('Gotit');
    await shell._setMenu();
    return shell;
  }

  Future<void> _setMenu() => trayManager.setContextMenu(
    Menu(
      items: [
        MenuItem(key: _open, label: 'Open Gotit'),
        MenuItem.checkbox(key: _sharing, label: 'Sharing', checked: _sharingOn),
        MenuItem.separator(),
        MenuItem(key: _quit, label: 'Quit Gotit'),
      ],
    ),
  );

  /// Shows the sharing switch in the tray: a greyed icon and an unticked
  /// Sharing item while it is off.
  Future<void> showSharing({required bool on}) async {
    if (on == _sharingOn) return;
    _sharingOn = on;
    _sentTimer?.cancel();
    await trayManager.setIcon(_restingIcon);
    await trayManager.setToolTip(on ? 'Gotit' : 'Gotit: sharing off');
    await _setMenu();
  }

  /// Shows the window and brings it to the front.
  Future<void> showWindow() async {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  }

  /// The quiet sign that a copy reached the phone: a check in the tray for
  /// about a second.
  void flashSent() {
    if (!_sharingOn) return;
    _sentTimer?.cancel();
    unawaited(trayManager.setIcon(_sentIcon));
    _sentTimer = Timer(const Duration(milliseconds: 1100), () {
      unawaited(trayManager.setIcon(_restingIcon));
    });
  }

  /// Whether the window is hidden, leaving only the tray icon.
  Future<bool> isInTray() async => !await windowManager.isVisible();

  /// Removes the tray icon, so none is left behind when the app ends.
  Future<void> dispose() async {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    await trayManager.destroy();
  }

  /// Quits for real: the window goes at once, then the tray icon, then the
  /// process. It ends with exit() like the self-update does, because the
  /// engine's own teardown keeps the window on screen for about 9 seconds.
  Future<void> quit() async {
    await windowManager.hide();
    await dispose();
    exit(0);
  }

  @override
  void onWindowClose() => unawaited(windowManager.hide());

  @override
  void onTrayIconMouseDown() => unawaited(showWindow());

  @override
  void onTrayIconRightMouseDown() => unawaited(trayManager.popUpContextMenu());

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _open:
        unawaited(showWindow());
      case _sharing:
        onSharing?.call(on: !_sharingOn);
      case _quit:
        unawaited(quit());
    }
  }
}
