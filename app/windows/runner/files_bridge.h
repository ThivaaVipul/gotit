#ifndef RUNNER_FILES_BRIDGE_H_
#define RUNNER_FILES_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <string>
#include <vector>

class FileDropTarget;

// Files for Gotit to send, on the app.gotit/files channel: dropped on the
// window ("dragging" while they hover, then "dropped" with their paths), and
// Ctrl+F2 ("hotkey" with the files copied in Explorer, or none). Dart asks
// "hotkey" to learn whether Ctrl+F2 is Gotit's; another app may hold it.
class FilesBridge {
 public:
  // |window| gets WM_HOTKEY; |view| is the Flutter view that takes drops.
  FilesBridge(flutter::BinaryMessenger* messenger, HWND window, HWND view);
  ~FilesBridge();

  // Call from the window procedure. True when the message was Gotit's
  // hotkey, now handled.
  bool HandleMessage(UINT message, WPARAM wparam);

  // From the drop target.
  void Dragging(bool hovering);
  void Dropped(const std::vector<std::wstring>& paths);

 private:
  void Send(const std::string& method, const std::vector<std::wstring>& paths);

  HWND window_;
  HWND view_;
  bool hotkey_ = false;
  FileDropTarget* drop_target_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_FILES_BRIDGE_H_
