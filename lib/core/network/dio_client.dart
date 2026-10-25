import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'app_user_agent.dart';
import 'ios_friendly_http.dart';

final _logger = Logger(printer: PrettyPrinter(methodCount: 0));

/// 让请求更像浏览器：补齐 Origin / Referer / Accept-Language。
/// 某些 CDN / WAF（如阿里云 ESA 的 Bot 管理）会对缺少这些头的非浏览器请求
/// 直接返回 400 或拦截页，而浏览器则正常。补上这些头可显著降低被误拦的概率。
class BrowserLikeHeadersInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final uri = options.uri;
    if (uri.hasAuthority) {
      final origin = '${uri.scheme}://${uri.authority}';
      options.headers.putIfAbsent(
        'Accept-Language',
        () => 'zh-CN,zh;q=0.9,en;q=0.8',
      );
      if (options.method != 'GET' && options.method != 'HEAD') {
        options.headers.putIfAbsent('Origin', () => origin);
        options.headers.putIfAbsent('Referer', () => '$origin/');
      }
    }
    handler.next(options);
  }
}

class DioClient {
  static DioClient? _instance;
  late final Dio dio;
  String _baseUrl = '';

  /// 全局 Cookie 存储：让 App 像浏览器一样在请求间保留/回传 Cookie。
  /// 反向代理（如阿里云 ESA 的 acw_tc 反爬 Cookie）在缺少 Cookie 时可能拦截 POST。
  static final CookieJar cookieJar = CookieJar();

  DioClient._() {
    dio = Dio(
      BaseOptions(
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 15),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          ...AppUserAgent.defaultHeaders,
        },
      ),
    );
    // 修复 iOS 在双栈域名下卡死在 IPv6 的问题（优先 IPv4 并行竞速）。
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => createIosFriendlyHttpClient(),
    );

    // 像浏览器一样保存并回传 Cookie（兼容反代/CDN 的反爬 Cookie）。
    dio.interceptors.add(CookieManager(cookieJar));
    dio.interceptors.add(BrowserLikeHeadersInterceptor());

    if (kDebugMode) {
      dio.interceptors.add(
        LogInterceptor(
          request: false,
          requestHeader: false,
          requestBody: false,
          responseHeader: false,
          responseBody: false,
          logPrint: (obj) => _logger.d(obj),
        ),
      );
    }
  }

  static DioClient get instance {
    _instance ??= DioClient._();
    return _instance!;
  }

  String get baseUrl => _baseUrl;

  void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    dio.options.baseUrl = _baseUrl;
    dio.options.headers.addAll(AppUserAgent.defaultHeaders);
  }

  Dio get rawDio {
    final d = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
        headers: {'Accept': 'application/json', ...AppUserAgent.defaultHeaders},
      ),
    );
    d.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => createIosFriendlyHttpClient(),
    );
    d.interceptors.add(CookieManager(cookieJar));
    d.interceptors.add(BrowserLikeHeadersInterceptor());
    return d;
  }
}
