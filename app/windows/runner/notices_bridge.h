#ifndef RUNNER_NOTICES_BRIDGE_H_
#define RUNNER_NOTICES_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>
#include <windows.ui.notifications.h>
#include <wrl/client.h>

#include <memory>
#include <string>

// Toasts Dart's toast package can't make quiet (it always plays a sound): a
// link that arrived from the phone, on the app.gotit/notices channel as
// "link" with a title, the link as shown, and the URL. No sound; the newest
// replaces the last; Windows takes it away after 5 minutes. Open, or a click
// on the toast, opens the link in the browser.
class NoticesBridge {
 public:
  // The window message that carries a link to open on the window's thread:
  // a std::wstring* in lParam, which the receiver deletes.
  static constexpr UINT kOpenMessage = WM_APP + 0x4C;

  // |window| gets kOpenMessage.
  NoticesBridge(flutter::BinaryMessenger* messenger, HWND window);
  ~NoticesBridge();

  // Call from the window procedure. True when the message was a link to
  // open, now opened.
  bool HandleMessage(UINT message, LPARAM lparam);

 private:
  bool ShowLink(const std::wstring& title, const std::wstring& text,
                const std::wstring& url);
  void ForgetLast();

  HWND window_;
  // The last toast, kept so its Open still works.
  Microsoft::WRL::ComPtr<ABI::Windows::UI::Notifications::IToastNotification>
      last_;
  EventRegistrationToken activated_{};
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_NOTICES_BRIDGE_H_
