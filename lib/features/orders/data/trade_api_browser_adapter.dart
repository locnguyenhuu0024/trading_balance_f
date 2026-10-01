import 'package:dio/browser.dart';
import 'package:dio/dio.dart';

bool get supportsTradeSessionRestoration => true;

void configureTradeApiBrowserClient(Dio dio) {
  dio.httpClientAdapter = BrowserHttpClientAdapter()..withCredentials = true;
}
