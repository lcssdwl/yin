import 'dart:async';

import 'package:flutter/material.dart';

/// 屏幕**居中**的轻提示(替代底部 SnackBar)
///
/// 为什么不用 SnackBar:它贴在屏幕底部,容易被播放条 / 输入框压住,
/// 而且提示"创建失败"这种信息时,用户视线在弹窗中间,底部一闪就错过了。
///
/// 特性:
/// - 居中卡片 + 图标(成功绿勾 / 失败红叹号),淡入淡出 + 轻微缩放
/// - 走 Overlay,不拦截点击、不需要等它消失(失败停留久一点,便于看清)
void showCenterToast(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _CenterToast(
      message: message,
      error: error,
      onDone: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _CenterToast extends StatefulWidget {
  final String message;
  final bool error;
  final VoidCallback onDone;

  const _CenterToast({
    required this.message,
    required this.error,
    required this.onDone,
  });

  @override
  State<_CenterToast> createState() => _CenterToastState();
}

class _CenterToastState extends State<_CenterToast> {
  static const Duration _fade = Duration(milliseconds: 180);

  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    // 先以透明+缩小入场,下一帧再置为可见,动画才会真正跑起来
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });

    // 失败信息多留一会儿,避免没看清就消失
    _timer = Timer(
      Duration(milliseconds: widget.error ? 2600 : 1600),
      () {
        if (!mounted) return;
        setState(() => _visible = false);
        Future.delayed(_fade + const Duration(milliseconds: 40), () {
          if (mounted) widget.onDone();
        });
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color =
        widget.error ? theme.colorScheme.error : const Color(0xFF34C759);

    return Positioned.fill(
      // 只是提示,不挡住下面的操作
      child: IgnorePointer(
        child: Center(
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: _fade,
            child: AnimatedScale(
              scale: _visible ? 1 : 0.92,
              duration: _fade,
              curve: Curves.easeOutBack,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 18,
                ),
                constraints: const BoxConstraints(maxWidth: 300),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF232028) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: color.withValues(alpha: 0.30)),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.error
                          ? Icons.error_outline_rounded
                          : Icons.check_circle_rounded,
                      size: 34,
                      color: color,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
