/// 接口异常
class ApiException implements Exception {
  final int code;
  final String message;

  ApiException(this.code, this.message);

  /// 未登录 / 登录失效
  bool get isUnauthorized => code == 401;

  @override
  String toString() => 'ApiException(code: $code, message: $message)';
}
