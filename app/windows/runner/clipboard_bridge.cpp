#include "clipboard_bridge.h"

#include <flutter/standard_method_codec.h>
#include <shlobj.h>

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

// The clipboard's sequence number, which changes with every write to it.
flutter::EncodableValue SequenceNumber() {
  return flutter::EncodableValue(
      static_cast<int64_t>(GetClipboardSequenceNumber()));
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
      drop_effect_format_(RegisterClipboardFormatW(CFSTR_PREFERREDDROPEFFECT)),
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
        if (call.method_name() == "wipe") {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          auto sequence =
              args ? args->find(flutter::EncodableValue("sequence"))
                   : flutter::EncodableMap::const_iterator();
          if (!args || sequence == args->end() ||
              !(std::holds_alternative<int32_t>(sequence->second) ||
                std::holds_alternative<int64_t>(sequence->second))) {
            result->Error("args", "No sequence");
            return;
          }
          result->Success(flutter::EncodableValue(
              Wipe(static_cast<DWORD>(sequence->second.LongValue()))));
          return;
        }
        const bool files = call.method_name() == "writeFiles";
        if (!files && call.method_name() != "write") {
          result->NotImplemented();
          return;
        }
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        if (!args) {
          result->Error("args", "No arguments");
          return;
        }
        if (files) {
          // Files that arrived: ready to paste, and an image also as itself.
          std::vector<std::wstring> paths;
          auto list = args->find(flutter::EncodableValue("paths"));
          if (list != args->end()) {
            if (const auto* items = std::get_if<flutter::EncodableList>(&list->second)) {
              for (const auto& item : *items) {
                if (const auto* path = std::get_if<std::string>(&item)) {
                  paths.push_back(ToUtf16(*path));
                }
              }
            }
          }
          std::wstring picture;
          auto image = args->find(flutter::EncodableValue("picture"));
          if (image != args->end()) {
            if (const auto* path = std::get_if<std::string>(&image->second)) {
              picture = ToUtf16(*path);
            }
          }
          if (paths.empty()) {
            result->Error("args", "No paths");
          } else if (WriteFiles(paths, picture)) {
            result->Success();
          } else {
            result->Error("busy", "The clipboard is in use");
          }
          return;
        }
        auto image = args->find(flutter::EncodableValue("image"));
        if (image != args->end()) {
          const auto* png = std::get_if<std::vector<uint8_t>>(&image->second);
          if (!png || png->empty()) {
            result->Error("args", "No image");
          } else if (WriteImage(*png)) {
            result->Success(SequenceNumber());
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
          result->Success(SequenceNumber());
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

bool ClipboardBridge::WriteFiles(const std::vector<std::wstring>& paths,
                                 const std::wstring& picture) {
  // CF_HDROP: a DROPFILES header, then the paths, each ending in a null, and
  // one more null at the end.
  size_t chars = 1;
  for (const auto& path : paths) chars += path.size() + 1;
  std::vector<uint8_t> drop(sizeof(DROPFILES) + chars * sizeof(wchar_t), 0);
  auto* header = reinterpret_cast<DROPFILES*>(drop.data());
  header->pFiles = sizeof(DROPFILES);
  header->fWide = TRUE;
  auto* out = reinterpret_cast<wchar_t*>(drop.data() + sizeof(DROPFILES));
  for (const auto& path : paths) {
    std::memcpy(out, path.c_str(), (path.size() + 1) * sizeof(wchar_t));
    out += path.size() + 1;
  }
  // Decoded before the clipboard opens, so it is held only briefly.
  std::optional<Picture> image;
  if (!picture.empty()) image = PictureFromFile(picture);

  if (!OpenWithRetry(window_)) return false;
  EmptyClipboard();
  Put(CF_HDROP, CopyToGlobal(drop.data(), drop.size()));
  const DWORD copy = DROPEFFECT_COPY;
  Put(drop_effect_format_, CopyToGlobal(&copy, sizeof(copy)));
  if (image) {
    Put(png_format_, CopyToGlobal(image->png.data(), image->png.size()));
    Put(CF_DIB, CopyToGlobal(image->dib.data(), image->dib.size()));
  }
  const BYTE mark = 1;
  Put(own_format_, CopyToGlobal(&mark, sizeof(mark)));
  CloseClipboard();
  return true;
}

bool ClipboardBridge::Wipe(DWORD sequence) {
  // Something copied since changed the number: it stays.
  if (GetClipboardSequenceNumber() != sequence) return false;
  if (!OpenWithRetry(window_)) return false;
  // Checked again while open, so nothing can slip in between.
  const bool ours = GetClipboardSequenceNumber() == sequence &&
                    IsClipboardFormatAvailable(own_format_);
  if (ours) EmptyClipboard();
  CloseClipboard();
  return ours;
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
