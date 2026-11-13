import 'package:gotit/core/recent/recent.dart';

/// What the recent list can do with an item on this device. The PC opens and
/// shows things in Explorer; the phone opens them and shares them.
abstract interface class RecentActions {
  /// Puts text, a link or an image back on this device's clipboard only.
  /// False when it can't.
  Future<bool> copy(RecentItem item);

  /// Opens [url] in the browser.
  void openLink(String url);

  /// Opens an image or a received file with its usual app.
  void open(RecentItem item);

  /// Shows an item's file in its folder (the PC).
  void reveal(RecentItem item);

  /// Opens the folder received files are in.
  void openFolder(RecentItem item);

  /// Android's share sheet, for an image or received files (the phone).
  void share(RecentItem item);
}
