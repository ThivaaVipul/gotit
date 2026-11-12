import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Opens [path] with its usual app, as a double-click in Explorer would.
void openPath(String path) => using((arena) {
  ShellExecute(
    null,
    arena.pcwstr('open'),
    arena.pcwstr(path),
    null,
    null,
    SW_SHOWNORMAL,
  );
});

/// Opens Explorer with [path] selected.
void revealPath(String path) => using((arena) {
  ShellExecute(
    null,
    arena.pcwstr('open'),
    arena.pcwstr('explorer.exe'),
    arena.pcwstr('/select,"$path"'),
    null,
    SW_SHOWNORMAL,
  );
});
