import 'dart:typed_data';
import 'dart:ui' as ui;

/// RGB565 big-endian pixels. Native round photos fill 466x466 with a smooth
/// centre crop; the original rectangular display keeps its 320x240 format.
class ImageConverter {
  static const int kDisplayWidth = 320,
      kDisplayHeight = 240,
      kTotalBytes = 320 * 240 * 2;
  static Future<Uint8List> convertToRgb565(Uint8List bytes,
      {int width = kDisplayWidth,
      int height = kDisplayHeight,
      bool cover = false}) async {
    final image = await buildPreviewImage(bytes,
        width: width, height: height, cover: cover);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError('Cannot read image pixels');
      final rgba = data.buffer.asUint8List();
      final result = Uint8List(width * height * 2);
      for (int i = 0; i < width * height; i++) {
        final pixel = ((rgba[i * 4] & 0xf8) << 8) |
            ((rgba[i * 4 + 1] & 0xfc) << 3) |
            (rgba[i * 4 + 2] >> 3);
        result[i * 2] = pixel >> 8;
        result[i * 2 + 1] = pixel & 255;
      }
      return result;
    } finally {
      image.dispose();
    }
  }

  static Future<ui.Image> buildPreviewImage(Uint8List bytes,
      {int width = kDisplayWidth,
      int height = kDisplayHeight,
      bool cover = false}) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final source = frame.image;
    try {
      final sx = width / source.width, sy = height / source.height;
      final scale = cover ? (sx > sy ? sx : sy) : (sx < sy ? sx : sy);
      final w = source.width * scale, h = source.height * scale;
      final recorder = ui.PictureRecorder();
      final output = ui.Canvas(recorder);
      output.drawRect(
          ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          ui.Paint()..color = const ui.Color(0xff000000));
      output.drawImageRect(
          source,
          ui.Rect.fromLTWH(
              0, 0, source.width.toDouble(), source.height.toDouble()),
          ui.Rect.fromLTWH((width - w) / 2, (height - h) / 2, w, h),
          ui.Paint()
            ..filterQuality =
                cover ? ui.FilterQuality.high : ui.FilterQuality.none);
      final picture = recorder.endRecording();
      try {
        return await picture.toImage(width, height);
      } finally {
        picture.dispose();
      }
    } finally {
      source.dispose();
      codec.dispose();
    }
  }
}
