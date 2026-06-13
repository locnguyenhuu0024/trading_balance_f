import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'okx_interceptor.dart';
import 'package:flutter/foundation.dart';

/// Khởi tạo Singleton cho Dio Client bằng Riverpod
final dioProvider = Provider<Dio>((ref) {
  final okxInterceptor = ref.watch(okxInterceptorProvider);

  final dio = Dio(BaseOptions(
    baseUrl: kIsWeb ? '' : 'https://www.okx.com', // Cấu hình Base URL
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'Content-Type': 'application/json',
    },
  ));

  // Gắn OkxInterceptor để xử lý API Keys
  dio.interceptors.add(okxInterceptor);

  // Gắn LogInterceptor để dễ debug trong môi trường phát triển (Terminal)
  dio.interceptors.add(LogInterceptor(
    request: true,
    requestHeader: true,
    requestBody: true,
    responseHeader: false,
    responseBody: true,
    error: true,
  ));

  return dio;
});