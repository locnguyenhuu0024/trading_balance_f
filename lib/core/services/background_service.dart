// File Name: background_service.dart
// File Path: lib/core/services/background_service.dart
// Note: Quản lý Foreground Service và Local Notifications

import 'dart:async';
import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter/foundation.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import '../security/secure_storage_helper.dart';
import '../network/okx_interceptor.dart';
import '../../features/portfolio/data/okx_balance_model.dart';

const notificationChannelId = 'okx_tracker_channel';
const notificationId = 888;

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    notificationChannelId,
    'OKX Tracker Service',
    description: 'Thông báo hiển thị số dư OKX chạy nền',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
      notificationChannelId: notificationChannelId,
      initialNotificationTitle: 'OKX Tracker',
      initialNotificationContent: 'Đang tải dữ liệu số dư...',
      foregroundServiceNotificationId: notificationId,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
    ),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  final secureStorageHelper = SecureStorageHelper(storage);
  final dio = Dio(BaseOptions(baseUrl: kIsWeb ? '' : 'https://www.okx.com'));
  dio.interceptors.add(OkxInterceptor(secureStorageHelper));

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Chạy định kỳ mỗi 1 giây (Lưu ý: Có thể dính Rate Limit của OKX)
  Timer.periodic(const Duration(seconds: 1), (timer) async {
    try {
      final apiKey = await secureStorageHelper.getOkxApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: 'OKX Tracker',
            content: 'Vui lòng cài đặt API Key trong ứng dụng.',
          );
        }
        return;
      }

      final response = await dio.get('/api/v5/account/balance', options: Options(extra: {'requiresAuth': true}));
      final balanceResponse = OkxBalanceResponse.fromJson(response.data);

      if (balanceResponse.code == '0' && balanceResponse.data.isNotEmpty) {
        final accountData = balanceResponse.data.first;

        double dynamicTotalEquity = 0.0;
        double totalUnrealizedPnl = 0.0;

        for (var coin in accountData.details) {
          final double eqUsd = double.tryParse(coin.eqUsd) ?? 0.0;
          final double upl = double.tryParse(coin.upl) ?? 0.0;

          dynamicTotalEquity += eqUsd;
          totalUnrealizedPnl += upl;
        }

        // Tạo giao diện trực quan bằng Emoji màu sắc
        final pnlSign = totalUnrealizedPnl >= 0 ? '+' : '-';
        final pnlEmoji = totalUnrealizedPnl >= 0 ? '🟢' : '🔴';

        // Dùng .abs() để lấy giá trị tuyệt đối, tránh bị lỗi in ra hai dấu trừ (--$10)
        final pnlFormatted = NumberFormat("#,##0.00", "en_US").format(totalUnrealizedPnl.abs());
        final equityFormatted = NumberFormat("#,##0.00", "en_US").format(dynamicTotalEquity);

        final title = 'Tổng: \$$equityFormatted';
        final content = 'Lãi/Lỗ: $pnlEmoji $pnlSign\$$pnlFormatted';

        // Dùng API chuyên dụng của Android Service để cập nhật thông báo an toàn
        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: title,
            content: content,
          );
        }
      } else {
        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: 'OKX Tracker',
            content: 'Lỗi API: ${balanceResponse.msg}',
          );
        }
      }
    } catch (e) {
      // Hiển thị trạng thái lỗi ra thông báo để dễ chẩn đoán
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'OKX Tracker',
          content: 'Lỗi kết nối mạng hoặc đồng bộ...',
        );
      }
    }
  });
}