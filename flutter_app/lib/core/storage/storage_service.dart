import 'dart:convert';
import 'dart:math';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/constants.dart';

/// 本地存储服务
///
/// 职责:
/// 1. Token / 用户信息 / 设备ID 持久化
/// 2. 游客(免登录)数据落本地:收藏、历史、歌单
///    登录后通过 /user/sync 一次性合并到云端
class StorageService {
  StorageService._();

  static late Box<dynamic> _settings;
  static late Box<dynamic> _local;
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    await Hive.initFlutter();
    _settings = await Hive.openBox(AppConstants.boxSettings);
    _local = await Hive.openBox(AppConstants.boxLocalData);
    _prefs = await SharedPreferences.getInstance();
  }

  // ==================== 设备ID(游客身份标识) ====================

  static String get deviceId {
    String? id = _settings.get(AppConstants.keyDeviceId);
    if (id == null || id.isEmpty) {
      id = _generateDeviceId();
      _settings.put(AppConstants.keyDeviceId, id);
    }
    return id;
  }

  static String _generateDeviceId() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // ==================== Token / 用户 ====================

  static String? get token => _settings.get(AppConstants.keyToken) as String?;

  static Future<void> setToken(String? value) async {
    if (value == null || value.isEmpty) {
      await _settings.delete(AppConstants.keyToken);
    } else {
      await _settings.put(AppConstants.keyToken, value);
    }
  }

  static Map<String, dynamic>? get userInfo {
    final raw = _settings.get(AppConstants.keyUserInfo);
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw as String));
    } catch (_) {
      return null;
    }
  }

  static Future<void> setUserInfo(Map<String, dynamic>? info) async {
    if (info == null) {
      await _settings.delete(AppConstants.keyUserInfo);
    } else {
      await _settings.put(AppConstants.keyUserInfo, jsonEncode(info));
    }
  }

  static bool get isLoggedIn => (token ?? '').isNotEmpty;

  // ==================== 主题 / 音质 ====================

  static String get themeMode =>
      _prefs.getString(AppConstants.keyThemeMode) ?? 'system';

  static Future<void> setThemeMode(String mode) =>
      _prefs.setString(AppConstants.keyThemeMode, mode);

  /// 播放音质(默认「标准」128,可在播放页切换)
  static String get quality =>
      _prefs.getString(AppConstants.keyQuality) ?? '128';

  static Future<void> setQuality(String q) =>
      _prefs.setString(AppConstants.keyQuality, q);

  // ==================== 音效(均衡器) ====================

  /// 音效预设 id('off' = 原声/关闭)
  static String get audioEffect {
    try {
      return _prefs.getString(AppConstants.keyAudioEffect) ?? 'off';
    } catch (_) {
      return 'off';
    }
  }

  static Future<void> setAudioEffect(String id) =>
      _prefs.setString(AppConstants.keyAudioEffect, id);

  /// 自定义音效的 5 点增益曲线(低 → 高,dB);长度不是 5 时按全 0 处理
  static List<double> get audioEffectCurve {
    const flat = [0.0, 0.0, 0.0, 0.0, 0.0];
    try {
      final raw = _prefs.getString(AppConstants.keyAudioEffectCurve);
      if (raw == null || raw.isEmpty) return flat;
      final list = (jsonDecode(raw) as List)
          .map((e) => (e as num).toDouble())
          .toList();
      return list.length == flat.length ? list : flat;
    } catch (_) {
      return flat;
    }
  }

  static Future<void> setAudioEffectCurve(List<double> curve) =>
      _prefs.setString(AppConstants.keyAudioEffectCurve, jsonEncode(curve));

  // ==================== 游客:本地收藏 ====================

  static List<int> get localFavorites {
    final raw = _local.get(AppConstants.keyLocalFavorites);
    if (raw == null) return [];
    return List<int>.from(raw as List);
  }

  static bool isLocalFavorite(int songId) => localFavorites.contains(songId);

  static Future<void> toggleLocalFavorite(int songId) async {
    final list = localFavorites;
    if (list.contains(songId)) {
      list.remove(songId);
    } else {
      list.insert(0, songId);
    }
    await _local.put(AppConstants.keyLocalFavorites, list);
  }

  /// 覆盖式写入本地收藏(退出登录时把云端收藏快照写回本地,供离线查看)
  static Future<void> setLocalFavorites(List<int> ids) async {
    await _local.put(AppConstants.keyLocalFavorites, ids);
  }

  // ==================== 游客:本地历史 ====================

  /// 元素:{songId, playTime}
  static List<Map<String, dynamic>> get localHistory {
    final raw = _local.get(AppConstants.keyLocalHistory);
    if (raw == null) return [];
    return (raw as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Future<void> addLocalHistory(int songId) async {
    final list = localHistory;
    list.removeWhere((e) => e['songId'] == songId);
    list.insert(0, {
      'songId': songId,
      'playTime': DateTime.now().toIso8601String(),
    });
    // 最多保留 200 条
    final trimmed = list.take(200).toList();
    await _local.put(AppConstants.keyLocalHistory, trimmed);
  }

  /// 清空本地历史(「播放历史」页的「清空」按钮)
  static Future<void> clearLocalHistory() =>
      _local.delete(AppConstants.keyLocalHistory);

  // ==================== 游客:本地歌单 ====================

  /// 元素:{name, songs:[songId...], createTime}
  static List<Map<String, dynamic>> get localPlaylists {
    final raw = _local.get(AppConstants.keyLocalPlaylists);
    if (raw == null) return [];
    return (raw as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Future<void> addLocalPlaylist(String name, List<int> songs) async {
    final list = localPlaylists;
    list.insert(0, {
      'name': name,
      'songs': songs,
      'createTime': DateTime.now().toIso8601String(),
    });
    await _local.put(AppConstants.keyLocalPlaylists, list);
  }

  static Future<void> addSongToLocalPlaylist(int index, int songId) async {
    final list = localPlaylists;
    if (index < 0 || index >= list.length) return;
    final songs = List<int>.from(list[index]['songs'] as List);
    if (!songs.contains(songId)) {
      songs.add(songId);
      list[index]['songs'] = songs;
      await _local.put(AppConstants.keyLocalPlaylists, list);
    }
  }

  /// 退出登录时清理用户信息(保留游客本地数据)
  static Future<void> clearUser() async {
    await setToken(null);
    await setUserInfo(null);
  }
}
