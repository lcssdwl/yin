// 生成通知小图标(白色剪影 PNG)
//
// 关键点:通知的 small icon 必须是**真正的位图 PNG**。
// Flutter 默认的 ic_launcher 在 Android 8+ 是自适应图标(XML),
// 拿它当通知小图标会抛 "Invalid notification (no valid small icon)"。
//
// 运行:dart gen_smallicon.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const String resRoot =
    r'c:\Users\Administrator\Desktop\yin\flutter_app\android\app\src\main\res';

const Map<String, int> densities = {
  'mdpi': 24,
  'hdpi': 36,
  'xhdpi': 48,
  'xxhdpi': 72,
  'xxxhdpi': 96,
};

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

/// 白色音符剪影(系统会给它着色,所以只画纯白形状 + 透明底)
bool inNote(double x, double y) {
  // 符头(椭圆)
  final hx = (x - 0.40) / 0.17, hy = (y - 0.68) / 0.14;
  if (hx * hx + hy * hy <= 1) return true;
  // 符干
  if (x >= 0.52 && x <= 0.60 && y >= 0.18 && y <= 0.70) return true;
  // 旗(三角形)
  if (x >= 0.60 && x <= 0.86 && y >= 0.18) {
    final t = (x - 0.60) / 0.26;
    final bottom = 0.50 - 0.10 * t;
    if (y <= bottom) return true;
  }
  return false;
}

Uint8List render(int s) {
  final rgba = Uint8List(s * s * 4);
  for (var y = 0; y < s; y++) {
    for (var x = 0; x < s; x++) {
      var cov = 0;
      for (var sy = 0; sy < 3; sy++) {
        for (var sx = 0; sx < 3; sx++) {
          final ux = (x + (sx + 0.5) / 3) / s;
          final uy = (y + (sy + 0.5) / 3) / s;
          if (inNote(ux, uy)) cov++;
        }
      }
      final i = (y * s + x) * 4;
      final a = cov / 9.0;
      rgba[i] = 255;
      rgba[i + 1] = 255;
      rgba[i + 2] = 255;
      rgba[i + 3] = (a * 255).round();
    }
  }
  return rgba;
}

void main() {
  final sep = Platform.pathSeparator;
  for (final e in densities.entries) {
    final dir = Directory('$resRoot${sep}drawable-${e.key}');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final f = File('${dir.path}${sep}ic_stat_music.png')
      ..writeAsBytesSync(encodePng(e.value, e.value, render(e.value)));
    print('${f.path} (${f.lengthSync()}B)');
  }
  print('done');
}
