import '../../core/utils/json_util.dart';
import '../../config/constants.dart';

/// 歌曲模型
class Song {
  final int id;
  final String name;
  final int singerId;
  final String singerName;
  final int albumId;
  final String albumName;
  final int duration;
  final String cover;
  final String url;
  final String url128;
  final String url320;
  final String urlFlac;
  final int playCount;
  final int likeCount;
  final int commentCount;
  final String releaseDate;
  final bool isCollected;

  /// 歌词(仅详情页返回时才有)
  final String lyric;

  /// 音频 MD5(由 /song/url 下发,与该地址配对,用于校验本地缓存完整性)
  ///
  /// 为空表示后端没有该音源的指纹(多为远程外链),此时跳过校验。
  final String md5;

  /// 各音质各自的 MD5(列表 / 详情接口下发)
  final String md5128;
  final String md5320;
  final String md5Flac;

  Song({
    required this.id,
    required this.name,
    this.singerId = 0,
    this.singerName = '',
    this.albumId = 0,
    this.albumName = '',
    this.duration = 0,
    this.cover = '',
    this.url = '',
    this.url128 = '',
    this.url320 = '',
    this.urlFlac = '',
    this.playCount = 0,
    this.likeCount = 0,
    this.commentCount = 0,
    this.releaseDate = '',
    this.isCollected = false,
    this.lyric = '',
    this.md5 = '',
    this.md5128 = '',
    this.md5320 = '',
    this.md5Flac = '',
  });

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: JsonUtil.toInt(json['id']),
      name: JsonUtil.toStr(json['name']),
      singerId: JsonUtil.toInt(json['singer_id']),
      singerName: JsonUtil.toStr(json['singer_name']),
      albumId: JsonUtil.toInt(json['album_id']),
      albumName: JsonUtil.toStr(json['album_name']),
      duration: JsonUtil.toInt(json['duration']),
      cover: JsonUtil.toUrl(json['cover']),
      url: JsonUtil.toUrl(json['url']),
      url128: JsonUtil.toUrl(json['url_128']),
      url320: JsonUtil.toUrl(json['url_320']),
      urlFlac: JsonUtil.toUrl(json['url_flac']),
      playCount: JsonUtil.toInt(json['play_count']),
      likeCount: JsonUtil.toInt(json['like_count']),
      commentCount: JsonUtil.toInt(json['comment_count']),
      releaseDate: JsonUtil.toStr(json['release_date']),
      isCollected: JsonUtil.toBool(json['is_collected']),
      lyric: JsonUtil.toStr(json['lyric']),
      md5: JsonUtil.toStr(json['md5']),
      md5128: JsonUtil.toStr(json['md5_128']),
      md5320: JsonUtil.toStr(json['md5_320']),
      md5Flac: JsonUtil.toStr(json['md5_flac']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'singer_id': singerId,
        'singer_name': singerName,
        'album_id': albumId,
        'album_name': albumName,
        'duration': duration,
        'cover': cover,
        'url': url,
        'url_128': url128,
        'url_320': url320,
        'url_flac': urlFlac,
        'play_count': playCount,
        'like_count': likeCount,
        'comment_count': commentCount,
        'release_date': releaseDate,
        'is_collected': isCollected,
        'lyric': lyric,
      };

  /// 实际播放地址(优先非空)
  String get playUrl {
    if (url.isNotEmpty) return url;
    if (url320.isNotEmpty) return url320;
    if (url128.isNotEmpty) return url128;
    if (urlFlac.isNotEmpty) return urlFlac;
    return '';
  }

  /// 取该音质对应的 MD5(空 = 后端无指纹,跳过校验)
  ///
  /// 优先用 /song/url 下发的 md5(它和当前播放地址是配对的),
  /// 没有再按音质取列表里的字段。
  String md5ForQuality(String quality) {
    if (md5.isNotEmpty) return md5;

    switch (quality) {
      case '128':
        return md5128;
      case 'flac':
        return md5Flac;
      case '320':
      default:
        return md5320;
    }
  }

  /// 该音质档位**文件自己的**指纹
  ///
  /// 与 [md5ForQuality] 的区别:那个优先用 /song/url 下发的「配对 md5」,
  /// 而配对 md5 可能是后端兜底到别的档位后的指纹。缓存键必须精确对应
  /// 「这一档的文件」,所以这里只看按档位存的字段。
  String md5OfQualityField(String quality) {
    switch (quality) {
      case '128':
        return md5128;
      case 'flac':
        return md5Flac;
      case '320':
      default:
        return md5320;
    }
  }

  /// 后端实际会输出的音质档位(按与后端 PickAudio 相同的兜底顺序推算)
  ///
  /// 后端在「请求的档位没有文件」时会兜底:320 → 128 → flac。
  /// 客户端按同一套规则推算,缓存键才能和后端真正给的文件对上,
  /// 否则会出现「请求 128,却按 128 的键去存 320 的内容」。
  String effectiveQuality(String quality) {
    switch (quality) {
      case 'flac':
        if (urlFlac.isNotEmpty) return 'flac';
        break;
      case '128':
        if (url128.isNotEmpty) return '128';
        break;
      case '320':
      default:
        if (url320.isNotEmpty) return '320';
        break;
    }
    if (url320.isNotEmpty) return '320';
    if (url128.isNotEmpty) return '128';
    if (urlFlac.isNotEmpty) return 'flac';
    return quality;
  }

  /// 按音质取地址
  String urlForQuality(String quality) {
    switch (quality) {
      case 'flac':
        return urlFlac.isNotEmpty ? urlFlac : playUrl;
      case '128':
        return url128.isNotEmpty ? url128 : playUrl;
      case '320':
      default:
        return url320.isNotEmpty ? url320 : playUrl;
    }
  }

  String get coverUrl => cover.isEmpty ? AppConstants.defaultCover : cover;

  String get durationText => formatDuration(duration);

  String get subtitle =>
      singerName.isEmpty ? albumName : '$singerName${albumName.isNotEmpty ? ' · $albumName' : ''}';

  Song copyWith({
    bool? isCollected,
    String? lyric,
    String? url,
    String? md5,
  }) {
    return Song(
      id: id,
      name: name,
      singerId: singerId,
      singerName: singerName,
      albumId: albumId,
      albumName: albumName,
      duration: duration,
      cover: cover,
      url: url ?? this.url,
      url128: url128,
      url320: url320,
      urlFlac: urlFlac,
      playCount: playCount,
      likeCount: likeCount,
      commentCount: commentCount,
      releaseDate: releaseDate,
      isCollected: isCollected ?? this.isCollected,
      lyric: lyric ?? this.lyric,
      md5: md5 ?? this.md5,
      // 关键:这几个「按音质存的指纹」必须一起带上。
      // 之前漏传 → copyWith 之后它们全变空串,而本地缓存的键正是它们,
      // 于是「解析播放地址」时明明后端下发了指纹,却被当成「无音频指纹」跳过缓存。
      md5128: md5128,
      md5320: md5320,
      md5Flac: md5Flac,
    );
  }

  @override
  bool operator ==(Object other) => other is Song && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// 播放地址 + 音频指纹(GET /song/url)
class SongUrl {
  final String url;

  /// 音频 MD5(空 = 后端没有该音源指纹,跳过校验)
  final String md5;

  /// 请求的音质档位(与 url 里的 q 一致)
  final String quality;

  /// 实际输出的音质档位(无对应文件时后端会回退,可能与 [quality] 不同)
  final String actualQuality;

  /// 后端是否发生了音质回退(该歌曲没有请求音质的文件)
  final bool fallback;

  const SongUrl({
    required this.url,
    this.md5 = '',
    this.quality = '320',
    this.actualQuality = '',
    this.fallback = false,
  });

  bool get isEmpty => url.isEmpty;
  bool get isNotEmpty => url.isNotEmpty;
}
