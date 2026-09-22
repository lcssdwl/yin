import 'package:flutter/material.dart';

/// 主题配置
class AppTheme {
  AppTheme._();

  /// 主色(亮紫罗兰)
  static const Color primary = Color(0xFF7C4DFF);

  /// 辅色(粉红)
  static const Color accent = Color(0xFFFF6B9D);

  /// 暖橙
  static const Color warm = Color(0xFFFFA94D);

  /// 主渐变(紫 → 粉 → 橙,生动多彩)
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, accent, warm],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// 迷你播放器专用渐变(菊 → 粉 → 紫,与主渐变反序)
  static const LinearGradient miniGradient = LinearGradient(
    colors: [warm, accent, primary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// 多彩色板(序号 / 标签 / 图标轮换用)
  static const List<Color> palette = [
    Color(0xFFFF6B6B), // 红
    Color(0xFFFF922B), // 橙
    Color(0xFFFFC53D), // 黄
    Color(0xFF51CF66), // 绿
    Color(0xFF4DABF7), // 蓝
    Color(0xFF9775FA), // 紫
    Color(0xFFF06595), // 粉
  ];

  /// 按下标取一个多彩色(循环)
  static Color paletteAt(int index) => palette[index % palette.length];

  /// 圆角
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 20.0;

  /// 间距
  static const double gapSm = 8.0;
  static const double gapMd = 16.0;
  static const double gapLg = 24.0;

  /// 表单输入框统一样式(登录 / 注册 / 修改密码等页面复用)
  ///
  /// 比默认的 `OutlineInputBorder()` 圆润:圆角 + 浅底 + 细描边,
  /// 聚焦时描边转主色、图标跟着变色,错误态用红色描边。
  /// 圆角与全局 [inputDecorationTheme] 的 12 保持同一档(略大一点更松弛)。
  static InputDecoration inputDecoration(
    ThemeData theme, {
    required String label,
    required IconData icon,
    Widget? suffixIcon,
    String? hint,
    String? helper,
  }) {
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(14);

    OutlineInputBorder line(Color color, double width) => OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      prefixIcon: Icon(icon, size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: theme.brightness == Brightness.dark
          ? const Color(0xFF1E1E1E)
          : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      // 图标颜色跟随状态:平常弱化,聚焦/出错时提亮
      prefixIconColor: scheme.onSurfaceVariant,
      suffixIconColor: scheme.onSurfaceVariant,

      border: line(scheme.outlineVariant, 1),
      enabledBorder: line(scheme.outlineVariant, 1),
      focusedBorder: line(scheme.primary, 1.6),
      errorBorder: line(scheme.error, 1),
      focusedErrorBorder: line(scheme.error, 1.6),

      labelStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
      floatingLabelStyle: TextStyle(color: scheme.primary, fontSize: 13),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
      helperStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
      errorStyle: const TextStyle(fontSize: 12),
    );
  }

  static ThemeData light() {
    final base = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    );
    return _build(base, Brightness.light);
  }

  static ThemeData dark() {
    final base = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
    );
    return _build(base, Brightness.dark);
  }

  static ThemeData _build(ColorScheme scheme, Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF14121A) : const Color(0xFFF7F4FF),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor:
            isDark ? const Color(0xFF14121A) : const Color(0xFFF7F4FF),
        foregroundColor: isDark ? Colors.white : const Color(0xFF1A1A1A),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : const Color(0xFF1A1A1A),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        selectedItemColor: primary,
        unselectedItemColor: isDark ? Colors.white54 : Colors.grey,
        type: BottomNavigationBarType.fixed,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: isDark ? Colors.white24 : Colors.black12,
        thumbColor: primary,
        trackHeight: 3,
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? Colors.white12 : Colors.black12,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
    );
  }
}
