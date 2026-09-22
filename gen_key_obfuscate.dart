import 'dart:math';
import 'dart:typed_data';

// 7 个锚点位置(1-based) → 每组 7 轮
const anchors = [5, 9, 7, 10, 18, 19, 1];

Uint8List hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String bytesToHex(Uint8List b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

Uint8List randomBytes(Random r, int n) =>
    Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));

Uint8List xorBytes(Uint8List a, Uint8List b) {
  final out = Uint8List(a.length);
  for (var i = 0; i < a.length; i++) {
    out[i] = (a[i] ^ b[i]) & 0xff;
  }
  return out;
}

void rotLeft(Uint8List a, int steps) {
  final n = a.length;
  steps %= n;
  if (steps == 0) return;
  final tmp = Uint8List.fromList(a.sublist(0, steps));
  for (var i = 0; i < n - steps; i++) {
    a[i] = a[i + steps];
  }
  for (var i = 0; i < steps; i++) {
    a[n - steps + i] = tmp[i];
  }
}

void rotRight(Uint8List a, int steps) =>
    rotLeft(a, a.length - (steps % a.length));

Uint8List scramble(
  Uint8List k,
  Uint8List m1,
  Uint8List m2,
  Uint8List m3,
) {
  final n = k.length;
  var c = Uint8List.fromList(k);

  c = xorBytes(c, m1); // 层1

  for (var r = 0; r < 7; r++) {
    // 层2: 正向锚点扩散
    final anchor = (anchors[r] - 1) % n;
    final seed = c[anchor];
    for (var i = 0; i < n; i++) {
      if (i == anchor) continue;
      c[i] = (c[i] ^ (seed + i * 17 + r * 11)) & 0xff;
    }
    rotLeft(c, (r + 1) % n);
  }

  c = xorBytes(c, m2); // 层3

  for (var r = 0; r < 7; r++) {
    // 层4: 反向锚点扩散
    final anchor = (anchors[6 - r] - 1) % n;
    final seed = c[anchor];
    for (var i = 0; i < n; i++) {
      if (i == anchor) continue;
      c[i] = (c[i] ^ (seed + i * 23 + r * 5)) & 0xff;
    }
    rotRight(c, (r + 2) % n);
  }

  c = xorBytes(c, m3); // 层5
  return c;
}

Uint8List unscramble(
  Uint8List c,
  Uint8List m1,
  Uint8List m2,
  Uint8List m3,
) {
  final n = c.length;
  var out = Uint8List.fromList(c);

  out = xorBytes(out, m3); // 反层5

  for (var r = 6; r >= 0; r--) {
    // 反层4
    rotLeft(out, (r + 2) % n);
    final anchor = (anchors[6 - r] - 1) % n;
    final seed = out[anchor];
    for (var i = 0; i < n; i++) {
      if (i == anchor) continue;
      out[i] = (out[i] ^ (seed + i * 23 + r * 5)) & 0xff;
    }
  }

  out = xorBytes(out, m2); // 反层3

  for (var r = 6; r >= 0; r--) {
    // 反层2
    rotRight(out, (r + 1) % n);
    final anchor = (anchors[r] - 1) % n;
    final seed = out[anchor];
    for (var i = 0; i < n; i++) {
      if (i == anchor) continue;
      out[i] = (out[i] ^ (seed + i * 17 + r * 11)) & 0xff;
    }
  }

  out = xorBytes(out, m1); // 反层1
  return out;
}

void main() {
  final m1 = randomBytes(Random(0x1111), 32);
  final m2 = randomBytes(Random(0x2222), 32);
  final m3 = randomBytes(Random(0x3333), 32);

  const plain = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
  final k = hexToBytes(plain);
  final c = scramble(k, m1, m2, m3);
  final r = unscramble(c, m1, m2, m3);

  print('m1: ${bytesToHex(m1)}');
  print('m2: ${bytesToHex(m2)}');
  print('m3: ${bytesToHex(m3)}');
  print('scrambled: ${bytesToHex(c)}');
  print('restored : ${bytesToHex(r)}');
  print('match    : ${bytesToHex(r) == plain}');
}
