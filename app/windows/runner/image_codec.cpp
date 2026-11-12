#include "image_codec.h"

#include <wincodec.h>
#include <wrl/client.h>

#include <cstring>

using Microsoft::WRL::ComPtr;

namespace {

ComPtr<IWICImagingFactory> Factory() {
  static ComPtr<IWICImagingFactory> factory;
  if (!factory) {
    CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                     IID_PPV_ARGS(&factory));
  }
  return factory;
}

// |source| in |format|, converting when it isn't already.
ComPtr<IWICBitmapSource> InFormat(IWICImagingFactory* factory,
                                  IWICBitmapSource* source,
                                  const WICPixelFormatGUID& format) {
  WICPixelFormatGUID current;
  if (SUCCEEDED(source->GetPixelFormat(&current)) &&
      IsEqualGUID(current, format)) {
    return source;
  }
  ComPtr<IWICFormatConverter> converter;
  if (FAILED(factory->CreateFormatConverter(&converter)) ||
      FAILED(converter->Initialize(source, format, WICBitmapDitherTypeNone,
                                   nullptr, 0.0,
                                   WICBitmapPaletteTypeCustom))) {
    return nullptr;
  }
  return converter;
}

}  // namespace

std::optional<std::vector<uint8_t>> BitmapToPng(HBITMAP bitmap) {
  ComPtr<IWICImagingFactory> factory = Factory();
  if (!factory) return std::nullopt;
  ComPtr<IWICBitmap> source;
  if (FAILED(factory->CreateBitmapFromHBITMAP(bitmap, nullptr,
                                              WICBitmapIgnoreAlpha,
                                              &source))) {
    return std::nullopt;
  }
  UINT width = 0;
  UINT height = 0;
  if (FAILED(source->GetSize(&width, &height)) || width == 0 || height == 0) {
    return std::nullopt;
  }

  ComPtr<IStream> stream;
  ComPtr<IWICBitmapEncoder> encoder;
  ComPtr<IWICBitmapFrameEncode> frame;
  if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream)) ||
      FAILED(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr,
                                    &encoder)) ||
      FAILED(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache)) ||
      FAILED(encoder->CreateNewFrame(&frame, nullptr)) ||
      FAILED(frame->Initialize(nullptr)) ||
      FAILED(frame->SetSize(width, height))) {
    return std::nullopt;
  }
  // The encoder may pick a different format; give it exactly that.
  WICPixelFormatGUID format = GUID_WICPixelFormat24bppBGR;
  if (FAILED(frame->SetPixelFormat(&format))) return std::nullopt;
  ComPtr<IWICBitmapSource> pixels = InFormat(factory.Get(), source.Get(), format);
  if (!pixels || FAILED(frame->WriteSource(pixels.Get(), nullptr)) ||
      FAILED(frame->Commit()) || FAILED(encoder->Commit())) {
    return std::nullopt;
  }

  STATSTG stat{};
  HGLOBAL memory = nullptr;
  if (FAILED(stream->Stat(&stat, STATFLAG_NONAME)) ||
      FAILED(GetHGlobalFromStream(stream.Get(), &memory))) {
    return std::nullopt;
  }
  const auto size = static_cast<size_t>(stat.cbSize.QuadPart);
  const void* bytes = GlobalLock(memory);
  if (!bytes) return std::nullopt;
  std::vector<uint8_t> png(size);
  std::memcpy(png.data(), bytes, size);
  GlobalUnlock(memory);
  return png;
}

std::optional<std::vector<uint8_t>> PngToDib(const std::vector<uint8_t>& png) {
  ComPtr<IWICImagingFactory> factory = Factory();
  if (!factory || png.empty()) return std::nullopt;
  ComPtr<IWICStream> stream;
  ComPtr<IWICBitmapDecoder> decoder;
  ComPtr<IWICBitmapFrameDecode> frame;
  if (FAILED(factory->CreateStream(&stream)) ||
      FAILED(stream->InitializeFromMemory(const_cast<BYTE*>(png.data()),
                                          static_cast<DWORD>(png.size()))) ||
      FAILED(factory->CreateDecoderFromStream(
          stream.Get(), nullptr, WICDecodeMetadataCacheOnDemand, &decoder)) ||
      FAILED(decoder->GetFrame(0, &frame))) {
    return std::nullopt;
  }
  ComPtr<IWICBitmapSource> pixels =
      InFormat(factory.Get(), frame.Get(), GUID_WICPixelFormat32bppBGRA);
  UINT width = 0;
  UINT height = 0;
  if (!pixels || FAILED(pixels->GetSize(&width, &height)) || width == 0 ||
      height == 0) {
    return std::nullopt;
  }

  const UINT stride = width * 4;
  const size_t image_size = static_cast<size_t>(stride) * height;
  std::vector<uint8_t> rows(image_size);
  if (FAILED(pixels->CopyPixels(nullptr, stride,
                                static_cast<UINT>(image_size), rows.data()))) {
    return std::nullopt;
  }

  BITMAPINFOHEADER header{};
  header.biSize = sizeof(header);
  header.biWidth = static_cast<LONG>(width);
  // Positive: bottom-up, the layout every app reads.
  header.biHeight = static_cast<LONG>(height);
  header.biPlanes = 1;
  header.biBitCount = 32;
  header.biCompression = BI_RGB;
  header.biSizeImage = static_cast<DWORD>(image_size);

  std::vector<uint8_t> dib(sizeof(header) + image_size);
  std::memcpy(dib.data(), &header, sizeof(header));
  uint8_t* out = dib.data() + sizeof(header);
  for (UINT y = 0; y < height; ++y) {
    std::memcpy(out + static_cast<size_t>(height - 1 - y) * stride,
                rows.data() + static_cast<size_t>(y) * stride, stride);
  }
  return dib;
}
