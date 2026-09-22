import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../core/audio/audio_effect.dart';

/// 音效面板(均衡器预设 + 5 段自定义)
///
/// 预设直接作用到播放中的音频(Android 均衡器 + 响度增强),不是只改 UI。
void showAudioEffectSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _AudioEffectSheet(),
  );
}

class _AudioEffectSheet extends StatefulWidget {
  const _AudioEffectSheet();

  @override
  State<_AudioEffectSheet> createState() => _AudioEffectSheetState();
}

class _AudioEffectSheetState extends State<_AudioEffectSheet> {
  final AudioEffects _fx = AudioEffects.instance;

  @override
  void initState() {
    super.initState();
    // 频段表要等播放器激活后才拿得到;拿不到会自己超时并给出提示,不会卡住面板
    _fx.addListener(_onChanged);
    _fx.ensureReady();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _fx.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.of(context).size.height * 0.78;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(theme),
              const SizedBox(height: 14),

              if (!_fx.supported)
                _notice(theme, '音效仅在 Android 上生效,当前设备不支持。')
              else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      AudioEffects.presets.map(_presetPill).toList(growable: false),
                ),
                if (_fx.status.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _notice(theme, _fx.status),
                ],
                if (_fx.presetId == 'custom') ...[
                  const SizedBox(height: 6),
                  _customSection(theme),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ==================== 头部 ====================

  Widget _header(ThemeData theme) {
    final color = theme.colorScheme.primary;

    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppTheme.primaryGradient,
          ),
          child: const Icon(Icons.graphic_eq, size: 17, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Text(
          '音效',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const Spacer(),
        Text(
          _fx.enabled ? _fx.preset.label : '未开启',
          style: TextStyle(
            fontSize: 12,
            fontWeight: _fx.enabled ? FontWeight.w600 : FontWeight.normal,
            color: _fx.enabled ? color : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// 说明条(平台不支持 / 准备中 / 应用失败共用)
  Widget _notice(ThemeData theme, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 预设 ====================

  Widget _presetPill(AudioEffectPreset p) {
    final theme = Theme.of(context);
    final active = _fx.presetId == p.id;
    final color = theme.colorScheme.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _fx.setPreset(p.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: active
              ? color.withValues(alpha: 0.16)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? color : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              p.icon,
              size: 16,
              color: active ? color : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              p.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                color: active ? color : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 自定义 5 段 ====================

  Widget _customSection(ThemeData theme) {
    final min = _sliderMin;
    final max = _sliderMax;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '自定义均衡',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: _fx.ready ? () => _fx.resetCustom() : null,
              child: const Text('全部归零'),
            ),
          ],
        ),
        for (var i = 0; i < AudioEffects.curvePoints; i++)
          _bandRow(theme, i, min, max),
      ],
    );
  }

  Widget _bandRow(ThemeData theme, int i, double min, double max) {
    final value = _fx.customGain(i).clamp(min, max).toDouble();
    // 0.5dB 一档,拖起来更细腻
    final divisions = ((max - min) * 2).round().clamp(4, 96);

    return Row(
      children: [
        SizedBox(
          width: 46,
          child: Text(
            AudioEffects.bandLabels[i],
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: _dbText(value),
            onChanged: _fx.ready ? (v) => _fx.setCustomGain(i, v) : null,
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            _dbText(value),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  /// 滑块范围:取设备实际范围,但限制在 ±15dB 内(个别 ROM 会报 ±20,太夸张)
  double get _sliderMin => _fx.minGain.clamp(-15.0, -3.0).toDouble();
  double get _sliderMax => _fx.maxGain.clamp(3.0, 15.0).toDouble();

  String _dbText(double v) =>
      '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}dB';
}
