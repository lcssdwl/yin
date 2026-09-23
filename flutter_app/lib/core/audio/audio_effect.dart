import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../storage/storage_service.dart';
import '../utils/error_text.dart';

/// 一个音效预设
class AudioEffectPreset {
  final String id;
  final String label;
  final IconData icon;

  /// 增益曲线:低频 → 高频共 5 个点(dB)。
  ///
  /// 设备实际频段数不固定(常见 5 段,也有 10 段),应用时按位置线性插值映射,
  /// 所以预设统一用 5 点表达,换设备不用改预设。
  final List<double> gains;

  /// 响度增强(dB):整体更"响"。重低音 / 深夜这类预设配合它效果更明显。
  final double loudness;

  const AudioEffectPreset({
    required this.id,
    required this.label,
    required this.icon,
    required this.gains,
    this.loudness = 0,
  });
}

/// 音效控制器(均衡器 + 响度增强)
///
/// 走 just_audio 的 Android 音频效果:
/// - `AndroidEqualizer`:多段均衡,按频段增减增益(低音 / 人声 / 高音…)
/// - `AndroidLoudnessEnhancer`:响度增强,把整体音量抬起来
///
/// 两者由 ExoPlayer 在解码后直接处理音频信号,是**真实生效**的音效,不是 UI 装饰。
///
/// 三个要注意的点:
/// 1. pipeline 只能在 `AudioPlayer` **构造时**挂载 —— just_audio 没有运行时替换
///    pipeline 的接口,所以由 [createPipeline] 在创建播放器时调用(见 MusicAudioHandler)。
/// 2. 频段表 `parameters` 要等播放器首次激活(载入音频)后才拿得到,在那之前 await
///    会一直挂着,所以这里带超时,并在每次载歌成功后重新 [apply] 一次。
/// 3. 仅 Android 支持。其它平台不把 effect 挂进 pipeline,也不调用其方法 ——
///    否则会把 Android 专用调用打到 Windows 等实现上。
class AudioEffects extends ChangeNotifier {
  AudioEffects._();

  static final AudioEffects instance = AudioEffects._();

  /// 预设清单(增益为低频 → 高频的 5 点曲线,dB)
  static const List<AudioEffectPreset> presets = [
    AudioEffectPreset(
      id: 'off',
      label: '原声',
      icon: Icons.music_note,
      gains: [0, 0, 0, 0, 0],
    ),
    AudioEffectPreset(
      id: 'pop',
      label: '流行',
      icon: Icons.star,
      gains: [-1, 2, 3, 2, -1],
    ),
    AudioEffectPreset(
      id: 'rock',
      label: '摇滚',
      icon: Icons.electric_bolt,
      gains: [4, 2, -1, 2, 4],
    ),
    AudioEffectPreset(
      id: 'jazz',
      label: '爵士',
      icon: Icons.nightlife,
      gains: [3, 2, -1, 2, 3],
    ),
    AudioEffectPreset(
      id: 'classical',
      label: '古典',
      icon: Icons.piano,
      gains: [3, 1, -1, 2, 4],
    ),
    AudioEffectPreset(
      id: 'vocal',
      label: '人声',
      icon: Icons.mic,
      gains: [-2, 1, 3, 3, 1],
    ),
    AudioEffectPreset(
      id: 'bass',
      label: '重低音',
      icon: Icons.graphic_eq,
      gains: [7, 4, 1, 0, -1],
      loudness: 4,
    ),
    AudioEffectPreset(
      id: 'night',
      label: '深夜',
      icon: Icons.nightlight_round,
      gains: [2, 1, 0, -1, -3],
      loudness: 2,
    ),
    AudioEffectPreset(
      id: 'custom',
      label: '自定义',
      icon: Icons.tune,
      gains: [0, 0, 0, 0, 0],
    ),
  ];

  /// 曲线点数(所有预设 / 自定义统一 5 点)
  static const int curvePoints = 5;

  /// 各档位在界面上的名字(与 5 点曲线一一对应)
  static const List<String> bandLabels = ['60Hz', '230Hz', '910Hz', '3.6k', '14k'];

  AndroidEqualizer? _eq;
  AndroidLoudnessEnhancer? _loud;

  List<AndroidEqualizerBand> _bands = const [];
  double _deviceMinDb = -12;
  double _deviceMaxDb = 12;

  String _presetId = 'off';
  List<double> _customCurve = const [0, 0, 0, 0, 0];

  Future<bool>? _resolving;
  bool _ready = false;
  String _status = '';

  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 频段表是否已就绪(就绪后才能调增益)
  bool get ready => _ready;

  /// 设备实际频段(仅调试 / 展示用)
  List<AndroidEqualizerBand> get bands => _bands;

  /// 状态说明(给界面做提示用,空串 = 一切正常)
  String get status => _status;

  String get presetId => _presetId;

  AudioEffectPreset get preset => presetOf(_presetId);

  /// 是否开着音效(「原声」= 关)
  bool get enabled => _presetId != 'off';

  /// 当前生效的 5 点曲线:自定义时取用户曲线,否则取预设曲线
  List<double> get activeCurve =>
      _presetId == 'custom' ? _customCurve : preset.gains;

  /// 设备支持的增益范围(界面滑块用)
  double get minGain => _deviceMinDb;
  double get maxGain => _deviceMaxDb;

  static AudioEffectPreset presetOf(String id) =>
      presets.firstWhere((p) => p.id == id, orElse: () => presets.first);

  /// 自定义曲线第 [i] 档的增益
  double customGain(int i) =>
      (i >= 0 && i < _customCurve.length) ? _customCurve[i] : 0;

  // ==================== 挂载 ====================

  /// 供播放器构造时挂载 pipeline(非 Android 返回空 pipeline,不挂任何 effect)
  AudioPipeline createPipeline() {
    if (!supported) return AudioPipeline();

    _eq = AndroidEqualizer();
    _loud = AndroidLoudnessEnhancer();
    _ready = false;
    _resolving = null;
    return AudioPipeline(androidAudioEffects: [_eq!, _loud!]);
  }

  /// 从本地恢复上次的选择(StorageService 就绪后调用)
  void loadSaved() {
    try {
      final id = StorageService.audioEffect;
      _presetId = presets.any((p) => p.id == id) ? id : 'off';
      _customCurve = StorageService.audioEffectCurve;
    } catch (_) {
      // 存储未就绪:保持默认(原声)
    }
    notifyListeners();
  }

  /// 等频段表就绪;拿不到(还没播放过 / 平台不支持)返回 false 并给出说明
  Future<bool> ensureReady() {
    if (!supported) {
      _status = '音效仅在 Android 上生效(当前平台不支持)';
      return Future.value(false);
    }

    final eq = _eq;
    if (eq == null) {
      _status = '音效尚未初始化,请播放一首歌后重试';
      return Future.value(false);
    }
    if (_ready) return Future.value(true);

    // 多个入口(开面板 / 载歌)可能同时来问,共用一个 Future 避免重复查询
    return _resolving ??= _resolve(eq);
  }

  Future<bool> _resolve(AndroidEqualizer eq) async {
    try {
      // 频段表由系统在播放器激活后给出;没激活就一直等,所以必须带超时
      final params = await eq.parameters.timeout(const Duration(seconds: 3));
      _bands = params.bands;
      _deviceMinDb = params.minDecibels;
      _deviceMaxDb = params.maxDecibels;
      _ready = _bands.isNotEmpty;
      _status = _ready ? '' : '当前设备没有可用的均衡器频段';
    } catch (_) {
      _ready = false;
      _resolving = null; // 允许下次(通常载歌之后)重试
      _status = '音效准备中,播放一首歌后即可调节';
      notifyListeners();
      return false;
    }
    notifyListeners();
    return _ready;
  }

  // ==================== 应用 ====================

  /// 把当前预设推到设备(每次载歌成功后调用;没准备好会自动跳过)
  Future<void> apply() async {
    final eq = _eq;
    final loud = _loud;
    if (!supported || eq == null || loud == null) return;

    if (!await ensureReady()) return;

    final wantOn = enabled;
    final curve = activeCurve;
    final loudDb = _presetId == 'custom' ? 0.0 : preset.loudness;

    // 先把每个频段的目标增益算好,避免循环里逐个 set 时中途异常,
    // 留下「部分频段已设成负增益、EQ 仍启用」的半成品 → 声音被压小。
    final targets = <double>[
      for (final band in _bands)
        _gainForBand(band.index, _bands.length, curve)
            .clamp(_deviceMinDb, _deviceMaxDb)
            .toDouble(),
    ];

    try {
      // 先关掉效果再调参数:这样即使后面任何一步抛异常,
      // EQ / 响度都停在「已关闭」,不会把播放声音压小。
      await eq.setEnabled(false);
      await loud.setEnabled(false);

      for (var i = 0; i < _bands.length; i++) {
        await _bands[i].setGain(targets[i]);
      }
      await eq.setEnabled(wantOn);
      await loud.setTargetGain(wantOn ? loudDb : 0);
      await loud.setEnabled(wantOn && loudDb > 0);
      _status = '';
    } catch (e) {
      // 面板上会展示这句话,所以只给用户看得懂的文案(细节去日志里找)
      _status = '音效应用失败:${friendlyError(e, fallback: '已自动关闭音效,声音恢复正常')}';
      debugPrint('[audio] apply effect failed: $e');
      // 兜底:确保 EQ / 响度已关闭,声音回到正常音量
      try {
        await eq.setEnabled(false);
        await loud.setEnabled(false);
      } catch (_) {}
    }
    notifyListeners();
  }

  /// 选择预设
  Future<void> setPreset(String id) async {
    if (!presets.any((p) => p.id == id)) return;
    _presetId = id;
    notifyListeners();

    try {
      await StorageService.setAudioEffect(id);
    } catch (_) {}

    await apply();
  }

  /// 调整自定义曲线的第 [index] 档(dB)
  Future<void> setCustomGain(int index, double value) async {
    if (index < 0 || index >= curvePoints) return;

    final next = List<double>.from(
      _customCurve.length == curvePoints
          ? _customCurve
          : List<double>.filled(curvePoints, 0),
    );
    next[index] = value;
    _customCurve = next;
    notifyListeners();

    try {
      await StorageService.setAudioEffectCurve(next);
    } catch (_) {}

    // 只有当前就是「自定义」时才实时推给设备
    if (_presetId == 'custom') await apply();
  }

  /// 自定义曲线全部归零
  Future<void> resetCustom() async {
    _customCurve = List<double>.filled(curvePoints, 0);
    notifyListeners();

    try {
      await StorageService.setAudioEffectCurve(_customCurve);
    } catch (_) {}

    if (_presetId == 'custom') await apply();
  }

  /// 把 5 点曲线按位置线性插值映射到设备实际频段
  double _gainForBand(int index, int count, List<double> curve) {
    if (curve.isEmpty) return 0;
    if (count <= 1) return curve[curve.length ~/ 2];

    final pos = index / (count - 1) * (curve.length - 1);
    final lo = pos.floor();
    final hi = pos.ceil();
    if (lo == hi) return curve[lo.clamp(0, curve.length - 1)];

    final t = pos - lo;
    return curve[lo] * (1 - t) + curve[hi] * t;
  }
}
