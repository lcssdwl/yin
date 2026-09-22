import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// API 数据加解密(AES-256-CBC,与后端 openssl `aes-256-cbc` 一致)
class CryptoUtil {
  CryptoUtil._();

  /// 密钥混淆存储(5 层包裹):
  /// 明文 key 经「掩码A → 7轮正向锚点扩散 → 掩码B → 7轮反向锚点扩散 → 掩码C」打散,
  /// 这里只存最终乱码 + 三个掩码,libapp.so 里不再出现明文 key。
  /// 锚点位置(1-based):第 5/9/7/10/18/19/1 位,共 7 个 → 每组 7 轮。
  static const String _scrambledHex =
      'a1feb6b390d0e3b5678b2e8c8a85fbf797c0b652ee7b802cc27e002c36218b25';
  static const String _maskA =
      '163c18ea00299de128d8889f4c3891ed4533a746425ac42b68db6a4a648560a8';
  static const String _maskB =
      'cc838968a8fe5d3982d6ade81776528b0dd956b9a4eef7d8e39a60ae4b3aab47';
  static const String _maskC =
      '0d3742d79f6db43952fede0941c9fdc6c33279d966a8af88ca9e7d3ec4f9616c';
  static const List<int> _anchors = [5, 9, 7, 10, 18, 19, 1];

  static Uint8List _keyBytes() => _unscramble(_hexToBytes(_scrambledHex));

  /// 乱码 → 明文 key(逆向执行 5 层包裹)
  static Uint8List _unscramble(Uint8List c) {
    final n = c.length;
    var out = Uint8List.fromList(c);
    final m1 = _hexToBytes(_maskA);
    final m2 = _hexToBytes(_maskB);
    final m3 = _hexToBytes(_maskC);

    out = _xorBytes(out, m3); // 反层5
    for (var r = 6; r >= 0; r--) {
      _rotLeft(out, (r + 2) % n); // 反层4(反向锚点扩散)
      final anchor = (_anchors[6 - r] - 1) % n;
      final seed = out[anchor];
      for (var i = 0; i < n; i++) {
        if (i == anchor) continue;
        out[i] = (out[i] ^ (seed + i * 23 + r * 5)) & 0xff;
      }
    }
    out = _xorBytes(out, m2); // 反层3
    for (var r = 6; r >= 0; r--) {
      _rotRight(out, (r + 1) % n); // 反层2(正向锚点扩散)
      final anchor = (_anchors[r] - 1) % n;
      final seed = out[anchor];
      for (var i = 0; i < n; i++) {
        if (i == anchor) continue;
        out[i] = (out[i] ^ (seed + i * 17 + r * 11)) & 0xff;
      }
    }
    out = _xorBytes(out, m1); // 反层1
    return out;
  }

  static Uint8List _xorBytes(Uint8List a, Uint8List b) {
    final out = Uint8List(a.length);
    for (var i = 0; i < a.length; i++) {
      out[i] = (a[i] ^ b[i]) & 0xff;
    }
    return out;
  }

  static void _rotLeft(Uint8List a, int steps) {
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

  static void _rotRight(Uint8List a, int steps) =>
      _rotLeft(a, a.length - (steps % a.length));

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  /// 解密 base64(iv(16B) + 密文) → 明文 JSON 字符串
  static Future<String> decryptBase64(String base64Data) async {
    final raw = base64Decode(base64Data);
    final iv = raw.sublist(0, 16);
    final cipher = raw.sublist(16);

    final algo = AesCbc.with256bits(macAlgorithm: MacAlgorithm.empty);
    final plain = await algo.decrypt(
      SecretBox(cipher, nonce: iv, mac: Mac.empty),
      secretKey: SecretKey(_keyBytes()),
    );
    return utf8.decode(plain);
  }

  /// 加密明文 → base64(iv(16B) + 密文)
  static Future<String> encryptBase64(String plain) async {
    final iv = Uint8List.fromList(
      List.generate(16, (_) => Random.secure().nextInt(256)),
    );
    final algo = AesCbc.with256bits(macAlgorithm: MacAlgorithm.empty);
    final box = await algo.encrypt(
      utf8.encode(plain),
      secretKey: SecretKey(_keyBytes()),
      nonce: iv,
    );
    return base64Encode([...iv, ...box.cipherText]);
  }
}
