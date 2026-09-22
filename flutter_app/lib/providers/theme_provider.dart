import 'package:flutter/material.dart';

import '../core/storage/storage_service.dart';

/// 主题模式(系统 / 浅色 / 深色)
class ThemeProvider extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  Future<void> load() async {
    final value = StorageService.themeMode;
    _mode = value == 'light'
        ? ThemeMode.light
        : (value == 'dark' ? ThemeMode.dark : ThemeMode.system);
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    await StorageService.setThemeMode(
      mode == ThemeMode.light
          ? 'light'
          : (mode == ThemeMode.dark ? 'dark' : 'system'),
    );
  }
}
