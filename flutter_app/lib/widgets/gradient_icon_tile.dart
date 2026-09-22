import 'package:flutter/material.dart';

/// 渐变封面块(「默认收藏」这类"无封面"的歌单用它 + 居中图标)
///
/// - 亮色:整块彩色渐变,和 App 主视觉一致
/// - 深色:黑底 + 一圈彩色描边 ——
///   深色下整块亮渐变太扎眼,只留一道彩色边框(与「我的」页顶部卡片同款处理)
///
/// 尺寸由外部约束决定(SizedBox / Expanded 都行),自身不设宽高。
class GradientIconTile extends StatelessWidget {
  final IconData icon;

  /// 圆角(深色时内层会自动减去描边宽度)
  final double radius;

  final double iconSize;

  /// 描边宽度
  static const double _border = 1.2;

  const GradientIconTile({
    super.key,
    required this.icon,
    this.radius = 12,
    this.iconSize = 34,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      // 深色下外层渐变只当"描边"用,内层铺黑底盖住中间
      padding: isDark ? const EdgeInsets.all(_border) : null,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF5A7A), Color(0xFFB23A8F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Container(
        decoration: isDark
            ? BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(radius - _border),
              )
            : null,
        child: Center(child: Icon(icon, color: Colors.white, size: iconSize)),
      ),
    );
  }
}
