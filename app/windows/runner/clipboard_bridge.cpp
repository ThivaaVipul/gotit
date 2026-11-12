#include "clipboard_bridge.h"

#include <flutter/standard_method_codec.h>

#include "image_codec.h"

#include <chrono>
#include <cstring>
#include <optional>
#include <variant>

namespace {

// The biggest image that crosses; Dart checks the same.
constexpr size_t kMaxImageBytes = 25 * 1024 * 1024;

std::string ToUtf8(const wchar_t* text, int length) {
  if (length <= 0) return std::string();
  int size = WideCharToMultiByte(CP_UTF8, 0, text, length, nullptr, 0, nullptr,
                                 nullptr);
  std::string out(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, text, length, out.data(), size, nullptr,
                      nullptr);
  return out;
}

std::wstring ToUtf16(const std::string& text) {
  if (text.empty()) return std::wstring();
  int size = MultiByteToWideChar(CP_UTF8, 0, text.data(),
                                 static_cast<int>(text.size()), nullptr, 0);
  std::wstring out(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      out.data(), size);
  return out;
}

// Another program may hold the clipboard for a moment.
bool OpenWithRetry(HWND window) {
  for (int attempt = 0; attempt < 10; ++attempt) {
    if (OpenClipboard(window)) return true;
    Sleep(15);
  }
  return false;
}

// Global memory holding a copy of |bytes|, for SetClipboardData.
HGLOBAL CopyToGlobal(const void* bytes, size_t size) {
  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, size);
  if (!memory) return nullptr;
  void* target = GlobalLock(memory);
  if (!target) {
    GlobalFree(memory);
    return nullptr;
  }
  std::memcpy(target, bytes, size);
  GlobalUnlock(memory);
  return memory;
}

// Sets |format| to |memory|; the clipboard owns it on success.
void Put(UINT format, HGLOBAL memory) {
  if (memory && !SetClipboardData(format, memory)) GlobalFree(memory);
}

// Whether |format| holds a DWORD set to 0. The clipboard must be open.
bool DwordIsZero(UINT format) {
  HANDLE data = GetClipboardData(format);
  if (!data) return false;
  void* value = GlobalLock(data);
  if (!value) return false;
  bool zero = GlobalSize(data) >= sizeof(DWORD) &&
              *static_cast<const DWORD*>(value) == 0;
  GlobalUnlock(data);
  return zero;
}

int64_t NowMillis() {
  using namespace std::chrono;
  return duration_cast<milliseconds>(system_clock::now().time_since_epoch())
      .count();
}

}  // namespace

ClipboardBridge::ClipboardBridge(flutter::BinaryMessenger* messenger,
                                 HWND window)
    : window_(window),
      own_format_(RegisterClipboardFormatW(L"Gotit.Own")),
      png_format_(RegisterClipboardFormatW(L"PNG")),
      exclude_format_(RegisterClipboardFormatW(
          L"ExcludeClipboardContentFromMonitorProcessing")),
      history_format_(RegisterClipboardFormatW(L"CanIncludeInClipboardHistory")),
      cloud_format_(RegisterClipboardFormatW(L"CanUploadToCloudClipboard")) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "app.gotit/clipboard",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "write") {
          result->NotImplemented();
          return;
        }
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        if (!args) {
          result->Error("args", "No arguments");
          return;
        }
        auto image = args->find(flutter::EncodableValue("image"));
        if (image != args->end()) {
          const auto* png = std::get_if<std::vector<uint8_t>>(&image->second);
          if (!png || png->empty()) {
            result->Error("args", "No image");
          } else if (WriteImage(*png)) {
            result->Success();
          } else {
            result->Error("busy", "The clipboard is in use");
          }
          return;
        }
        auto text = args->find(flutter::EncodableValue("text"));
        auto sensitive = args->find(flutter::EncodableValue("sensitive"));
        if (text == args->end() ||
            !std::holds_alternative<std::string>(text->second)) {
          result->Error("args", "No text");
          return;
        }
        bool is_sensitive = sensitive != args->end() &&
                            std::holds_alternative<bool>(sensitive->second) &&
                            std::get<bool>(sensitive->second);
        if (Write(std::get<std::string>(text->second), is_sensitive)) {
          result->Success();
        } else {
          result->Error("busy", "The clipboard is in use");
        }
      });
  AddClipboardFormatListener(window_);
}

ClipboardBridge::~ClipboardBridge() {
  RemoveClipboardFormatListener(window_);
  channel_->SetMethodCallHandler(nullptr);
}

bool ClipboardBridge::HandleMessage(UINT message) {
  if (message != WM_CLIPBOARDUPDATE) return false;
  OnClipboardChanged();
  return true;
}

void ClipboardBridge::OnClipboardChanged() {
  if (!OpenWithRetry(window_)) return;
  // Gotit's own write: the phone's copy arriving, not a new one.
  if (IsClipboardFormatAvailable(own_format_)) {
    CloseClipboard();
    return;
  }
  std::optional<std::string> text;
  if (IsClipboardFormatAvailable(CF_UNICODETEXT)) {
    HANDLE data = GetClipboardData(CF_UNICODETEXT);
    if (data) {
      const auto* chars = static_cast<const wchar_t*>(GlobalLock(data));
      if (chars) {
        size_t limit = GlobalSize(data) / sizeof(wchar_t);
        text = ToUtf8(chars, static_cast<int>(wcsnlen(chars, limit)));
        GlobalUnlock(data);
      }
    }
  }
  // No text: an image, as PNG. The clipboard's own PNG keeps transparency;
  // otherwise its bitmap (Windows makes one from any image format) is
  // encoded. Text comes first, so copying cells or a document sends text.
  std::optional<std::vector<uint8_t>> image;
  if (!text || text->empty()) {
    if (IsClipboardFormatAvailable(png_format_)) {
      HANDLE data = GetClipboardData(png_format_);
      const void* bytes = data ? GlobalLock(data) : nullptr;
      if (bytes) {
        const size_t size = GlobalSize(data);
        image = std::vector<uint8_t>(size);
        std::memcpy(image->data(), bytes, size);
        GlobalUnlock(data);
      }
    }
    if (!image && IsClipboardFormatAvailable(CF_BITMAP)) {
      auto* bitmap = static_cast<HBITMAP>(GetClipboardData(CF_BITMAP));
      if (bitmap) image = BitmapToPng(bitmap);
    }
  }
  // Password managers ask watchers to look away, or keep a copy out of
  // history. It still crosses, marked sensitive (Gotit's own decision).
  bool sensitive = IsClipboardFormatAvailable(exclude_format_) ||
                   (IsClipboardFormatAvailable(history_format_) &&
                    DwordIsZero(history_format_));
  CloseClipboard();
  flutter::EncodableMap args{
      {flutter::EncodableValue("sensitive"), flutter::EncodableValue(sensitive)},
      {flutter::EncodableValue("at"), flutter::EncodableValue(NowMillis())},
  };
  if (text && !text->empty()) {
    args[flutter::EncodableValue("text")] = flutter::EncodableValue(*text);
  } else if (image && !image->empty() && image->size() <= kMaxImageBytes) {
    args[flutter::EncodableValue("image")] =
        flutter::EncodableValue(std::move(*image));
  } else {
    return;
  }
  channel_->InvokeMethod("copied",
                         std::make_unique<flutter::EncodableValue>(args));
}

bool ClipboardBridge::WriteImage(const std::vector<uint8_t>& png) {
  // Converted before the clipboard opens, so it is held only briefly.
  std::optional<std::vector<uint8_t>> dib = PngToDib(png);
  if (!OpenWithRetry(window_)) return false;
  EmptyClipboard();
  Put(png_format_, CopyToGlobal(png.data(), png.size()));
  // A bitmap too, for apps that only paste bitmaps (Paint, older Office).
  if (dib) Put(CF_DIB, CopyToGlobal(dib->data(), dib->size()));
  const BYTE mark = 1;
  Put(own_format_, CopyToGlobal(&mark, sizeof(mark)));
  CloseClipboard();
  return true;
}

bool ClipboardBridge::Write(const std::string& utf8, bool sensitive) {
  std::wstring wide = ToUtf16(utf8);
  if (!OpenWithRetry(window_)) return false;
  EmptyClipboard();
  Put(CF_UNICODETEXT,
      CopyToGlobal(wide.c_str(), (wide.size() + 1) * sizeof(wchar_t)));
  const BYTE mark = 1;
  Put(own_format_, CopyToGlobal(&mark, sizeof(mark)));
  if (sensitive) {
    // Keep it out of clipboard history, off the cloud clipboard, and away
    // from other clipboard watchers.
    const DWORD zero = 0;
    Put(history_format_, CopyToGlobal(&zero, sizeof(zero)));
    Put(cloud_format_, CopyToGlobal(&zero, sizeof(zero)));
    Put(exclude_format_, CopyToGlobal(&zero, sizeof(zero)));
  }
  CloseClipboard();
  return true;
}
