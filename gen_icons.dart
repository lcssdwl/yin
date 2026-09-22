// 生成通知栏媒体按钮图标(PNG,非矢量 —— 矢量图在通知 RemoteViews 里会失效)
// 每个图标画两遍:先白色放大版当描边,再深色正常版当实心 ——
// 不管 SystemUI 给不给图标着色、通知底是浅是深都能看清。
//
// 运行:dart gen_icons.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const String resRoot =
    r'c:\Users\Administrator\Desktop\yin\flutter_app\android\app\src\main\res';

const List<String> kinds = ['play', 'pause', 'skip_previous', 'skip_next'];
const Map<String, int> densities = {
  'mdpi': 24,
  'hdpi': 36,
  'xhdpi': 48,
  'xxhdpi': 72,
  'xxxhdpi': 96,
};

// 归一化坐标(0~1)的多边形
List<List<List<double>>> shapesFor(String kind) {
  List<List<double>> rect(double x0, double y0, double x1, double y1) =>
      [
        [x0, y0],
        [x1, y0],
        [x1, y1],
        [x0, y1],
      ];

  switch (kind) {
    case 'play':
      return [
        [
          [0.30, 0.20],
          [0.30, 0.80],
          [0.78, 0.50],
        ],
      ];
    case 'pause':
      return [rect(0.30, 0.20, 0.44, 0.80), rect(0.56, 0.20, 0.70, 0.80)];
    case 'skip_previous':
      return [
        rect(0.16, 0.20, 0.24, 0.80),
        [
          [0.28, 0.50],
          [0.80, 0.20],
          [0.80, 0.80],
        ],
      ];
    case 'skip_next':
      return [
        rect(0.76, 0.20, 0.84, 0.80),
        [
          [0.72, 0.50],
          [0.20, 0.20],
          [0.20, 0.80],
        ],
      ];
    default:
      return [];
  }
}

bool inPoly(double x, double y, List<List<double>> poly) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final xi = poly[i][0], yi = poly[i][1];
    final xj = poly[j][0], yj = poly[j][1];
    if (((yi > y) != (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi)) {
      inside = !inside;
    }
  }
  return inside;
}

bool inAny(List<List<List<double>>> shapes, double x, double y) {
  for (final p in shapes) {
    if (inPoly(x, y, p)) return true;
  }
  return false;
}

Uint8List render(String kind, int s) {
  final shapes = shapesFor(kind);
  final rgba = Uint8List(s * s * 4);
  const ink = 24; // 深色芯 #181818

  for (var y = 0; y < s; y++) {
    for (var x = 0; x < s; x++) {
      var covOutline = 0, covSolid = 0;
      for (var sy = 0; sy < 3; sy++) {
        for (var sx = 0; sx < 3; sx++) {
          final ux = (x + (sx + 0.5) / 3) / s;
          final uy = (y + (sy + 0.5) / 3) / s;
          // 白色描边:以中心为原点放大 1.35 倍
          final ox = 0.5 + (ux - 0.5) * 1.35;
          final oy = 0.5 + (uy - 0.5) * 1.35;
          if (inAny(shapes, ox, oy)) covOutline++;
          if (inAny(shapes, ux, uy)) covSolid++;
        }
      }

      final aO = covOutline / 9.0;
      final aS = covSolid / 9.0;
      if (aO <= 0 && aS <= 0) continue;

      // 先铺白描边,再用深色芯 src-over 叠上去
      final aOut = aS + aO * (1 - aS);
      final c = (ink * aS + 255 * aO * (1 - aS)) / aOut;

      final i = (y * s + x) * 4;
      rgba[i] = c.round();
      rgba[i + 1] = c.round();
      rgba[i + 2] = c.round();
      rgba[i + 3] = (aOut * 255).round();
    }
  }
  return rgba;
}

// ==================== PNG 编码(仅 dart:io,无第三方依赖) ====================

final List<int> crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) == 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
  }
  return c;
});

int crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = crcTable[(c ^ b) & 0xFF] ^ (c >>> 8);
  }
  return c ^ 0xFFFFFFFF;
}

Uint8List chunk(String type, Uint8List data) {
  final typeBytes = ascii.encode(type);
  final out = BytesBuilder();
  out.add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List());
  out.add(typeBytes);
  out.add(data);
  final crcInput = BytesBuilder()
    ..add(typeBytes)
    ..add(data);
  out.add((ByteData(4)..setUint32(0, crc32(crcInput.takeBytes())))
      .buffer
      .asUint8List());
  return out.takeBytes();
}

Uint8List encodePng(int w, int h, Uint8List rgba) {
  final raw = Uint8List((w * 4 + 1) * h);
  for (var y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0; // filter: none
    raw.setRange(y * (w * 4 + 1) + 1, y * (w * 4 + 1) + 1 + w * 4, rgba, y * w * 4);
  }

  final ihdr = ByteData(13)
    ..setUint32(0, w)
    ..setUint32(4, h)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 6) // color type RGBA
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);

  final png = BytesBuilder();
  png.add([137, 80, 78, 71, 13, 10, 26, 10]);
  png.add(chunk('IHDR', ihdr.buffer.asUint8List()));
  png.add(chunk(
      'IDAT', Uint8List.fromList(ZLibCodec(level: 9).encode(raw))));
  png.add(chunk('IEND', Uint8List(0)));
  return png.takeBytes();
}

void main() {
  final sep = Platform.pathSeparator;
  for (final kind in kinds) {
    for (final entry in densities.entries) {
      final s = entry.value;
      final dir = Directory('$resRoot${sep}drawable-${entry.key}');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File('${dir.path}${sep}audio_service_$kind.png');
      file.writeAsBytesSync(encodePng(s, s, render(kind, s)));
      print('${file.path} (${file.lengthSync()}B)');
    }
  }
  print('done');
}
