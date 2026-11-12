#include "files_bridge.h"

#include <flutter/standard_method_codec.h>
#include <ole2.h>
#include <shellapi.h>

#include "utils.h"

namespace {

// Ctrl+F2. The ID is Gotit's own, for WM_HOTKEY.
constexpr int kHotkeyId = 0x6701;

// The paths in a CF_HDROP block.
std::vector<std::wstring> PathsIn(HDROP drop) {
  std::vector<std::wstring> paths;
  const UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
  for (UINT i = 0; i < count; ++i) {
    const UINT length = DragQueryFileW(drop, i, nullptr, 0);
    if (length == 0) continue;
    std::wstring path(length + 1, L'\0');
    DragQueryFileW(drop, i, path.data(), length + 1);
    path.resize(length);
    paths.push_back(std::move(path));
  }
  return paths;
}

FORMATETC FilesFormat() {
  return FORMATETC{CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
}

// The files copied in Explorer (Ctrl+C), if the clipboard holds any.
std::vector<std::wstring> CopiedFiles(HWND window) {
  std::vector<std::wstring> paths;
  if (!IsClipboardFormatAvailable(CF_HDROP)) return paths;
  for (int attempt = 0; attempt < 10; ++attempt) {
    if (OpenClipboard(window)) {
      if (HANDLE data = GetClipboardData(CF_HDROP)) {
        paths = PathsIn(static_cast<HDROP>(data));
      }
      CloseClipboard();
      return paths;
    }
    // Another program may hold the clipboard for a moment.
    Sleep(15);
  }
  return paths;
}

}  // namespace

// Takes files dropped on the window. Anything that isn't files (text, a
// link) is turned away with the "no" cursor.
class FileDropTarget : public IDropTarget {
 public:
  explicit FileDropTarget(FilesBridge* bridge) : bridge_(bridge) {}

  // The bridge is going: drops that are still under way go nowhere.
  void Detach() { bridge_ = nullptr; }

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid,
                                           void** object) override {
    if (iid == IID_IUnknown || iid == IID_IDropTarget) {
      *object = static_cast<IDropTarget*>(this);
      AddRef();
      return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
  }

  ULONG STDMETHODCALLTYPE AddRef() override {
    return static_cast<ULONG>(InterlockedIncrement(&references_));
  }

  ULONG STDMETHODCALLTYPE Release() override {
    const LONG left = InterlockedDecrement(&references_);
    if (left == 0) delete this;
    return static_cast<ULONG>(left);
  }

  HRESULT STDMETHODCALLTYPE DragEnter(IDataObject* data, DWORD /*keys*/,
                                      POINTL /*point*/,
                                      DWORD* effect) override {
    FORMATETC format = FilesFormat();
    files_ = data && data->QueryGetData(&format) == S_OK;
    *effect = files_ ? DROPEFFECT_COPY : DROPEFFECT_NONE;
    if (files_ && bridge_) bridge_->Dragging(true);
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE DragOver(DWORD /*keys*/, POINTL /*point*/,
                                     DWORD* effect) override {
    *effect = files_ ? DROPEFFECT_COPY : DROPEFFECT_NONE;
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE DragLeave() override {
    if (files_ && bridge_) bridge_->Dragging(false);
    files_ = false;
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE Drop(IDataObject* data, DWORD /*keys*/,
                                 POINTL /*point*/, DWORD* effect) override {
    std::vector<std::wstring> paths;
    FORMATETC format = FilesFormat();
    STGMEDIUM medium{};
    if (files_ && data && data->GetData(&format, &medium) == S_OK) {
      paths = PathsIn(static_cast<HDROP>(medium.hGlobal));
      ReleaseStgMedium(&medium);
    }
    *effect = paths.empty() ? DROPEFFECT_NONE : DROPEFFECT_COPY;
    const bool were_files = files_;
    files_ = false;
    if (bridge_) {
      if (!paths.empty()) {
        bridge_->Dropped(paths);
      } else if (were_files) {
        bridge_->Dragging(false);
      }
    }
    return S_OK;
  }

 private:
  ~FileDropTarget() = default;

  LONG references_ = 1;
  bool files_ = false;
  FilesBridge* bridge_;
};

FilesBridge::FilesBridge(flutter::BinaryMessenger* messenger, HWND window,
                         HWND view)
    : window_(window), view_(view) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "app.gotit/files",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "hotkey") {
          result->Success(flutter::EncodableValue(hotkey_));
        } else {
          result->NotImplemented();
        }
      });
  // MOD_NOREPEAT: holding the keys down sends once.
  hotkey_ = RegisterHotKey(window_, kHotkeyId, MOD_CONTROL | MOD_NOREPEAT,
                           VK_F2) != 0;
  drop_target_ = new FileDropTarget(this);
  if (RegisterDragDrop(view_, drop_target_) != S_OK) {
    drop_target_->Detach();
    drop_target_->Release();
    drop_target_ = nullptr;
  }
}

FilesBridge::~FilesBridge() {
  if (hotkey_) UnregisterHotKey(window_, kHotkeyId);
  if (drop_target_) {
    drop_target_->Detach();
    RevokeDragDrop(view_);
    drop_target_->Release();
  }
  channel_->SetMethodCallHandler(nullptr);
}

bool FilesBridge::HandleMessage(UINT message, WPARAM wparam) {
  if (message != WM_HOTKEY || wparam != static_cast<WPARAM>(kHotkeyId)) {
    return false;
  }
  Send("hotkey", CopiedFiles(window_));
  return true;
}

void FilesBridge::Dragging(bool hovering) {
  channel_->InvokeMethod(
      "dragging", std::make_unique<flutter::EncodableValue>(hovering));
}

void FilesBridge::Dropped(const std::vector<std::wstring>& paths) {
  Send("dropped", paths);
}

void FilesBridge::Send(const std::string& method,
                       const std::vector<std::wstring>& paths) {
  flutter::EncodableList list;
  for (const auto& path : paths) {
    list.push_back(flutter::EncodableValue(Utf8FromUtf16(path.c_str())));
  }
  channel_->InvokeMethod(method,
                         std::make_unique<flutter::EncodableValue>(list));
}
