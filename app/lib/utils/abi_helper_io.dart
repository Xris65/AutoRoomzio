import 'dart:async';
import 'dart:ffi' show Abi;
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart' show MethodChannel;

/// Returns the primary Android ABI of the current device (`arm64-v8a`,
/// `armeabi-v7a`, `x86_64`, etc.), or `null` outside Android.
Future<String?> getPrimaryAndroidAbi() async {
  if (defaultTargetPlatform != TargetPlatform.android) {
    return null;
  }

  const MethodChannel channel = MethodChannel('com.autoroomzio.app/device');
  try {
    final String? abi = await channel
        .invokeMethod<String>('getPrimaryAbi')
        .timeout(const Duration(seconds: 2));
    if (abi != null && abi.trim().isNotEmpty) {
      return abi.trim();
    }
  } catch (_) {
    // Fall back to dart:ffi Abi.current() in unit tests or headless isolates.
  }

  return switch (Abi.current()) {
    Abi.androidArm64 => 'arm64-v8a',
    Abi.androidArm => 'armeabi-v7a',
    Abi.androidX64 => 'x86_64',
    _ => null,
  };
}
