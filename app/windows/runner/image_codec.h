#ifndef RUNNER_IMAGE_CODEC_H_
#define RUNNER_IMAGE_CODEC_H_

#include <windows.h>

#include <cstdint>
#include <optional>
#include <vector>

// Images between the clipboard's formats and PNG, with Windows Imaging
// Component (WIC). COM must be initialised on the calling thread.

// A clipboard bitmap (CF_BITMAP) as PNG. Its alpha is ignored: bitmaps from
// snips and most apps carry none that means anything.
std::optional<std::vector<uint8_t>> BitmapToPng(HBITMAP bitmap);

// PNG as a 32-bit bottom-up device-independent bitmap (CF_DIB: a
// BITMAPINFOHEADER followed by the pixels), for apps that paste bitmaps.
std::optional<std::vector<uint8_t>> PngToDib(const std::vector<uint8_t>& png);

#endif  // RUNNER_IMAGE_CODEC_H_
