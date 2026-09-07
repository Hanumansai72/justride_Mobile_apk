// lib/core/utils/image_converter.dart
//
// Converts any picked image into a 320x240 big-endian RGB565 byte buffer
// ready for direct streaming to the JustRide ESP32 TFT display via BLE.
//
// Key decisions:
//  * FilterQuality.none  -> nearest-neighbour scaling -> QR codes stay crisp,
//    no blurring artefacts that would break scanner modules.
//  * Letterbox with black fill -> correct aspect ratio without stretching.
//  * Big-endian output  -> ILI9341 SPI controller expects high-byte first;
//    tft_draw_raw_pixels() sends bytes as-is without swapping.

import 'dart:typed_data';
import 'dart:ui' as ui;

class ImageConverter {
  static const int kDisplayWidth  = 320;
  static const int kDisplayHeight = 240;
  static const int kTotalBytes    = kDisplayWidth * kDisplayHeight * 2; // 153 600

  /// Convert raw image bytes (JPEG / PNG / BMP / WebP) to a 320x240
  /// big-endian RGB565 Uint8List of exactly kTotalBytes bytes.
  ///
  /// Scaling strategy:
  ///   * Compute uniform scale so the image fits inside 320x240 without
  ///     exceeding either dimension.
  ///   * Centre the scaled image on a black canvas.
  ///   * FilterQuality.none -> nearest-neighbour -> sharp QR codes.
  static Future<Uint8List> convertToRgb565(Uint8List imageBytes) async {
    // 1. Decode source image
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final srcImage = frame.image;

    final srcW = srcImage.width.toDouble();
    final srcH = srcImage.height.toDouble();

    // 2. Compute letterbox geometry
    final scaleX = kDisplayWidth  / srcW;
    final scaleY = kDisplayHeight / srcH;
    final scale  = scaleX < scaleY ? scaleX : scaleY; // fit-inside

    final fitW = (srcW * scale).roundToDouble();
    final fitH = (srcH * scale).roundToDouble();
    final offX = ((kDisplayWidth  - fitW) / 2.0);
    final offY = ((kDisplayHeight - fitH) / 2.0);

    // 3. Draw onto a 320x240 canvas with black background
    final recorder = ui.PictureRecorder();
    final canvas   = ui.Canvas(recorder);

    // Black fill (0x0000 in RGB565 = black)
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, kDisplayWidth.toDouble(), kDisplayHeight.toDouble()),
      ui.Paint()..color = const ui.Color(0xFF000000),
    );

    // Nearest-neighbour blit -- CRITICAL for QR code sharpness
    canvas.drawImageRect(
      srcImage,
      ui.Rect.fromLTWH(0, 0, srcW, srcH),
      ui.Rect.fromLTWH(offX, offY, fitW, fitH),
      ui.Paint()..filterQuality = ui.FilterQuality.none,
    );

    final picture     = recorder.endRecording();
    final outputImage = await picture.toImage(kDisplayWidth, kDisplayHeight);

    // 4. Extract raw RGBA bytes
    final byteData = await outputImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null) {
      throw Exception('[ImageConverter] toByteData() returned null');
    }
    final rgba = byteData.buffer.asUint8List();

    // 5. RGBA8888 -> big-endian RGB565
    //   RGB565 bit layout: RRRRR GGGGGG BBBBB  (MSB->LSB)
    //   Stored big-endian: high byte first (as ILI9341 expects on SPI).
    //
    //   pixel16 = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)
    //   byte[2i+0] = pixel16 >> 8     (high byte)
    //   byte[2i+1] = pixel16 & 0xFF   (low  byte)
    final rgb565 = Uint8List(kTotalBytes);
    const pixels = kDisplayWidth * kDisplayHeight;

    for (int i = 0; i < pixels; i++) {
      final r = rgba[i * 4 + 0];
      final g = rgba[i * 4 + 1];
      final b = rgba[i * 4 + 2];

      final int pixel16 = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
      rgb565[i * 2 + 0] = (pixel16 >> 8) & 0xFF; // high byte first (big-endian)
      rgb565[i * 2 + 1] =  pixel16       & 0xFF; // low byte
    }

    return rgb565;
  }

  /// Convenience: returns a preview ui.Image at 320x240 for the app UI.
  /// Uses the same letterbox + nearest-neighbour logic as convertToRgb565.
  static Future<ui.Image> buildPreviewImage(Uint8List imageBytes) async {
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final src   = frame.image;

    final srcW = src.width.toDouble();
    final srcH = src.height.toDouble();
    final scale = (kDisplayWidth / srcW) < (kDisplayHeight / srcH)
        ? (kDisplayWidth / srcW)
        : (kDisplayHeight / srcH);

    final fitW = srcW * scale;
    final fitH = srcH * scale;

    final rec    = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);

    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, kDisplayWidth.toDouble(), kDisplayHeight.toDouble()),
      ui.Paint()..color = const ui.Color(0xFF000000),
    );
    canvas.drawImageRect(
      src,
      ui.Rect.fromLTWH(0, 0, srcW, srcH),
      ui.Rect.fromLTWH(
        (kDisplayWidth  - fitW) / 2,
        (kDisplayHeight - fitH) / 2,
        fitW, fitH,
      ),
      ui.Paint()..filterQuality = ui.FilterQuality.none,
    );

    return rec.endRecording().toImage(kDisplayWidth, kDisplayHeight);
  }
}
