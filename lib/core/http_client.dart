/// 网络请求层（对应 MP utils/request.js）
///
/// 封装 dio，实现与 SpiritedWeb HttpRequest.js / MP request.js 完全一致的
/// 加密/签名/解密逻辑：
///
///   GET:          X-IDE = md5(url)
///   POST form:    X-IDE = md5(values)，values 以 "" 开头拼接所有参数值
///   POST json:    X-IDE = md5(values)，values 以 "" 开头拼接所有参数值
///   X-APPL：防重放盐值；Authorization：登录 token；device: mobile
///
/// 响应 ReturnT {code, data, message}：
///   200~399 成功，data 为 v2 AES 加密串，解密后回填
///   100 幂等拦截（1 秒内重复请求）；400/500 业务错误 toast
///   401 登录过期：清 token 弹窗跳登录页（游客态静默）
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import 'crypto_util.dart';
import 'store.dart';

/// 后端 ReturnT 响应结构
class ApiResult {
  ApiResult({required this.code, this.data, this.message, this.reason});

  final int code;
  dynamic data;
  String? message;
  String? reason;

  bool get ok => code >= 200 && code < 400;
}

/// 业务异常（对应 MP request.js buildError：附带后端 reason 机器码）
class ApiException implements Exception {
  ApiException(this.message, {this.code, this.reason, this.data});

  final String message;
  final int? code;
  final String? reason;
  final dynamic data;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  /// 全局 Navigator Key（Toast/Loading/401 跳转用）
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static BuildContext? get _ctx => navigatorKey.currentContext;

  final Dio _dio = Dio(BaseOptions(
    baseUrl: AppConfig.baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    // 状态码全放行，按 MP 逻辑自行判定（>=500 / 404 → 服务维护中）
    validateStatus: (status) => true,
  ));

  /// 表单编码（保持插入序，与 wx.request 的 urlencoded 编码一致）
  static String encodeForm(Map<String, dynamic> data) {
    final buf = StringBuffer();
    for (final e in data.entries) {
      if (buf.isNotEmpty) buf.write('&');
      buf.write(Uri.encodeComponent(e.key));
      buf.write('=');
      buf.write(Uri.encodeComponent(e.value == null ? '' : _formValue(e.value!)));
    }
    return buf.toString();
  }

  static String _formValue(dynamic v) {
    if (v is bool) return v ? 'true' : 'false';
    if (v is double && v == v.truncateToDouble()) return v.truncate().toString();
    return v.toString();
  }

  bool _isRedirecting = false;

  // ===================== 对外请求方法 =====================

  /// GET 请求：X-IDE = md5(完整 url)
  Future<ApiResult> get(String path,
      {bool showLoading = false, bool silent = false}) {
    final url = AppConfig.baseUrl + path;
    return _doRequest(
      'GET',
      url,
      null,
      CryptoUtil.md5Hash(url),
      showLoading: showLoading,
      silent: silent,
    );
  }

  /// POST 表单（application/x-www-form-urlencoded）
  Future<ApiResult> postForm(String path, Map<String, dynamic>? data,
      {bool showLoading = true, bool silent = false}) {
    data = data ?? {};
    return _doRequest(
      'POST',
      AppConfig.baseUrl + path,
      encodeForm(data),
      CryptoUtil.md5Hash(CryptoUtil.buildIdeValues(data)),
      isJson: false,
      showLoading: showLoading,
      silent: silent,
    );
  }

  /// POST JSON（application/json）
  Future<ApiResult> postJson(String path, Map<String, dynamic>? data,
      {bool showLoading = true, bool silent = false}) {
    data = data ?? {};
    return _doRequest(
      'POST',
      AppConfig.baseUrl + path,
      jsonEncode(data),
      CryptoUtil.md5Hash(CryptoUtil.buildIdeValues(data)),
      isJson: true,
      showLoading: showLoading,
      silent: silent,
    );
  }

  /// POST 表单（二进制流响应），用于文件下载
  /// 返回 (字节流, contentType)
  Future<(Uint8List, String)> postFormBuffer(String path, Map<String, dynamic> data,
      {bool showLoading = true}) async {
    final url = AppConfig.baseUrl + path;
    final ide = CryptoUtil.md5Hash(CryptoUtil.buildIdeValues(data));

    if (showLoading) LoadingManager.show('下载中...');
    try {
      final resp = await _dio.post<Object>(
        url,
        data: encodeForm(data),
        options: Options(
          contentType: 'application/x-www-form-urlencoded',
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(minutes: 10),
          headers: _headers(ide),
        ),
      );
      if (showLoading) LoadingManager.hide();

      final contentType = resp.headers.value('content-type') ?? '';
      if (resp.statusCode != 200 || contentType.contains('json')) {
        var msg = '下载失败';
        try {
          final bytes = resp.data as List<int>;
          final str = utf8.decode(bytes.take(2048).toList(), allowMalformed: true);
          final parsed = jsonDecode(str);
          if (parsed is Map && parsed['message'] != null) {
            msg = parsed['message'].toString();
          }
        } catch (_) {}
        Toast.show(msg);
        throw ApiException(msg);
      }
      return (resp.data as Uint8List, contentType);
    } catch (e) {
      if (showLoading) LoadingManager.hide();
      if (e is ApiException) rethrow;
      Toast.show('下载失败，请检查网络');
      throw ApiException('下载失败');
    }
  }

  /// 上传文件（multipart，对应 MP request.uploadFile）
  Future<ApiResult> uploadFile(String path, String filePath, String name,
      {Map<String, dynamic>? formData}) async {
    final url = AppConfig.baseUrl + path;
    final ide = CryptoUtil.md5Hash(url);

    if (formData == null || formData.isEmpty) {
      LoadingManager.show('上传中...');
    }
    try {
      final form = FormData.fromMap({
        name: await MultipartFile.fromFile(filePath),
        ...(formData ?? const {}),
      });
      final resp = await _dio.post<Object>(
        url,
        data: form,
        options: Options(headers: _headers(ide)),
      );
      LoadingManager.hide();

      final result = _parseResponseText(resp.data);
      if (result == null) throw ApiException('解析响应失败');
      if (result.ok) {
        result.data = _decryptIfNeeded(result.data);
        return result;
      }
      Toast.show(result.message ?? '未知错误');
      throw ApiException(result.message ?? '未知错误',
          code: result.code, reason: result.reason);
    } catch (e) {
      LoadingManager.hide();
      if (e is ApiException) rethrow;
      Toast.show('上传失败');
      throw ApiException('上传失败');
    }
  }

  // ===================== 内部实现 =====================

  Map<String, dynamic> _headers(String ideMd5) {
    final token = Store.getToken();
    return {
      if (token.isNotEmpty) 'Authorization': token,
      'X-APPL': CryptoUtil.generateSalt(),
      'X-IDE': ideMd5,
      'device': 'mobile',
    };
  }

  Future<ApiResult> _doRequest(
    String method,
    String url,
    Object? body,
    String ideMd5, {
    bool isJson = false,
    bool showLoading = false,
    bool silent = false,
  }) async {
    if (showLoading) LoadingManager.show('加载中...');
    try {
      Response<Object> resp;
      if (method == 'GET') {
        resp = await _dio.get<Object>(
          url,
          options: Options(headers: _headers(ideMd5)),
        );
      } else {
        resp = await _dio.post<Object>(
          url,
          data: body,
          options: Options(
            contentType: isJson ? 'application/json' : 'application/x-www-form-urlencoded',
            headers: _headers(ideMd5),
          ),
        );
      }
      if (showLoading) LoadingManager.hide();
      return _handleBusiness(resp, silent: silent);
    } on DioException catch (e) {
      if (showLoading) LoadingManager.hide();
      final msg = e.type == DioExceptionType.receiveTimeout ||
              e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.connectionError
          ? '请求超时，请检查网络'
          : '网络连接异常';
      if (!silent) Toast.show(msg);
      throw ApiException(e.message ?? '网络异常');
    } catch (e) {
      if (showLoading) LoadingManager.hide();
      if (e is ApiException) rethrow;
      if (!silent) Toast.show('网络连接异常');
      throw ApiException('网络异常');
    }
  }

  /// 业务响应处理（对应 MP doRequest success 回调）
  ApiResult _handleBusiness(Response<Object> resp, {bool silent = false}) {
    // HTTP 状态码检查
    if ((resp.statusCode ?? 0) >= 500 || resp.statusCode == 404) {
      Toast.show('服务维护中，请稍后重试');
      throw ApiException('服务维护中', code: resp.statusCode);
    }

    final dynamic raw = resp.data;
    if (raw is! Map) {
      Toast.show('服务异常，请稍后重试');
      throw ApiException('服务异常');
    }

    final result = ApiResult(
      code: (raw['code'] as num?)?.toInt() ?? 0,
      data: raw['data'],
      message: raw['message']?.toString(),
      reason: raw['reason']?.toString(),
    );

    // code = 100：网关幂等拦截（1 秒内重复请求），静默失败
    if (result.code == 100) {
      throw ApiException('100', code: 100);
    }

    // code 200~399：成功，解密 data
    if (result.code >= 200 && result.code < 400) {
      if (result.data != null && result.data.toString().isNotEmpty) {
        result.data = _decryptIfNeeded(result.data);
      }
      return result;
    }

    // code = 400 参数错误
    if (result.code == 400) {
      if (!silent) Toast.show(result.message ?? '参数错误');
      throw _bizError(result);
    }

    // code = 401 登录过期
    if (result.code == 401) {
      _handleUnauthorized();
      throw ApiException('登录已过期，请重新登录', code: 401);
    }

    if (!silent) Toast.show(result.message ?? '未知错误');
    throw _bizError(result);
  }

  ApiException _bizError(ApiResult result) {
    return ApiException(
      result.message ?? '未知错误',
      code: result.code,
      reason: result.reason,
      data: result.data,
    );
  }

  dynamic _decryptIfNeeded(dynamic data) {
    if (data is String && data.isNotEmpty) {
      try {
        return CryptoUtil.decryptData(data);
      } catch (_) {
        return data;
      }
    }
    return data;
  }

  ApiResult? _parseResponseText(dynamic text) {
    try {
      final raw = jsonDecode(text.toString());
      if (raw is! Map) return null;
      return ApiResult(
        code: (raw['code'] as num?)?.toInt() ?? 0,
        data: raw['data'],
        message: raw['message']?.toString(),
        reason: raw['reason']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 401 处理（对应 MP handleUnauthorized）
  ///
  /// 游客态发出的请求（本地本就无 token）收到 401：静默失败，
  /// 不弹窗、不跳转登录页，由页面自行渲染空态。
  void _handleUnauthorized() {
    final token = Store.getToken();
    if (token.isEmpty) return;

    Store.clear();
    Store.tokenExpired = true;
    if (_isRedirecting) return;
    _isRedirecting = true;

    final ctx = _ctx;
    if (ctx == null) {
      _isRedirecting = false;
      return;
    }
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('登录已过期，请重新登录'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              _isRedirecting = false;
              navigatorKey.currentState
                  ?.pushNamedAndRemoveUntil('/login', (route) => false);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

// ===================== 全局 Loading / Toast =====================

/// 全局 Loading 管理器（对应 wx.showLoading / wx.hideLoading）
///
/// 同一时刻仅一个 loading，新 show 先移除旧遮罩。
class LoadingManager {
  LoadingManager._();

  static OverlayEntry? _entry;

  static void show([String title = '加载中...']) {
    hide();
    final ctx = ApiClient.navigatorKey.currentContext;
    if (ctx == null) return;
    _entry = OverlayEntry(
      builder: (_) => _LoadingMask(title: title),
    );
    Overlay.of(ctx, rootOverlay: true).insert(_entry!);
  }

  static void hide() {
    _entry?.remove();
    _entry = null;
  }
}

class _LoadingMask extends StatelessWidget {
  const _LoadingMask({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: const Color(0x4D16181D),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(minWidth: 120),
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
            decoration: BoxDecoration(
              color: const Color(0xFF16181D),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    strokeCap: StrokeCap.round,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 全局 Toast（对应 wx.showToast icon:none）
class Toast {
  Toast._();

  static void show(String? msg, {int seconds = 2}) {
    if (msg == null || msg.isEmpty) return;
    final ctx = ApiClient.navigatorKey.currentContext;
    if (ctx == null) return;
    final entry = OverlayEntry(
      builder: (_) => _ToastWidget(message: msg, seconds: seconds),
    );
    Overlay.of(ctx, rootOverlay: true).insert(entry);
    Future.delayed(Duration(seconds: seconds), () => entry.remove());
  }
}

class _ToastWidget extends StatelessWidget {
  const _ToastWidget({required this.message, required this.seconds});

  final String message;
  final int seconds;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 132,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            builder: (_, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFF16181D),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: Colors.white,
                  decoration: TextDecoration.none,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
