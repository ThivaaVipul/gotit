#ifndef RUNNER_CLIPBOARD_BRIDGE_H_
#define RUNNER_CLIPBOARD_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <string>

// The PC's clipboard for Gotit: tells Dart about each copy (as "copied" on
// the app.gotit/clipboard channel) and writes what the phone sends ("write").
// Nothing read or written is kept or logged.
class ClipboardBridge {
 public:
  ClipboardBridge(flutter::BinaryMessenger* messenger, HWND window);
  ~ClipboardBridge();

  // Call from the window procedure. True when the message was a clipboard
  // change, now handled.
  bool HandleMessage(UINT message);

 private:
  void OnClipboardChanged();
  bool Write(const std::string& utf8, bool sensitive);

  HWND window_;
  // Marks Gotit's own writes, so they are never reported as new copies.
  UINT own_format_;
  // Set by password managers: "clipboard watchers, look away".
  UINT exclude_format_;
  // A DWORD; 0 keeps a copy out of Windows clipboard history.
  UINT history_format_;
  // A DWORD; 0 keeps a copy off Windows' cloud clipboard.
  UINT cloud_format_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_CLIPBOARD_BRIDGE_H_
