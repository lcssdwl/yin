import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../config/constants.dart';
import '../core/audio/audio_cache.dart';
import '../core/audio/audio_handler.dart';
import '../core/audio/lyrics_parser.dart';
import '../core/log/app_log.dart';
import '../core/storage/storage_service.dart';
import '../data/models/app_config.dart';
import '../data/models/song.dart';
import '../data/repositories/music_repository.dart';
import '../data/repositories/user_repository.dart';
import '../core/network/api_exception.dart';
import 'auth_provider.dart';

/// 播放器状态
///
/// 关键:游客也能完整使用播放、收藏、历史
/// - 收藏:登录→云端接口;游客→写入本地 Hive
/// - 历史:登录→后端记录;游客→写入本地 Hive
class PlayerProvider extends ChangeNotifier {
  final MusicAudioHandler _handler;
  final AuthProvider _auth;

  final MusicRepository _musicRepo = MusicRepository();
  final UserRepository _userRepo = UserRepository();

  List<Song> _queue = [];
  int _currentIndex = -1;
  PlayMode _mode = PlayMode.listLoop; // 默认列表循环(播完最后一首自动回第一首)
  bool _loading = false;

  /// 切歌代号:每发起一次切歌 +1
  ///
  /// 切歌是异步的(要解析播放地址),而「下一首 / 上一首」会被连着点。
  /// 旧的那次解析回来时下标早被新的一次改掉了 —— 如果还按 [_currentIndex]
  /// 回写队列,就会把「上一首」的地址写进新下标:旧位置还留着那首歌,
  /// 新位置又被覆盖成同一首,播放列表里于是出现两首一样的歌。
  /// 用代号把过期结果整段丢弃(不回写、不载入、不复位状态)。
  int _playToken = 0;

  /// 「应该正在播放」的意图标记
  ///
  /// [PlayerProvider._confirmPlayingOnWindows] 会补发 play() 来修 Windows 的
  /// 换源竞态;若用户在这期间点了暂停,补发就会把音乐又拉起来 —— 所以补发前
  /// 必须先看这个意图标记。
  bool _wantPlaying = false;

  /// 当前这首已经上报过的播放秒数(只报增量,避免同一段重复累计)
  int _reportedSec = 0;

  /// 是否正在缓冲(切歌 / 弱网时 UI 转圈)
  ///
  /// 取自播放器真实状态(loading / buffering),而不是 [_loading] ——
  /// 缓存命中时本地文件瞬间可用,这里几乎不会置 true,也就不会闪一下转圈。
  bool _buffering = false;

  /// 是否正在切歌(点下一首 / 上一首 / 选歌)
  ///
  /// 与 [_buffering] 的区别:这个是「点了就立刻转」,并带最短显示时长,
  /// 所以就算命中缓存秒开,用户也能看到一圈,不会以为点了没反应。
  bool _switching = false;

  /// 播放中卡顿的宽限计时器(弱网下先不转圈,连续卡顿才提示)
  Timer? _stallTimer;

  /// 切歌兜底:不管卡在哪一步,超时强制撤掉转圈,避免「一直转 + 不切歌」
  Timer? _switchGuard;

  /// 最近一次「播完切歌」处理的时刻(onComplete 防抖)
  DateTime? _lastCompleteAt;

  String _lyric = '';
  List<LyricLine> _lyricLines = [];

  /// 定时关闭:倒计时定时器
  Timer? _sleepTimer;

  /// 定时关闭剩余秒数(0 表示未启用倒计时)
  int _sleepSecondsLeft = 0;

  /// 是否设为"本首歌结束后停止"
  bool _sleepEndOfSong = false;

  /// 收藏ID集合(登录后从云端加载,游客取本地)
  final Set<int> _favoriteIds = {};

  /// 最近一次播放错误提示(UI 读取后调用 clearError 清掉)
  String? _errorMessage;

  /// 播放被拦截原因:需要登录
  /// (后端开启「音频需登录才能播放」且当前未登录时置位,UI 据此弹登录引导)
  bool _needLogin = false;

  /// 当前播放音质(默认「标准」128,可在播放页切换)
  String _quality = StorageService.quality;

  /// 当前歌曲**实际**播放的档位
  ///
  /// 与 [_quality](用户选的档位)的区别:这首歌没有所选档位的音源时,
  /// 后端会兜底到别的档位(如选无损但没有 flac 文件,实际放 320)。
  /// 播放页要显示真正在放的那一档,否则就是「页面写着无损、耳朵听到高品质」。
  /// null 表示这一轮还没解析出结果。
  String? _actualQuality;

  /// 后台下发的音质策略(音质列表 + 各音质是否需要登录)
  AppConfig _appConfig = const AppConfig();

  /// 是否已成功拿到后台音质策略
  /// (没拿到就不提前提示「需要登录」,避免策略未知时误报)
  bool _configLoaded = false;

  /// 「此音质需要登录」提示文案(非空时播放页底部展示)
  String? _qualityLoginHint;

  /// 音质相关提示:如「「标准」暂无音源,已用「高品质」播放」
  ///
  /// 后端在该歌曲没有请求音质的文件时会静默回退到别的档位,
  /// 这里把回退结果明示给用户,并可一键切到实际音质。
  /// 记录回退后的实际音质(供提示里的「切换」按钮使用)
  String? _qualityNotice;
  String? _qualityNoticeActual;

  /// 需登录时回调(由 main.dart 注入,用全局 navigator 弹登录引导,
  /// 这样无论当前在哪个页面都能弹窗,不依赖 PlayerPage 是否挂载)
  void Function(String)? onRequireLogin;

  /// 连续播放失败次数(避免在坏文件上无限跳过)
  int _consecutiveErrors = 0;

  PlayerProvider(this._handler, this._auth) {
    _favoriteIds.addAll(StorageService.localFavorites);

    _handler.onSkipNext = next;
    _handler.onSkipPrevious = previous;
    _handler.onComplete = _onComplete;
    // 收藏:把切换/查询能力注入音频后台服务,供通知栏心形按钮调用
    _handler.onToggleFavorite = toggleFavoriteCurrent;
    _handler.isFavorite = isFavorite;
    _handler.onPlaybackError = _onPlaybackError;

    // 播放 / 缓冲状态:刷新 UI(通知栏由 audio_service 的 MediaSession 自动维护)
    //
    // 注意:不能只凭 processingState 判断「正在加载」——
    // 弱网下 just_audio 会在播放过程中反复进入 buffering,而此时声音是不断续的,
    // 直接转圈就会出现「已经出声了还在转」。
    // 规则:没出声(playing=false)才立即转圈;已出声则给 2 秒宽限,持续卡才提示。
    _handler.player.playerStateStream.listen((st) {
      notifyListeners();
      _updateBuffering(st);
    });

    // 登录态变化:登录后立即清掉「此音质需要登录」提示
    _auth.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (_auth.isLoggedIn) {
      // 登录后立即从云端刷新收藏集合,避免继续显示游客态的本地收藏
      if (_qualityLoginHint != null) _qualityLoginHint = null;
      unawaited(loadFavorites());
    } else {
      // 退出登录:把当前云端收藏快照写回本地,
      // 保证「退出使用本地」依旧可用(本地数据不再被登录合并时清空)
      unawaited(StorageService.setLocalFavorites(_favoriteIds.toList()));
    }
    notifyListeners();
  }

  void _setBuffering(bool value) {
    if (_buffering == value) return;
    _buffering = value;
    debugPrint('[player] buffering=$value playing=${_handler.player.playing} '
        'state=${_handler.player.processingState}');
    notifyListeners();
  }



  /// 根据播放器真实状态决定是否转圈
  ///
  /// 规则只有一条:**出声了就不转圈**。
  ///
  /// 之前还额外判断「卡了多久」「位置有没有在走」,但弱网下 just_audio 会在
  /// 播放中反复进出 buffering、声音却是连续的,怎么调都会出现
  /// 「已经在播了还一直转」。宁可不报,也不要一直转。
  void _updateBuffering(PlayerState st) {
    final stalled = st.processingState == ProcessingState.loading ||
        st.processingState == ProcessingState.buffering;

    _stallTimer?.cancel();
    _stallTimer = null;
    // st.playing 为 true 说明已经出声,这时一律不转
    _setBuffering(stalled && !st.playing);
  }

  // ==================== Getter ====================

  List<Song> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  PlayMode get mode => _mode;
  bool get loading => _loading;

  /// 是否正在缓冲(切歌加载中 / 网络卡顿)
  bool get buffering => _buffering;

  /// 是否正在切歌(UI 应立即转圈)
  bool get switching => _switching;
  String get lyric => _lyric;
  List<LyricLine> get lyricLines => List.unmodifiable(_lyricLines);

  Song? get currentSong =>
      (_currentIndex >= 0 && _currentIndex < _queue.length)
          ? _queue[_currentIndex]
          : null;

  bool get isPlaying => _handler.player.playing;
  bool get hasSong => currentSong != null;

  Stream<Duration> get positionStream => _handler.player.positionStream;
  Stream<Duration?> get durationStream => _handler.player.durationStream;
  Stream<PlayerState> get playerStateStream => _handler.player.playerStateStream;

  bool isFavorite(int songId) => _favoriteIds.contains(songId);

  /// 播放错误提示(可能为 null)
  String? get errorMessage => _errorMessage;

  /// 是否因「需登录」被拦截(UI 弹登录引导而非普通提示)
  bool get needLogin => _needLogin;

  /// UI 显示过提示后调用
  void clearError() {
    _errorMessage = null;
  }

  // ==================== 音质 ====================

  /// 用户选择的播放音质(设置项)
  String get quality => _quality;

  /// 当前歌曲实际播放的档位(还没解析出地址时等于 [quality])
  String get actualQuality => _actualQuality ?? _quality;

  /// 这首歌是否发生了音质回退(所选档位没有音源,实际放了别的档位)
  bool get qualityFallback =>
      _actualQuality != null && _actualQuality != _quality;

  /// 当前**实际**音质显示名(播放页胶囊显示这个,而不是所选档位)
  String get qualityLabel => _appConfig.labelOf(actualQuality);

  /// 取任意音质的显示名(UI 文案用)
  String labelOfQuality(String q) => _appConfig.labelOf(q);

  /// 可选音质列表(后台未下发时回退本地默认三项)
  List<QualityOption> get qualityOptions {
    if (_appConfig.qualities.isNotEmpty) return _appConfig.qualities;
    return const [
      QualityOption(value: '128', label: '标准'),
      QualityOption(value: '320', label: '高品质'),
      QualityOption(value: 'flac', label: '无损'),
    ];
  }

  /// 该音质是否需要登录才能播放
  ///
  /// 已登录 → 永远不需要;后台策略还没拉到时返回 false(不提前误报)。
  bool qualityNeedsLogin(String q) {
    if (_auth.isLoggedIn) return false;
    if (!_configLoaded) return false;
    return _appConfig.requiresLogin(q);
  }

  /// 「此音质需要登录」提示(非空时播放页底部展示,见 UI)
  String? get qualityLoginHint => _qualityLoginHint;

  /// UI 处理完(如弹过登录)后清除提示
  void clearQualityLoginHint() {
    if (_qualityLoginHint == null) return;
    _qualityLoginHint = null;
    notifyListeners();
  }

  /// 音质提示文案:如「「标准」暂无音源,已用「高品质」播放」(可能为 null)
  String? get qualityNotice => _qualityNotice;

  /// 提示里提到的实际音质(点「切换」时切到它)
  String? get qualityNoticeActual => _qualityNoticeActual;

  void clearQualityNotice() {
    if (_qualityNotice == null) return;
    _qualityNotice = null;
    _qualityNoticeActual = null;
    notifyListeners();
  }

  /// 按当前歌曲重算「音质回退」提示(不重新加载音频)
  ///
  /// 用在「点的是已经选中的档位」这种情况:不需要重新解析,
  /// 但提示条必须和实际在放的档位一致,否则就是「胶囊写着高品质、却没有任何解释」。
  void _refreshQualityNotice() {
    final song = currentSong;
    if (song == null) return;

    // 与后端同一套兜底规则:请求档 → 320 → 128 → flac
    final actual = song.effectiveQuality(_quality);
    if (actual == _quality) return;
    if (_qualityNotice != null && _qualityNoticeActual == actual) return;

    _qualityNotice = '「${_appConfig.labelOf(_quality)}」暂无音源,'
        '已用「${_appConfig.labelOf(actual)}」播放';
    _qualityNoticeActual = actual;
    AppLog.add('[player] 重算音质提示:请求 $_quality 实际 $actual');
    notifyListeners();
  }

  /// 当前歌曲是否真的有该音质的音源
  ///
  /// 返回 null = 无法判断(列表没下发分音质地址),UI 此时不要标「暂无」,
  /// 免得误伤 —— 后端仍可能兜底给出别的档位。
  bool? currentSongHasQuality(String q) {
    final s = currentSong;
    if (s == null) return null;
    return _songHasQuality(s, q);
  }

  /// 某首歌是否有该音质的专用地址(client 侧能判断时)
  bool? _songHasQuality(Song s, String q) {
    if (s.url128.isEmpty && s.url320.isEmpty && s.urlFlac.isEmpty) return null;
    switch (q) {
      case '128':
        return s.url128.isNotEmpty;
      case 'flac':
        return s.urlFlac.isNotEmpty;
      default:
        return s.url320.isNotEmpty;
    }
  }

  /// 拉取后台音质策略(启动 / 首次播放时调用,失败静默)
  Future<void> loadAppConfig() async {
    try {
      final cfg = await _musicRepo.getAppConfig();
      _appConfig = cfg;
      _configLoaded = true;
      notifyListeners();
    } catch (_) {
      // 拉取失败:保持「策略未知」,不提示需登录,由播放时 401 兜底
    }
  }

  /// 切换播放音质,返回是否切换成功
  ///
  /// 需登录的音质在未登录时**不切换**,只在播放页底部提示「此音质需要登录」;
  /// 切换成功后当前歌曲会按新音质重新加载(缓存按音质分目录,自动走新音质)。
  Future<bool> setQuality(String q) async {
    if (q == _quality) {
      clearQualityLoginHint();
      // 点的就是当前档位:不必重新加载,但提示条要和实际播放的档位对齐
      // (例如先进播放页时走的是缓存,那时还没来得及算提示)
      _refreshQualityNotice();
      return true;
    }

    if (qualityNeedsLogin(q)) {
      _qualityLoginHint = '「${_appConfig.labelOf(q)}」此音质需要登录后播放';
      AppLog.add('[player] 切换音质被拦截 → ${_appConfig.labelOf(q)}($q): 需登录');
      notifyListeners();
      return false;
    }

    _qualityLoginHint = null;
    _qualityNotice = null;
    _qualityNoticeActual = null;
    AppLog.add('[player] 切换音质 → ${_appConfig.labelOf(q)}($q)');
    _quality = q;
    await StorageService.setQuality(q);

    // 清掉队列里这首歌的旧音质地址与指纹:
    // 它和旧音质是配对的,留着会被 _resolvePlayable 当「可用地址」直接复用,
    // 表现就是「切了音质还在播旧音质」。清掉后按新音质重新解析(列表地址或联网)。
    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      _queue[_currentIndex] = _queue[_currentIndex].copyWith(url: '', md5: '');
    }
    notifyListeners();

    // 正在播放的歌立刻按新音质重新加载
    if (currentSong != null) {
      await _playAt(_currentIndex);
    }
    return true;
  }

  /// 定时关闭剩余秒数
  int get sleepSecondsLeft => _sleepSecondsLeft;

  /// 是否"本首歌结束后停止"
  bool get sleepEndOfSong => _sleepEndOfSong;

  /// 定时关闭是否生效
  bool get sleepActive => _sleepTimer != null || _sleepEndOfSong;

  // ==================== 播放控制 ====================

  /// 播放某首歌(可附带播放列表作为队列)
  Future<void> playSong(Song song, {List<Song>? playlist}) async {
    final list = playlist ?? [song];
    final index = list.indexWhere((e) => e.id == song.id);
    await playQueue(list, index < 0 ? 0 : index);
  }

  /// 播放队列(点击列表时调用,一次性保存列表)
  Future<void> playQueue(List<Song> songs, int index) async {
    if (songs.isEmpty || index < 0 || index >= songs.length) {
      // 提前返回也要复位,否则转圈会一直转
      _switching = false;
      notifyListeners();
      return;
    }

    // 关键:列表在点击这一刻就固定下来,后续切歌只改下标、绝不重建 _queue,
    // 这样「左右切歌」不会影响播放列表的数据(不会重复/不会变序)。
    _queue = List<Song>.from(songs);
    await _playAt(index);
  }

  /// 加载并播放队列第 [index] 首(不改 _queue 列表本身)
  ///
  /// 连点切歌时会有多次调用同时在跑,靠 [_playToken] 保证只有最后一次算数:
  /// 过期的解析结果一律丢弃,避免写坏队列或把新歌顶掉。
  Future<void> _playAt(int index) async {
    // 先把上一首已听的秒数上报掉 —— 此刻 currentSong / position 还指向上一首
    // (flushListen 内部先同步取值再发请求,不会受下面改下标影响)
    unawaited(flushListen());

    final token = ++_playToken; // 本次切歌的代号
    final idx = index; // 本次要播的下标(不随后续切歌再变)

    _currentIndex = idx;
    _reportedSec = 0; // 换歌:听歌秒数从头计
    _loading = true;
    _switching = true;
    _wantPlaying = true; // 用户点的是播放/切歌,意图就是要它响
    _needLogin = false; // 新一轮播放,清除上一次的「需登录」标记
    _qualityLoginHint = null;
    _qualityNotice = null; // 音质回退提示同样只反映当前这一轮
    _qualityNoticeActual = null;
    _actualQuality = null; // 实际档位也重新解析,避免沿用上一首的结论
    debugPrint('[player] switching=true (_playAt #$index)');

    if (idx >= 0 && idx < _queue.length) {
      final s = _queue[idx];
      AppLog.add('[player] 开始播放 #${s.id} ${s.name} '
          '音质=$_quality 队列=${_queue.length} 序号=${idx + 1}');
    }

    // 兜底:不管下面哪一步 await 卡住(网络探测 / audio focus 等),
    // 8 秒后强制撤掉转圈。
    _switchGuard?.cancel();
    _switchGuard = Timer(const Duration(seconds: 8), () {
      if (_switching) {
        debugPrint('[player] switching 超时兜底复位');
        _switching = false;
        _loading = false;
        notifyListeners();
      }
    });

    notifyListeners();

    try {
      // 解析播放地址:优先本地缓存;没有则立即流式播放,同时在后台缓存
      final song = await _resolvePlayable(_queue[idx]);

      // 解析期间又切了歌:这一次的结果作废。
      // 这里必须直接返回 —— 若继续按当前的 _currentIndex 回写,
      // 就会把这首歌写进新下标,队列里出现两首一样的歌,还会把新歌顶掉。
      if (token != _playToken) {
        AppLog.add('[player] 切歌过快,丢弃过期结果 #${song.id}'
            '(当前已切到 #${currentSong?.id ?? -1})');
        return;
      }

      _queue[idx] = song;

      await _handler.setQueue(_queue, index: idx);
      await _handler.loadSong(song);

      // 载入过程中又被切走(载入也要几百毫秒):同样交给新的那一次去收尾,
      // 否则这里复位状态会把新一次的转圈一起灭掉。
      if (token != _playToken) {
        AppLog.add('[player] 载入完成时已被新切歌取代,跳过状态复位');
        return;
      }

      // 不等 play() 返回 —— 它的 Future 可能卡在 audio focus 上,
      // 一旦卡住,下面 switching=false 永远执行不到 → 播放按钮一直转圈。
      unawaited(_playAsync(token));

      _loading = false;
      _switchGuard?.cancel();
      _switching = false;
      _stallTimer?.cancel();
      _stallTimer = null;
      _buffering = false;
      _consecutiveErrors = 0; // 播放成功,重置错误计数
      notifyListeners();

      // 确保 MediaSession 被激活(MIUI 妙播/媒体中心要求 active=true)
      unawaited(_handler.ensureSessionActive());

      unawaited(_loadLyric(song));
      unawaited(_reportPlay(song));
    } catch (_) {
      // 过期的那次失败不打扰当前这次(状态归最后一次切歌管)
      if (token == _playToken) {
        _loading = false;
        _stallTimer?.cancel();
        _stallTimer = null;
        _buffering = false;
        notifyListeners();
      }
    } finally {
      // 兜底复位只归最后一次切歌管:否则旧的那次会把新一次的转圈一起灭掉
      if (token == _playToken) {
        _switchGuard?.cancel();
        _switching = false;
        debugPrint('[player] switching=false (finally)');
        notifyListeners();
      }
    }
  }

  /// 解析出「最终用于播放的地址」
  ///
  /// 顺序:本地缓存 → 网络地址(必要时刷新签名)
  ///
  /// 没有缓存时**不等下载**:直接用网络地址流式播放(秒开),
  /// 同时在后台把这首歌下载并加密进缓存 —— 下次再听就是本地秒开 + 零流量。
  /// 缓存失败也完全不影响本次播放。
  Future<Song> _resolvePlayable(
    Song song, {
    bool useCache = true,
  }) async {
    // 本次解析所属的切歌代号:连点切歌时会有多次解析同时在跑,
    // 过期的那次只能返回地址,不能再去写「实际音质 / 回退提示」这类
    // 属于当前歌曲的状态 —— 否则在放 B,提示条却写着 A 的音质回退。
    final token = _playToken;
    bool stale() => token != _playToken;

    // 1) 本地缓存优先:离线也能播,秒开 + 零流量
    //
    // 键是「音频指纹 + 实际音质」,不是歌曲 ID(见 _cacheKeyOf 说明)。
    // 没有指纹时查不了,直接走网络 —— 这是刻意的:宁可不命中,也不串歌。
    if (useCache) {
      final key = _cacheKeyOf(song);
      if (key != null) {
        final local = await AudioCache.localPath(key.key, key.value);
        if (local != null) {
          debugPrint('[player] 用本地缓存 #${song.id} md5=${_shortMd5(key.key)} 音质=${key.value}');
          AppLog.add('[player] 用本地缓存 #${song.id} '
              '指纹=${_shortMd5(key.key)} 音质=${key.value}');
          if (!stale()) {
            // 缓存文件名里的档位就是这份音频真实档位(可能是兜底后的档位)
            _actualQuality = key.value;
            // 命中缓存也要给提示:选了无损却直接播缓存里的高品质时,
            // 不解释的话用户只会看到胶囊从「无损」跳成「高品质」,一脸问号。
            if (key.value != _quality) {
              _qualityNotice = '「${_appConfig.labelOf(_quality)}」暂无音源,'
                  '已用「${_appConfig.labelOf(key.value)}」播放';
              _qualityNoticeActual = key.value;
              notifyListeners();
            }
          }
          return song.copyWith(url: local);
        }
      }
    }

    // 2) 没有缓存 → 列表已下发地址就直接用(秒播,不联网)
    //
    // 注意:必须按**当前音质**取地址(urlForQuality),
    // 否则切了音质也会一直用列表里的默认地址(多为 320),音质设置形同虚设。
    final current = song.urlForQuality(_quality);
    // 游客(未登录)不信任列表/缓存下发的 http 地址直接「秒播」,
    // 必须先走 _fetchUrl 探测,后端开启「需登录才能播放」时才能正确拦截并弹登录。
    if (current.startsWith('http') && _auth.isLoggedIn) {
      final urlId = _urlSongId(current);
      final idOk = urlId == null || urlId == song.id;
      // 除了核对是不是这首歌,还必须确认地址里带的是**当前**登录令牌。
      //
      // 列表 / 播放队列很可能是登录前拉下来的,那些签名地址里根本没有 token。
      // 之前只看歌曲 id 就直接「秒播」,媒体接口会把请求当游客 → 401,
      // 表现就是「明明已经登录了,还是提示要登录 / 放不出声」。
      final tkOk = _urlCarriesCurrentToken(current);
      if (idOk && tkOk) {
        debugPrint('[player] 秒播(用列表地址 q=$_quality) #${song.id}');
        // 列表里若没有该音质的专用地址,说明这首歌还没生成这一档
        // (转码需要时间)。这里不发请求也能判断,直接提示,避免
        // 「看着是标准、其实在放列表默认的那一路」。
        //
        // 实际档位按后端同一套兜底规则推算(320 → 128 → flac):
        // 播放页显示的就是这一档,而不是用户选的那一档。
        final actual = song.effectiveQuality(_quality);
        if (!stale()) {
          _actualQuality = actual;
          if (actual != _quality) {
            _qualityNotice = '「${_appConfig.labelOf(_quality)}」暂无音源,'
                '已用「${_appConfig.labelOf(actual)}」播放';
            _qualityNoticeActual = actual;
            AppLog.add(
                '[player] 列表无 $_quality 专用地址 → 实际按 $actual 播放 #${song.id}');
            notifyListeners();
          }
        }
        AppLog.add('[player] 秒播(用列表地址,已带当前令牌) #${song.id} '
            '音质=$_quality 实际=$actual');
        // 把最终播放地址写回 url,供播放器与缓存使用
        final playable = song.copyWith(url: current);
        _prefetchFor(playable);
        return playable;
      }
      debugPrint('[player] 列表地址不可信(idOk=$idOk tkOk=$tkOk) → 联网纠正 #${song.id}');
      AppLog.add('[player] 列表地址不带上当前登录令牌(idOk=$idOk) → 联网重取 #${song.id}');
      final fixed = await _fetchUrl(song);
      _prefetchFor(fixed);
      return fixed;
    }

    // 3) 没有缓存、列表也没下发地址 → 联网取
    debugPrint('[player] 列表无地址 → 联网 #${song.id}');
    final fresh = await _fetchUrl(song);
    if (fresh.playUrl.startsWith('http')) {
      _prefetchFor(fresh);
    }
    return fresh;
  }

  /// 这个平台在换源后需要先对齐状态才能起播(目前只有 Windows)
  bool get _needAlignBeforePlay =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// 真正把「播放」下发出去
  ///
  /// Windows 上必须先对齐:just_audio 核心的 `play()` 第一行就是
  /// `if (playing) return;` —— 核心以为在播时它直接返回、一个字节都不发给平台。
  /// 而 WMF 换源后其实是暂停态,不先 pause 一下把两边拉平,这次 play() 就是空转
  /// (表现:「点了没反应/被按成暂停」)。
  ///
  /// 换源路径已经在 loadSong 里对齐过一次;这里再兜一次,覆盖 toggle / 重播等
  /// 不经过 loadSong 的入口。
  Future<void> _playNow() async {
    // 装载中不抢跑:此刻下发 play 请求,WMF 很可能紧接着被「换源」重置回暂停,
    // 白费一次;而且会让核心的 playing 提前变成 true,后面那次 play() 反而空转。
    // 交给「载入完成后」的那次 _playAsync 就行(它一定会执行)。
    if (_handler.player.processingState == ProcessingState.loading) {
      debugPrint('[player] 正在装载,稍后由载入完成的那次起播');
      return;
    }

    if (_needAlignBeforePlay && _handler.player.playing) {
      try {
        await _handler.pause();
        debugPrint('[player] Windows 起播前对齐:先 pause 再 play');
      } catch (e) {
        debugPrint('[player] 起播前 pause 失败(继续尝试 play): $e');
      }
    }
    await _handler.play();
  }

  /// 异步触发播放(不阻塞切歌流程,异常单独吞掉)
  ///
  /// [token] 本次切歌的代号:起播确认期间若又切了歌,就交回新的一次,不再插手。
  Future<void> _playAsync(int token) async {
    try {
      await _playNow();
    } catch (e) {
      debugPrint('[player] play error: $e');
      return;
    }
    unawaited(_confirmPlayingOnWindows(token));
  }

  /// Windows 起播确认(其它平台直接跳过)
  ///
  /// 为什么需要这一手:
  ///   Windows 端 just_audio 走的是 WinRT MediaPlayer(WMF)。WMF 的 `Source`
  ///   属性一旦被赋值(WMF 侧就是「换源 / 载入下一首」),播放器会**立即回到暂停态**;
  ///   而 just_audio 核心的 `play()` 第一行是 `if (playing) return;` ——
  ///   切歌那一刻核心还以为「在播」(它只认 pause/平台事件),于是这句 play()
  ///   直接返回,压根不向平台下发播放请求。等 WMF 的暂停事件传回 Dart 侧,
  ///   界面就停在暂停态了。
  ///   表现:「点下一首 / 上一首,转圈结束后不播,得再点一次播放按钮」。
  ///
  ///   Android 的 ExoPlayer 有 playWhenReady 语义(换源后自动续播),没这个问题,
  ///   所以只在 Windows 上补,免得动了手机端正常的续播行为。
  Future<void> _confirmPlayingOnWindows(int token) async {
    if (defaultTargetPlatform != TargetPlatform.windows) return;

    final p = _handler.player;
    var lastPos = p.position;

    for (var i = 0; i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 120));

      if (!_wantPlaying) return; // 用户已经暂停,别再把它拉起来
      if (token != _playToken) return; // 已经切到别的歌了

      final state = p.processingState;
      if (state == ProcessingState.completed) return; // 已经放完,不是「没起播」

      final pos = p.position;
      if (p.playing && pos != lastPos) return; // 位置在走 = 真的在出声,收工
      lastPos = pos;

      // 平台已经回到暂停态:此刻 play() 才会真的下发播放请求。
      // 补发后继续下一轮,确认是不是真起来了。
      if (!p.playing) {
        debugPrint('[player] Windows 起播确认($i):补发 play() '
            '#${currentSong?.id} state=$state');
        try {
          await _playNow(); // 内含「必要时先 pause 对齐」
        } catch (e) {
          debugPrint('[player] 补发 play 失败: $e');
        }
        continue;
      }

      // 还在装载/缓冲:位置本来就不走,继续等。
      // 这里**不要** pause —— 那会把正在进行的缓冲打断,反而更容易卡住。
      if (state == ProcessingState.loading ||
          state == ProcessingState.buffering) {
        continue;
      }

      // 核心说「在播」、状态也不是装载,但位置一动不动 —— 就是那个竞态(假在播)。
      // 给它约半秒;之后 pause+play 强制下发一次。
      if (i >= 4) {
        debugPrint('[player] Windows 疑似「假在播」→ 强制重新起播 '
            '#${currentSong?.id}');
        try {
          await _handler.pause();
          await _playNow();
        } catch (e) {
          debugPrint('[player] 强制起播失败: $e');
        }
        return;
      }
    }
  }

  /// 本地缓存的键:(音频指纹, 实际音质)
  ///
  /// 为什么不用歌曲 ID:ID 是后端的自增序号,重新扫描 / 重建库之后会变。
  /// 一变,老缓存就会被「新的同 ID 歌曲」认领 ——
  /// 表现就是缓存里明明是这首歌,播出来却是另一首的声音。
  /// 指纹是音频内容本身的身份,与 ID 怎么变都无关。
  ///
  /// 音质一起带上:同一首歌不同档位是不同文件、指纹也不同,必须分开存。
  /// 档位用 [Song.effectiveQuality] 推算 —— 和后端兜底规则一致,
  /// 保证键对应的就是后端真正给的那份文件。
  ///
  /// 返回 null 表示后端还没算出指纹:这时既不查缓存也不写缓存,直接走网络。
  MapEntry<String, String>? _cacheKeyOf(Song song) {
    final q = song.effectiveQuality(_quality);

    // 1) 首选「该档位文件自己的指纹」(列表 / 详情接口下发的 md5_128/320/flac)
    final own = song.md5OfQualityField(q);
    if (own.isNotEmpty) return MapEntry(own, q);

    // 2) 列表里没有这一档的指纹时,退回 /song/url 下发的「配对指纹」。
    //
    // 走到这里通常是:地址是现从 /song/url 取的(请求参数带 fallback),
    // 而列表数据里那一档的 md5 是空的。配对指纹同样是**内容 MD5**,
    // 且 save() 下完还会拿它再校验一遍内容 —— 万一配对错了,
    // 结果只是「这份存不下来」,不会把别的歌写进缓存。
    if (_looksLikeMd5(song.md5)) return MapEntry(song.md5, q);

    return null;
  }

  /// 是否合法指纹(32 位十六进制)。
  ///
  /// 后端没算出来时是空串;HLS / 外链等音源也可能下发别的形状,
  /// 那种不能当缓存键用(会污染文件名),一律不认。
  bool _looksLikeMd5(String s) {
    if (s.length != 32) return false;
    for (final c in s.codeUnits) {
      final isDigit = c >= 0x30 && c <= 0x39;
      final isLower = c >= 0x61 && c <= 0x66;
      final isUpper = c >= 0x41 && c <= 0x46;
      if (!isDigit && !isLower && !isUpper) return false;
    }
    return true;
  }

  /// 日志里的短指纹
  String _shortMd5(String md5) => md5.length > 8 ? md5.substring(0, 8) : md5;

  /// 后台预缓存(不阻塞起播)
  void _prefetchFor(Song song) {
    final key = _cacheKeyOf(song);
    if (key == null) {
      // 后端还没算出这首歌的音频指纹 → 不缓存。
      // 没有指纹就只能拿 ID 当键,而 ID 会变,一变就串歌。
      AppLog.add('[player] 无音频指纹,跳过缓存 #${song.id} 音质=$_quality');
      return;
    }
    // 下载地址必须和缓存键(音质)严格对应:用 urlForQuality 取该音质专用地址,
    // 不能用 playUrl(它优先返回 song.url / url320,可能和 key.value 不是同一档,
    // 导致「下的是 320、却用 md5Flac 校验」→ MD5 永远不符)。
    unawaited(AudioCache.prefetch(key.key, key.value, song.urlForQuality(key.value)));
  }

  /// 联网取播放地址;失败退回原地址(不阻塞,由上层决定能否播)
  Future<Song> _fetchUrl(Song song) async {
    // 与 _resolvePlayable 同理:连点切歌时过期的那次取流,
    // 不能再写提示、更不能再弹一次登录引导
    final token = _playToken;
    try {
      final info = await _musicRepo.getSongUrl(
        song.id,
        quality: _quality,
      );
      if (info.url.isNotEmpty) {
        AppLog.add('[player] 取流成功 #${song.id} 请求音质=$_quality '
            '实际音质=${info.actualQuality.isEmpty ? _quality : info.actualQuality} '
            '回退=${info.fallback} '
            'md5=${info.md5.isEmpty ? "(无)" : info.md5} '
            'url=${_shortUrl(info.url)}');

        // 实际档位:新后端会明确下发 actual_quality;老后端没有这个字段时,
        // 用同一套兜底规则按列表下发的分音质地址推算,保证播放页显示的是真实档位。
        final actual = info.actualQuality.isNotEmpty
            ? info.actualQuality
            : song.effectiveQuality(
                info.quality.isNotEmpty ? info.quality : _quality,
              );
        if (token == _playToken) {
          _actualQuality = actual;

          // 后端回退了音质(该歌曲没有请求音质的文件,如 128 还没转码生成)。
          // 必须提示出来,否则用户看着「标准」却在听别的档位。
          if (actual != _quality) {
            _qualityNotice = '「${_appConfig.labelOf(_quality)}」暂无音源,'
                '已用「${_appConfig.labelOf(actual)}」播放';
            _qualityNoticeActual = actual;
            notifyListeners();
          } else if (_qualityNotice != null) {
            _qualityNotice = null;
            _qualityNoticeActual = null;
            notifyListeners();
          }
        }

        return song.copyWith(
          url: info.url,
          md5: info.md5.isNotEmpty ? info.md5 : song.md5,
        );
      }
      AppLog.add('[player] 取流返回空地址 #${song.id} 音质=$_quality');
    } on ApiException catch (e) {
      // 后端开启「音频需登录才能播放」时,未登录会返回 401 并提示登录
      if (e.code == 401 || e.message.contains('登录')) {
        AppLog.add('[player] 需登录才能播放 #${song.id} 音质=$_quality: ${e.message}');
        if (token == _playToken && !_needLogin) {
          _needLogin = true;
          _errorMessage =
              e.message.isNotEmpty ? e.message : '请先登录后播放';
          // 播放页底部常驻提示(与「评论」同区域),用户可在页面内直接去登录
          _qualityLoginHint = _errorMessage;
          notifyListeners();
          // 全局弹登录引导(不依赖 PlayerPage 是否挂载)
          onRequireLogin?.call(_errorMessage!);
        }
      } else {
        // 其它失败(典型:404「该歌曲暂无可播放音源」)。
        // 以前只写日志,用户看到的就是「点了没反应」;现在明确提示并可去换音质。
        AppLog.add('[player] 取流失败 #${song.id} 音质=$_quality: $e');
        if (token == _playToken) {
          final msg = e.message.isNotEmpty ? e.message : '取流失败,请稍后重试';
          _errorMessage = msg;
          _qualityNotice = msg;
          _qualityNoticeActual = null;
          notifyListeners();
        }
      }
    } catch (e) {
      AppLog.add('[player] 取流异常 #${song.id} 音质=$_quality: $e');
      if (token == _playToken) {
        _errorMessage = '取流失败,请检查网络后重试';
        _qualityNotice = _errorMessage;
        _qualityNoticeActual = null;
        notifyListeners();
      }
    }
    return song;
  }

  /// 日志里只留域名+路径,避免把带签名的超长 query 整段写进去
  String _shortUrl(String url) {
    final i = url.indexOf('?');
    return i < 0 ? url : '${url.substring(0, i)}?…';
  }

  /// 地址里是否带着「当前登录令牌」
  ///
  /// 后端会把 token 拼进签名播放地址(`&token=xxx`)。地址里没有当前 token,
  /// 说明它是登录前签发的旧地址 —— 直接拿去播会被媒体接口当游客拦成 401。
  bool _urlCarriesCurrentToken(String url) {
    final tk = StorageService.token;
    if (tk == null || tk.isEmpty) return false;
    return url.contains('token=$tk');
  }

  /// 解析播放地址里的歌曲 id(/api/v1/media/audio?id=123&q=320&...)
  ///
  /// 解析不出来返回 null(外链等情况不参与核对)
  int? _urlSongId(String url) {
    if (url.isEmpty) return null;

    final m = RegExp(r'[?&]id=(\d+)').firstMatch(url);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  /// 上报当前这首「实际听了多少秒」
  ///
  /// 切歌 / 暂停 / 退到后台时调用:
  ///   - 只报**增量**(当前位置 - 已上报值),同一段不会被重复计算;
  ///   - 游客不报(这类成绩记在账号上,游客只有本地历史);
  ///   - 不足 5 秒不报,省掉大量无意义的短请求;
  ///   - 上报失败不动「已上报值」,下一轮会把这段一起补上。
  Future<void> flushListen() async {
    final song = currentSong;
    if (song == null || !_auth.isLoggedIn) return;

    final pos = _handler.player.position.inSeconds;
    final delta = pos - _reportedSec;
    if (delta < 5) return;

    try {
      await _musicRepo.reportListen(song.id, delta);
      _reportedSec = pos;
    } catch (_) {
      // 静默失败:下次上报会把这段时间补上
    }
  }

  Future<void> toggle() async {
    if (currentSong == null) return;
    if (_handler.player.playing) {
      await flushListen(); // 暂停前先把这段听歌时间记上
      _wantPlaying = false;
      await _handler.pause();
    } else {
      // 走 _playAsync:Windows 上会先对齐状态再下发播放请求,并做一次起播确认;
      // 直接 await _handler.play() 会踩到「核心以为在播 → 空转」那个坑。
      _wantPlaying = true;
      unawaited(_playAsync(_playToken));
    }
    notifyListeners();
  }

  /// 随机取一个**不等于** [exclude] 的下标(队列只有一首歌时返回它自己)
  ///
  /// 直接 nextInt(length) 会随到当前这首,表现就是「点了下一首还是这首歌」。
  int _randomExcept(int exclude) {
    if (_queue.length <= 1) return 0;
    final idx = Random().nextInt(_queue.length - 1);
    return idx >= exclude ? idx + 1 : idx;
  }

  /// 切到队列第 [index] 首(只改下标,不改变播放列表数据)
  Future<void> playAt(int index) async {
    if (_queue.isEmpty || index < 0 || index >= _queue.length) return;
    await _playAt(index);
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;

    int nextIndex;
    if (_mode == PlayMode.shuffle) {
      nextIndex = _randomExcept(_currentIndex);
    } else {
      nextIndex = _currentIndex + 1;
      if (nextIndex >= _queue.length) nextIndex = 0;
    }
    // 切歌只改下标、加载对应歌,不重建列表(不改变播放列表数据)
    await _playAt(nextIndex);
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;

    int prevIndex;
    if (_mode == PlayMode.shuffle) {
      prevIndex = _randomExcept(_currentIndex);
    } else {
      prevIndex = _currentIndex - 1;
      if (prevIndex < 0) prevIndex = _queue.length - 1;
    }
    await _playAt(prevIndex);
  }

  Future<void> seek(Duration position) async {
    debugPrint('[player] seek ${position.inSeconds}s '
        '(state=${_handler.player.processingState}, playing=${_handler.player.playing})');
    try {
      await _handler.seek(position);
      debugPrint('[player] seek ok pos=${_handler.player.position.inSeconds}s');
    } catch (e) {
      debugPrint('[player] seek FAILED: $e');
    }
  }

  // ==================== 定时关闭 ====================

  /// 定时关闭(单位:分钟),到点自动暂停
  void startSleepTimer(int minutes) {
    cancelSleepTimer();
    _sleepSecondsLeft = minutes * 60;
    _sleepEndOfSong = false;

    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_sleepSecondsLeft <= 1) {
        _stopAfterSleep();
      } else {
        _sleepSecondsLeft--;
        notifyListeners();
      }
    });
    notifyListeners();
  }

  /// 设为「本首歌结束后停止」
  void setSleepEndOfSong(bool value) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepSecondsLeft = 0;
    _sleepEndOfSong = value;
    notifyListeners();
  }

  /// 取消定时关闭
  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepSecondsLeft = 0;
    _sleepEndOfSong = false;
    notifyListeners();
  }

  /// 倒计时结束:暂停播放
  void _stopAfterSleep() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepSecondsLeft = 0;
    _wantPlaying = false;
    _handler.pause();
    notifyListeners();
  }

  void setMode(PlayMode mode) {
    _mode = mode;
    notifyListeners();
  }

  /// 切换播放模式(顺序→单曲→随机)
  void switchMode() {
    switch (_mode) {
      case PlayMode.sequence:
        _mode = PlayMode.listLoop;
        break;
      case PlayMode.listLoop:
        _mode = PlayMode.single;
        break;
      case PlayMode.single:
        _mode = PlayMode.shuffle;
        break;
      case PlayMode.shuffle:
        _mode = PlayMode.sequence;
        break;
    }
    notifyListeners();
  }

  void _onComplete() {
    // 时间戳防抖:播放器 completed 事件和切歌撞在一起会连跳两首,
    // 2 秒内只处理一次。
    //
    // 注意:不能用 `if (_switching) return` 来防 —— switching 一旦卡在 true
    // (起播卡住时),就会把「自动切下一首」永久拦死,表现就是「播完不切」。
    final now = DateTime.now();
    if (_lastCompleteAt != null &&
        now.difference(_lastCompleteAt!) < const Duration(seconds: 2)) {
      debugPrint('[player] onComplete 防抖忽略');
      return;
    }
    _lastCompleteAt = now;

    debugPrint('[player] onComplete mode=$_mode '
        'dur=${_handler.player.duration?.inSeconds}s '
        'pos=${_handler.player.position.inSeconds}s');

    if (_mode == PlayMode.single) {
      // 单曲循环:重新取地址后再播。
      // 直接 seek(0)+play() 会重新请求「同一个」签名地址,
      // 循环时间超过有效期(默认 24 小时)后该地址已过期 → 403 播不动。
      unawaited(_replayCurrent());
      return;
    }

    // 定时关闭:本首歌结束后停止
    if (_sleepEndOfSong) {
      _sleepEndOfSong = false;
      _wantPlaying = false;
      _handler.pause();
      notifyListeners();
      return;
    }

    // 顺序播放:放到列表最后一首就停下,不再从头循环。
    //
    // 之前这里是无条件 next(),而 next() 在最后一首会回到第一首,
    // 结果就是「没点单曲循环,播完却自己从头重播了」。
    // (用户手动点「下一首」时仍然会回到第一首,那是主动操作)
    if (_mode == PlayMode.sequence &&
        _queue.isNotEmpty &&
        _currentIndex >= _queue.length - 1) {
      debugPrint('[player] sequence finished → pause');
      _wantPlaying = false;
      _handler.pause();
      notifyListeners();
      return;
    }

    next();
  }

  /// 单曲循环重播:先刷新播放地址,再重新加载播放
  Future<void> _replayCurrent() async {
    final song = currentSong;
    if (song == null) return;

    final token = _playToken;
    final fresh = await _resolvePlayable(song);
    debugPrint('[player] replay: urlChanged=${fresh.playUrl != song.playUrl}');

    // 解析期间切了歌:这次重播作废(否则会把旧地址写进新下标,写出重复歌曲)
    if (token != _playToken) {
      debugPrint('[player] replay: 期间已切歌,放弃本次重播');
      return;
    }

    // 重播会把进度归零,已上报值也要跟着归零,否则新的一轮会被算成 0 秒
    _reportedSec = 0;
    _wantPlaying = true; // 重播的意图就是要响(Windows 起播确认会用到)

    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      _queue[_currentIndex] = fresh;
    }

    try {
      if (fresh.playUrl.isNotEmpty && fresh.playUrl != song.playUrl) {
        // 拿到新地址:重新加载,避免继续用过期地址
        debugPrint('[player] replay: reload with fresh url');
        await _handler.loadSong(fresh);
      } else {
        // 地址没变(离线等兜底情况):原地重播
        debugPrint('[player] replay: seek 0');
        await _handler.seek(Duration.zero);
      }
      await _playNow();
      debugPrint('[player] replay: play() called, playing=${_handler.player.playing}');
      // 换了源(WMF 会回到暂停态)时同样要确认真的起播了
      unawaited(_confirmPlayingOnWindows(token));
    } catch (e) {
      debugPrint('[player] replay FAILED: $e');
      // 二次兜底:尽量恢复播放
      try {
        await _handler.seek(Duration.zero);
        await _playNow();
      } catch (_) {
        // 确实无法播放时静默处理,避免影响后续操作
      }
    }
  }

  /// 播放出错处理
  ///
  /// 最常见原因:音频格式本机解码器不支持 ——
  /// 例如 24bit / 96kHz 的 FLAC,Android 原生解码器只吃 16bit,
  /// 会直接抛 MediaCodecAudioRenderer error。
  /// 这种情况下重试没用,所以重试一次后就跳过并给出提示。
  Future<void> _onPlaybackError() async {
    final song = currentSong;
    debugPrint('[player] playbackError #${song?.id} count=$_consecutiveErrors');
    AppLog.add('[player] 播放器报错 #${song?.id} 音质=$_quality '
        '第 ${_consecutiveErrors + 1} 次(多为解码器不支持该格式)');

    // 第一次:可能是网络抖动,原地重试一次
    if (_consecutiveErrors == 0) {
      _consecutiveErrors = 1;
      await _replayCurrent();
      return;
    }

    // 重试后仍失败:这首歌本机就是放不了(例如 24bit 无损 FLAC)。
    //
    // 这里选择「直接停下」:
    //   - 不弹提示(反复弹窗很烦,拖动进度条时会连续触发)
    //   - 不自动跳下一首(否则单曲循环会被莫名跳歌)
    // 用户看到播放按钮回到「播放」态,自己决定切歌或换音质即可。
    _consecutiveErrors = 0;
    _wantPlaying = false;
    debugPrint('[player] give up on #${song?.id}: pause and stay');

    try {
      await _handler.pause();
    } catch (_) {
      // 暂停失败也无需处理
    }
    notifyListeners();
  }

  // ==================== 歌词 ====================

  Future<void> _loadLyric(Song song) async {
    try {
      _lyric = song.lyric.isNotEmpty
          ? song.lyric
          : await _musicRepo.getLyric(song.id);
      _lyricLines = LyricsParser.parse(_lyric);
      notifyListeners();
    } catch (_) {
      _lyric = '';
      _lyricLines = [];
    }
  }

  // ==================== 播放上报 / 历史 ====================

  Future<void> _reportPlay(Song song) async {
    // 顺带把播放器解析出的真实时长报上去:
    // 后端只在库里为 0 时补写(否则列表页一直显示 00:00)
    final realDur = _handler.player.duration?.inSeconds ?? 0;

    await _musicRepo.reportPlay(song.id, duration: realDur);

    if (!_auth.isLoggedIn) {
      await StorageService.addLocalHistory(song.id);
    }
  }

  // ==================== 收藏(游客本地 / 登录云端) ====================

  /// 加载收藏集合
  Future<void> loadFavorites() async {
    _favoriteIds.clear();

    if (_auth.isLoggedIn) {
      try {
        final list = await _userRepo.getMyCollects(type: TargetType.song);
        _favoriteIds.addAll(list.map((e) => e.id));
      } catch (_) {
        _favoriteIds.addAll(StorageService.localFavorites);
      }
    } else {
      _favoriteIds.addAll(StorageService.localFavorites);
    }
    notifyListeners();
    // 加载完收藏集合后,同步通知栏心形图标状态
    _handler.refreshControls();
  }

  /// 切换收藏,返回切换后的状态
  Future<bool> toggleFavorite(int songId) async {
    bool result;

    if (_auth.isLoggedIn) {
      result = await _userRepo.collectSong(songId);
    } else {
      await StorageService.toggleLocalFavorite(songId);
      result = StorageService.isLocalFavorite(songId);
    }

    if (result) {
      _favoriteIds.add(songId);
    } else {
      _favoriteIds.remove(songId);
    }
    notifyListeners();
    // 通知栏收藏图标(空心/实心)同步刷新
    _handler.refreshControls();
    return result;
  }

  /// 当前歌曲的收藏状态
  bool get isCurrentFavorite {
    final song = currentSong;
    return song == null ? false : isFavorite(song.id);
  }

  Future<void> toggleFavoriteCurrent() async {
    final song = currentSong;
    if (song == null) return;
    await toggleFavorite(song.id);
  }
}
