import 'dart:io';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

// Android 前台服务：让 Flutter 进程在后台常驻，BLE 长连接才不会掉。
// 非 Android 平台直接跳过。
class ForegroundService {
  static const MethodChannel _channel =
      MethodChannel('ai_passport/foreground');

  static Future<void> start() async {
    if (!Platform.isAndroid) return;
    try {
      // Android 13+ 通知权限只影响通知可见性，拒绝也照常启动服务
      await Permission.notification.request();
    } catch (_) {}
    try {
      await _channel.invokeMethod('start');
    } catch (_) {
      // 通知权限未授予等场景不影响语音链路，静默忽略
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }
}
