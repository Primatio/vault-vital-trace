import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/session_metadata.dart';

class PermissionDeniedException implements Exception {
  PermissionDeniedException(this.message, {this.canOpenSettings = false});

  final String message;
  final bool canOpenSettings;

  @override
  String toString() => message;
}

class AppPermissions {
  static Future<bool> ensureBlePermissions() async {
    if (Platform.isIOS) {
      final bluetooth = await Permission.bluetooth.request();
      return bluetooth.isGranted || bluetooth.isLimited;
    }

    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final scan = statuses[Permission.bluetoothScan];
    final connect = statuses[Permission.bluetoothConnect];
    return (scan?.isGranted ?? false) && (connect?.isGranted ?? false);
  }

  /// Requests camera (and microphone) permission.
  /// Throws [PermissionDeniedException] when access cannot be granted.
  static Future<void> ensureCameraPermissions() async {
    var camera = await Permission.camera.status;
    if (camera.isGranted) {
      await Permission.microphone.request();
      return;
    }

    if (camera.isPermanentlyDenied || camera.isRestricted) {
      throw PermissionDeniedException(
        'Camera permission is blocked. Enable it in Settings → Vault rPPG → Camera.',
        canOpenSettings: true,
      );
    }

    camera = await Permission.camera.request();
    if (camera.isGranted) {
      await Permission.microphone.request();
      return;
    }

    if (camera.isPermanentlyDenied || camera.isRestricted) {
      throw PermissionDeniedException(
        'Camera permission is blocked. Enable it in Settings → Vault rPPG → Camera.',
        canOpenSettings: true,
      );
    }

    throw PermissionDeniedException(
      'Camera permission is required to record sessions.',
      canOpenSettings: camera.isDenied,
    );
  }

  static Future<bool> openAppSettingsPage() => openAppSettings();

  static Future<DeviceInfoMeta> collectDeviceInfo() async {
    final package = await PackageInfo.fromPlatform();
    final plugin = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final info = await plugin.androidInfo;
      return DeviceInfoMeta(
        phoneModel: '${info.manufacturer} ${info.model}',
        osVersion: 'Android ${info.version.release} (SDK ${info.version.sdkInt})',
        osName: 'Android',
        appVersion: package.version,
        appBuild: package.buildNumber,
      );
    }

    if (Platform.isIOS) {
      final info = await plugin.iosInfo;
      return DeviceInfoMeta(
        phoneModel: info.utsname.machine,
        osVersion: '${info.systemName} ${info.systemVersion}',
        osName: info.systemName,
        appVersion: package.version,
        appBuild: package.buildNumber,
      );
    }

    return DeviceInfoMeta(
      phoneModel: 'unknown',
      osVersion: Platform.operatingSystemVersion,
      osName: Platform.operatingSystem,
      appVersion: package.version,
      appBuild: package.buildNumber,
    );
  }
}
