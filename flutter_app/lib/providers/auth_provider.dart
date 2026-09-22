import 'package:flutter/foundation.dart';

import '../core/network/api_exception.dart';
import '../core/storage/storage_service.dart';
import '../data/models/user.dart';
import '../data/repositories/user_repository.dart';

/// 认证状态
///
/// 游客态:token 为空,所有公开接口照常使用
/// 登录态:token 非空,自动携带;登录瞬间把游客本地数据合并到云端
class AuthProvider extends ChangeNotifier {
  final UserRepository _repo = UserRepository();

  UserModel? _user;
  String? _token;
  bool _loading = false;
  String? _error;

  UserModel? get user => _user;
  String? get token => _token;
  bool get loading => _loading;
  String? get error => _error;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;

  /// App 启动时恢复登录态(无 token 则保持游客)
  Future<void> init() async {
    _token = StorageService.token;
    final info = StorageService.userInfo;
    if (info != null) {
      _user = UserModel.fromJson(info);
    }
    notifyListeners();

    // 已登录则静默刷新资料,失败不强制登出(避免弱网被踢)
    if (isLoggedIn) {
      await refreshInfo(silent: true);
    }
  }

  /// 登录(成功后自动合并游客数据)
  Future<void> login(String username, String password) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await _repo.login(username, password);
      await _persist(res.token, res.user);
      await _repo.syncGuestData();
      await refreshInfo(silent: true);
    } catch (e) {
      _error = _msg(e);
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 注册(成功后自动合并游客数据)
  Future<void> register(
    String username,
    String password, {
    String? nickname,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await _repo.register(username, password, nickname: nickname);
      await _persist(res.token, res.user);
      await _repo.syncGuestData();
      await refreshInfo(silent: true);
    } catch (e) {
      _error = _msg(e);
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _repo.logout();
    await StorageService.clearUser();
    _token = null;
    _user = null;
    notifyListeners();
  }

  Future<void> refreshInfo({bool silent = false}) async {
    try {
      _user = await _repo.getInfo();
      await StorageService.setUserInfo(_user!.toJson());
      if (!silent) notifyListeners();
    } catch (_) {
      // 静默失败
    }
  }

  /// 401 回调:清理本地登录态,退回游客
  void handleUnauthorized() {
    if (!isLoggedIn) return;
    _token = null;
    _user = null;
    StorageService.clearUser();
    notifyListeners();
  }

  Future<void> _persist(String newToken, UserModel newUser) async {
    _token = newToken;
    _user = newUser;
    await StorageService.setToken(newToken);
    await StorageService.setUserInfo(newUser.toJson());
    notifyListeners();
  }

  /// 友好错误提示:只取后端业务文案(如"密码错误"),不暴露错误码
  String _msg(Object e) {
    if (e is ApiException) {
      return e.message;
    }
    return '网络异常,请稍后重试';
  }
}
