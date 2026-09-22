import 'dart:convert';

import 'package:dio/dio.dart';

import '../../config/api_config.dart';
import '../storage/storage_service.dart';
import '../utils/crypto_util.dart';
import 'api_exception.dart';

typedef UnauthorizedCallback = void Function();

/// 网络请求客户端
///
/// 统一处理:
/// - 自动携带 Token(无 Token 则不加,后端视为游客)
/// - 始终携带 X-Device-Id
/// - 统一解包 {code, msg, data},非 200 抛 ApiException
/// - 401 回调通知上层清理登录态
class DioClient {
  DioClient._();

  static final DioClient instance = DioClient._();

  late Dio dio;

  /// 401 回调(由 AuthProvider 注入)
  UnauthorizedCallback? onUnauthorized;

  void init() {
    dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
        sendTimeout: ApiConfig.sendTimeout,
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.json,
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = StorageService.token;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          options.headers['X-Device-Id'] = StorageService.deviceId;
          options.headers['Accept'] = 'application/json';
          handler.next(options);
        },
        onError: (error, handler) {
          handler.next(error);
        },
      ),
    );

    // 调试日志(发布时可移除)
    dio.interceptors.add(
      LogInterceptor(requestBody: true, responseBody: false),
    );
  }

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    // 请求参数统一加密:query → enc 字段(空参数也加密,后端强制要求)
    final q = {
      'enc': await CryptoUtil.encryptBase64(jsonEncode(query ?? <String, dynamic>{})),
    };
    final res = await dio.get(path, queryParameters: q);
    return await _unwrap(res);
  }

  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? query,
  }) async {
    // 请求参数统一加密:data → enc 字段(空参数也加密,后端强制要求)
    final d = {
      'enc': await CryptoUtil.encryptBase64(jsonEncode(data ?? <String, dynamic>{})),
    };
    final res = await dio.post(path, data: d, queryParameters: query);
    return await _unwrap(res);
  }

  Future<dynamic> put(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    final d = {
      'enc': await CryptoUtil.encryptBase64(jsonEncode(data ?? <String, dynamic>{})),
    };
    final res = await dio.put(path, data: d);
    return await _unwrap(res);
  }

  Future<dynamic> delete(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    final d = {
      'enc': await CryptoUtil.encryptBase64(jsonEncode(data ?? <String, dynamic>{})),
    };
    final res = await dio.delete(path, data: d);
    return await _unwrap(res);
  }

  /// 解包后端统一响应(data 为后端加密串,这里解密后返回)
  Future<dynamic> _unwrap(Response res) async {
    final body = res.data;

    if (body is Map<String, dynamic>) {
      final code = body['code'] is int
          ? body['code'] as int
          : int.tryParse('${body['code']}') ?? -1;

      if (code == 200) {
        return await _decryptData(body['data'], body['enc']);
      }

      if (code == 401) {
        onUnauthorized?.call();
      }

      throw ApiException(code, (body['msg'] ?? '请求失败').toString());
    }

    throw ApiException(-1, '响应格式错误');
  }

  /// 解密后端加密的 data 字段(enc=1 时为 base64(iv + 密文))
  Future<dynamic> _decryptData(dynamic data, dynamic enc) async {
    if (enc != 1 || data == null || data is! String) return data;
    try {
      final plain = await CryptoUtil.decryptBase64(data);
      return jsonDecode(plain);
    } catch (_) {
      // 解密失败(密钥不一致 / 非加密响应)原样返回,不阻断业务
      return data;
    }
  }
}
