import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Observes platform appearance changes for screens that render outside the
/// MaterialApp theme (for example, legacy presentation widgets).
class PlatformBrightnessObserver extends ChangeNotifier
    with WidgetsBindingObserver {
  PlatformBrightnessObserver()
    : _brightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness {
    WidgetsBinding.instance.addObserver(this);
  }

  Brightness _brightness;

  Brightness get brightness => _brightness;

  bool get isDark => _brightness == Brightness.dark;

  @override
  void didChangePlatformBrightness() {
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    if (brightness == _brightness) return;
    _brightness = brightness;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

final platformBrightnessProvider =
    ChangeNotifierProvider<PlatformBrightnessObserver>((ref) {
      final observer = PlatformBrightnessObserver();
      return observer;
    });
