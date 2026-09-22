import 'package:dio/dio.dart';

import '../network/api_exception.dart';

/// 把异常转成**给用户看**的一句话
///
/// 直接把异常对象拼进文案(如 `'创建失败:$e'`)会把
/// `ApiException(code: 400, message: xxx)` 这种开发者视角的内容怼到用户脸上,
/// 严重时只剩一个类名。这里只取后端给的业务 message,网络类错误映射成人话。
///
/// 需要完整异常细节的场合(排查)请写 AppLog / debugPrint,不要用这个函数。
String friendlyError(Object e, {String fallback = '操作失败,请稍后重试'}) {
  if (e is ApiException) {
    final msg = e.message.trim();
    return msg.isEmpty ? fallback : msg;
  }

  if (e is DioException) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return '网络超时,请稍后重试';
      case DioExceptionType.connectionError:
        return '连不上服务器,请检查网络';
      case DioExceptionType.badResponse:
      case DioExceptionType.badCertificate:
        return '服务异常,请稍后重试';
      case DioExceptionType.cancel:
        return '请求已取消';
      case DioExceptionType.unknown:
        return '网络异常,请检查网络后重试';
    }
  }

  return fallback;
}
