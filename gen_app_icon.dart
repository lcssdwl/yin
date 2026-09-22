// 生成 App 图标(多彩元素头像:圆形紫粉橙渐变 + 白色音符)
//
// 运行:dart gen_app_icon.dart
// 用 Flutter 内置 dart-sdk:C:\flutter\bin\cache\dart-sdk\bin\dart.exe
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const String resRoot =
    r'c:\Users\Administrator\Desktop\yin\flutter_app\android\app\src\main\res';

// Android launcher icon 各密度尺寸
const Map<String, int> densities = {
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};

// ---- PNG 编码(与既有脚本一致) ----
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
  out.add((ByteData(4)
        ..setUint32(0, crc32((BytesBuilder()
              ..add(typeBytes)
              ..add(data))
            .takeBytes())))
      .buffer
      .asUint8List());
  return out.takeBytes();
}

Uint8List encodePng(int w, int h, Uint8List rgba) {
  final raw = Uint8List((w * 4 + 1) * h);
  for (var y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    raw.setRange(
        y * (w * 4 + 1) + 1, y * (w * 4 + 1) + 1 + w * 4, rgba, y * w * 4);
  }
  final ihdr = ByteData(13)
    ..setUint32(0, w)
    ..setUint32(4, h)
    ..setUint8(8, 8)
    ..setUint8(9, 6)
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  final png = BytesBuilder();
  png.add([137, 80, 78, 71, 13, 10, 26, 10]);
  png.add(chunk('IHDR', ihdr.buffer.asUint8List()));
  png.add(chunk('IDAT', Uint8List.fromList(ZLibCodec(level: 9).encode(raw))));
  png.add(chunk('IEND', Uint8List(0)));
  return png.takeBytes();
}

// ---- 颜色 ----
// 与 AppTheme 一致:紫 0xFF7C4DFF / 粉 0xFFFF6B9D / 橙 0xFFFFA94D
List<int> lerpColor(int c1, int c2, double t) {
  final r =
      ((c1 >> 16 & 0xFF) + ((c2 >> 16 & 0xFF) - (c1 >> 16 & 0xFF)) * t).round();
  final g =
      ((c1 >> 8 & 0xFF) + ((c2 >> 8 & 0xFF) - (c1 >> 8 & 0xFF)) * t).round();
  final b = ((c1 & 0xFF) + ((c2 & 0xFF) - (c1 & 0xFF)) * t).round();
  return [r, g, b];
}

/// t: 0(左上) → 1(右下),紫 → 粉 → 橙 三段插值
List<int> gradientColor(double t) {
  const c1 = 0xFF7C4DFF; // 紫
  const c2 = 0xFFFF6B9D; // 粉
  const c3 = 0xFFFFA94D; // 橙
  if (t < 0.5) return lerpColor(c1, c2, t * 2);
  return lerpColor(c2, c3, (t - 0.5) * 2);
}

/// 居中白色音符(x,y ∈ [0,1])
bool inNote(double x, double y) {
  // 符头(椭圆)
  final hx = (x - 0.42) / 0.10, hy = (y - 0.66) / 0.085;
  if (hx * hx + hy * hy <= 1) return true;
  // 符干
  if (x >= 0.49 && x <= 0.56 && y >= 0.26 && y <= 0.68) return true;
  // 旗(三角形)
  if (x >= 0.56 && x <= 0.76 && y >= 0.26) {
    final t = (x - 0.56) / 0.20;
    final bottom = 0.46 - 0.12 * t;
    if (y <= bottom) return true;
  }
  return false;
}

Uint8List render(int s) {
  final rgba = Uint8List(s * s * 4);
  for (var y = 0; y < s; y++) {
    for (var x = 0; x < s; x++) {
      double r = 0, g = 0, b = 0, a = 0;
      for (var sy = 0; sy < 3; sy++) {
        for (var sx = 0; sx < 3; sx++) {
          final ux = (x + (sx + 0.5) / 3) / s;
          final uy = (y + (sy + 0.5) / 3) / s;
          final dx = ux - 0.5, dy = uy - 0.5;
          // 圆形头像(半径 0.5,透明底)
          if (dx * dx + dy * dy <= 0.25) {
            if (inNote(ux, uy)) {
              r += 255;
              g += 255;
              b += 255;
            } else {
              final c = gradientColor((ux + uy) / 2);
              r += c[0];
              g += c[1];
              b += c[2];
            }
            a += 1;
          }
        }
      }
      final i = (y * s + x) * 4;
      rgba[i] = (r / 9).round();
      rgba[i + 1] = (g / 9).round();
      rgba[i + 2] = (b / 9).round();
      rgba[i + 3] = (a / 9 * 255).round();
    }
  }
  return rgba;
}

void main() {
  final sep = Platform.pathSeparator;
  for (final e in densities.entries) {
    final dir = Directory('$resRoot${sep}mipmap-${e.key}');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final f = File('${dir.path}${sep}ic_launcher.png')
      ..writeAsBytesSync(encodePng(e.value, e.value, render(e.value)));
    print('${f.path} (${f.lengthSync()}B)');
  }
  print('done');
}
