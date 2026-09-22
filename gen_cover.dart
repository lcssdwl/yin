// 生成默认封面占位图(本地 asset,供 App 内兜底 + 系统通知封面使用)
// 运行:dart gen_cover.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const int S = 512;
const String outPath = r'c:\Users\Administrator\Desktop\yin\flutter_app\assets\images\default_cover.png';

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

// 深色底 + 白色圆环 + 音符
Uint8List render() {
  final rgba = Uint8List(S * S * 4);
  const bg = 43;

  for (var y = 0; y < S; y++) {
    for (var x = 0; x < S; x++) {
      var cov = 0;
      for (var sy = 0; sy < 3; sy++) {
        for (var sx = 0; sx < 3; sx++) {
          final ux = (x + (sx + 0.5) / 3) / S;
          final uy = (y + (sy + 0.5) / 3) / S;
          if (inNote(ux, uy)) cov++;
        }
      }
      final i = (y * S + x) * 4;
      final a = cov / 9.0;
      rgba[i] = (bg + (255 - bg) * a).round();
      rgba[i + 1] = (bg + (255 - bg) * a).round();
      rgba[i + 2] = (bg + (255 - bg) * a).round();
      rgba[i + 3] = 255;
    }
  }
  return rgba;
}

bool inNote(double x, double y) {
  final dx = x - 0.5, dy = y - 0.5;
  final r = (dx * dx + dy * dy);
  // 圆环
  if (r <= 0.34 * 0.34 && r >= 0.30 * 0.30) return true;
  // 符头(椭圆)
  final hx = (x - 0.435) / 0.085, hy = (y - 0.60) / 0.068;
  if (hx * hx + hy * hy <= 1) return true;
  // 符干
  if (x >= 0.500 && x <= 0.525 && y >= 0.30 && y <= 0.60) return true;
  // 旗(三角形)
  if (x >= 0.525 && x <= 0.62) {
    final t = (x - 0.525) / (0.62 - 0.525);
    final top = 0.30 + 0.02 * t;
    final bottom = 0.455 - 0.075 * t;
    if (y >= top && y <= bottom) return true;
  }
  return false;
}

void main() {
  final dir = Directory(outPath.substring(0, outPath.lastIndexOf(r'\')));
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final f = File(outPath)
    ..writeAsBytesSync(encodePng(S, S, render()));
  print('${f.path} (${f.lengthSync()}B)');
}
