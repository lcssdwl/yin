// 临时验证:本地缓存键与歌曲 ID 解耦(验证完即删)
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/data/models/song.dart';

const _a = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _b = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

/// 与 PlayerProvider._cacheKeyOf 的组合方式一致:
/// 先按后端兜底规则推算「实际音质」,再取该档位文件自己的指纹。
String keyOf(Song s, String quality) {
  final q = s.effectiveQuality(quality);
  return '${s.md5OfQualityField(q)}_$q';
}

void main() {
  test('实际音质按后端兜底顺序推算(请求档 → 320 → 128 → flac)', () {
    final full = Song(
      id: 1,
      name: 'x',
      url320: 'u320',
      url128: 'u128',
      urlFlac: 'uflac',
    );
    expect(full.effectiveQuality('128'), '128');
    expect(full.effectiveQuality('320'), '320');
    expect(full.effectiveQuality('flac'), 'flac');

    // 请求 128 但没生成 128 档 → 后端会兜底到 320
    final no128 = Song(id: 1, name: 'x', url320: 'u320');
    expect(no128.effectiveQuality('128'), '320');
    expect(no128.effectiveQuality('flac'), '320');

    // 只有无损源
    final onlyFlac = Song(id: 1, name: 'x', urlFlac: 'uflac');
    expect(onlyFlac.effectiveQuality('128'), 'flac');
  });

  test('ID 被复用(后端重建库)时键必须不同 —— 否则就是串歌', () {
    final before = Song(id: 3, name: 'A', url320: 'u', md5320: _a);
    final after = Song(id: 3, name: 'B', url320: 'u', md5320: _b);

    // 用 ID 当键时两者相等 → 老缓存会被新歌认领,播出来是另一首
    expect(before.id, after.id);
    // 用指纹当键就不会
    expect(keyOf(before, '320'), isNot(keyOf(after, '320')));
  });

  test('同一份音频换了 ID(重扫后常见)键不变 → 缓存继续命中', () {
    final before = Song(id: 3, name: 'A', url320: 'u', md5320: _a);
    final after = Song(id: 77, name: 'A', url320: 'u', md5320: _a);

    expect(keyOf(before, '320'), keyOf(after, '320'));
  });

  test('不同音质是不同的键 → 分开存,互不覆盖', () {
    final s = Song(
      id: 1,
      name: 'A',
      url320: 'u320',
      url128: 'u128',
      md5320: _a,
      md5128: _b,
    );

    expect(keyOf(s, '320'), '${_a}_320');
    expect(keyOf(s, '128'), '${_b}_128');
    expect(keyOf(s, '320'), isNot(keyOf(s, '128')));
  });

  test('兜底档用的也是该档自己的指纹,不是请求档的', () {
    // 请求 128,但只有 320 文件:键要落在 320 的指纹+档位上,
    // 才能和后端实际给的那份 320 文件对上(下载校验也才过得去)
    final s = Song(id: 1, name: 'A', url320: 'u320', md5320: _a);
    expect(keyOf(s, '128'), '${_a}_320');
  });

  test('后端没算出指纹时取不到键 → 不缓存,宁可不命中也不串歌', () {
    final s = Song(id: 1, name: 'A', url320: 'u320');
    expect(s.md5OfQualityField(s.effectiveQuality('320')), isEmpty);
  });

  test('copyWith 不能丢按音质存的指纹(丢了解析地址后就查不到缓存)', () {
    final s = Song(
      id: 1,
      name: 'A',
      url320: 'u320',
      urlFlac: 'uflac',
      md5128: _a,
      md5320: _b,
      md5Flac: _a,
      md5: _b,
    );

    // 秒播路径:只换播放地址
    final played = s.copyWith(url: 'http://x/1.mp3');
    expect(played.md5320, _b);
    expect(played.md5128, _a);
    expect(played.md5Flac, _a);
    expect(keyOf(played, '320'), '${_b}_320');

    // 联网路径:同时换地址和配对指纹
    final fresh = s.copyWith(url: 'http://x/2.mp3', md5: _a);
    expect(fresh.md5320, _b);
    expect(fresh.md5128, _a);
    expect(fresh.md5Flac, _a);
    expect(keyOf(fresh, '320'), '${_b}_320');
  });
}
