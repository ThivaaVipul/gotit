#include "notices_bridge.h"

#include <flutter/standard_method_codec.h>
#include <roapi.h>
#include <shellapi.h>
#include <windows.data.xml.dom.h>
#include <windows.foundation.h>
#include <wrl/event.h>
#include <wrl/implements.h>
#include <wrl/wrappers/corewrappers.h>

#include <cstdint>
#include <variant>

using ABI::Windows::Data::Xml::Dom::IXmlDocument;
using ABI::Windows::Data::Xml::Dom::IXmlDocumentIO;
using ABI::Windows::Foundation::DateTime;
using ABI::Windows::Foundation::IPropertyValueStatics;
using ABI::Windows::Foundation::IReference;
using ABI::Windows::Foundation::ITypedEventHandler;
using ABI::Windows::UI::Notifications::IToastNotification;
using ABI::Windows::UI::Notifications::IToastNotification2;
using ABI::Windows::UI::Notifications::IToastNotificationFactory;
using ABI::Windows::UI::Notifications::IToastNotificationManagerStatics;
using ABI::Windows::UI::Notifications::IToastNotifier;
using ABI::Windows::UI::Notifications::ToastNotification;
using Microsoft::WRL::Callback;
using Microsoft::WRL::ClassicCom;
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::Implements;
using Microsoft::WRL::RuntimeClassFlags;
using Microsoft::WRL::Wrappers::HStringReference;

namespace {

// The app ID on Gotit's Start menu shortcut, which Windows needs for toasts.
constexpr wchar_t kAppId[] = L"Gotit";

// How long a link's toast stays, in 100-nanosecond ticks: 5 minutes.
constexpr int64_t kLifetime = 5LL * 60 * 10000000;

std::wstring ToUtf16(const std::string& text) {
  if (text.empty()) return std::wstring();
  int size = MultiByteToWideChar(CP_UTF8, 0, text.data(),
                                 static_cast<int>(text.size()), nullptr, 0);
  std::wstring out(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      out.data(), size);
  return out;
}

// |text| made safe inside XML.
std::wstring Escape(const std::wstring& text) {
  std::wstring out;
  out.reserve(text.size());
  for (wchar_t c : text) {
    switch (c) {
      case L'&':
        out += L"&amp;";
        break;
      case L'<':
        out += L"&lt;";
        break;
      case L'>':
        out += L"&gt;";
        break;
      case L'"':
        out += L"&quot;";
        break;
      case L'\'':
        out += L"&apos;";
        break;
      default:
        out += c;
    }
  }
  return out;
}

std::string Text(const flutter::EncodableMap& args, const char* key) {
  auto found = args.find(flutter::EncodableValue(key));
  if (found == args.end()) return std::string();
  const auto* value = std::get_if<std::string>(&found->second);
  return value ? *value : std::string();
}

bool IsWebLink(const std::wstring& url) {
  return url.rfind(L"https://", 0) == 0 || url.rfind(L"http://", 0) == 0;
}

template <typename T>
HRESULT Factory(const wchar_t* name, size_t length, ComPtr<T>& factory) {
  return RoGetActivationFactory(
      HStringReference(name, static_cast<unsigned int>(length)).Get(),
      __uuidof(T), reinterpret_cast<void**>(factory.GetAddressOf()));
}

}  // namespace

NoticesBridge::NoticesBridge(flutter::BinaryMessenger* messenger, HWND window)
    : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "app.gotit/notices",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "link") {
          result->NotImplemented();
          return;
        }
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        if (!args) {
          result->Error("args", "No arguments");
          return;
        }
        const std::wstring url = ToUtf16(Text(*args, "url"));
        if (!IsWebLink(url)) {
          result->Error("args", "Not a web link");
          return;
        }
        if (ShowLink(ToUtf16(Text(*args, "title")),
                     ToUtf16(Text(*args, "text")), url)) {
          result->Success();
        } else {
          result->Error("toast", "Not shown");
        }
      });
}

NoticesBridge::~NoticesBridge() {
  channel_->SetMethodCallHandler(nullptr);
  ForgetLast();
}

bool NoticesBridge::HandleMessage(UINT message, LPARAM lparam) {
  if (message != kOpenMessage) return false;
  std::unique_ptr<std::wstring> url(reinterpret_cast<std::wstring*>(lparam));
  if (url && IsWebLink(*url)) {
    ShellExecuteW(nullptr, L"open", url->c_str(), nullptr, nullptr,
                  SW_SHOWNORMAL);
  }
  return true;
}

void NoticesBridge::ForgetLast() {
  if (last_) {
    last_->remove_Activated(activated_);
    last_.Reset();
  }
}

bool NoticesBridge::ShowLink(const std::wstring& title,
                             const std::wstring& text,
                             const std::wstring& url) {
  // Two lines, an Open button, and no sound.
  const std::wstring xml =
      L"<toast activationType=\"foreground\"><visual>"
      L"<binding template=\"ToastGeneric\"><text>" +
      Escape(title) + L"</text><text>" + Escape(text) +
      L"</text></binding></visual><actions>"
      L"<action content=\"Open\" arguments=\"open\" "
      L"activationType=\"foreground\"/></actions>"
      L"<audio silent=\"true\"/></toast>";

  ComPtr<IInspectable> made;
  if (FAILED(RoActivateInstance(
          HStringReference(RuntimeClass_Windows_Data_Xml_Dom_XmlDocument).Get(),
          &made))) {
    return false;
  }
  ComPtr<IXmlDocument> document;
  ComPtr<IXmlDocumentIO> io;
  if (FAILED(made.As(&document)) || FAILED(document.As(&io)) ||
      FAILED(io->LoadXml(
          HStringReference(xml.c_str(), static_cast<unsigned int>(xml.size()))
              .Get()))) {
    return false;
  }

  ComPtr<IToastNotificationFactory> toasts;
  ComPtr<IToastNotification> toast;
  if (FAILED(Factory(RuntimeClass_Windows_UI_Notifications_ToastNotification,
                     wcslen(RuntimeClass_Windows_UI_Notifications_ToastNotification),
                     toasts)) ||
      FAILED(toasts->CreateToastNotification(document.Get(), &toast))) {
    return false;
  }

  // The newest link replaces the last.
  ComPtr<IToastNotification2> tagged;
  if (SUCCEEDED(toast.As(&tagged))) {
    tagged->put_Tag(HStringReference(L"link").Get());
    tagged->put_Group(HStringReference(L"gotit").Get());
  }

  // Gone by itself after 5 minutes, from the notification centre too.
  ComPtr<IPropertyValueStatics> values;
  if (SUCCEEDED(Factory(RuntimeClass_Windows_Foundation_PropertyValue,
                        wcslen(RuntimeClass_Windows_Foundation_PropertyValue),
                        values))) {
    FILETIME now;
    GetSystemTimeAsFileTime(&now);
    DateTime expiry;
    expiry.UniversalTime =
        ((static_cast<int64_t>(now.dwHighDateTime) << 32) |
         now.dwLowDateTime) +
        kLifetime;
    ComPtr<IInspectable> boxed;
    ComPtr<IReference<DateTime>> when;
    if (SUCCEEDED(values->CreateDateTime(expiry, &boxed)) &&
        SUCCEEDED(boxed.As(&when))) {
      toast->put_ExpirationTime(when.Get());
    }
  }

  // Open, or a click on the toast: the link opens on the window's thread.
  HWND window = window_;
  std::wstring target = url;
  EventRegistrationToken token{};
  const HRESULT listened = toast->add_Activated(
      Callback<Implements<RuntimeClassFlags<ClassicCom>,
                          ITypedEventHandler<ToastNotification*, IInspectable*>>>(
          [window, target](IToastNotification*, IInspectable*) -> HRESULT {
            auto* link = new std::wstring(target);
            if (!PostMessageW(window, kOpenMessage, 0,
                              reinterpret_cast<LPARAM>(link))) {
              delete link;
            }
            return S_OK;
          })
          .Get(),
      &token);
  if (FAILED(listened)) return false;

  ComPtr<IToastNotificationManagerStatics> manager;
  ComPtr<IToastNotifier> notifier;
  if (FAILED(Factory(
          RuntimeClass_Windows_UI_Notifications_ToastNotificationManager,
          wcslen(RuntimeClass_Windows_UI_Notifications_ToastNotificationManager),
          manager)) ||
      FAILED(manager->CreateToastNotifierWithId(HStringReference(kAppId).Get(),
                                                &notifier)) ||
      FAILED(notifier->Show(toast.Get()))) {
    toast->remove_Activated(token);
    return false;
  }
  ForgetLast();
  last_ = toast;
  activated_ = token;
  return true;
}
