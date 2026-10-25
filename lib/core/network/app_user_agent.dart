import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppUserAgent {
  AppUserAgent._();

  static String _userAgent = _fallbackUserAgent;
  static String _platform = _detectPlatform();
  static String _version = 'unknown';
  static String _buildNumber = '';
  static String _deviceModel = '';
  static String _deviceName = '';
  static String _osVersion = '';

  static String get value => _userAgent;

  static Map<String, String> get defaultHeaders => {
    'User-Agent': _asciiHeaderValue(_userAgent),
    'X-Client-App': 'daidai-panel-app',
    'X-Client-Type': 'app',
    'X-Client-Platform': _asciiHeaderValue(_platform),
    'X-Client-Version': _asciiHeaderValue(versionLabel),
    // 注意：这里不再发送 X-Device-Model / X-Device-Name / X-OS-Version。
    // 设备名（尤其是中文设备名）曾因 HTTP 头不允许非 ASCII 导致请求发不出去；
    // 且部分 CDN/WAF/源站会拒收这类自定义头并直接返回 400。
    // 这些头仅用于诊断，移除不影响任何功能，同时彻底消除该风险。
  };

  /// HTTP 头字段值必须是 ASCII（可见字符 0x20-0x7E）。
  /// iOS 的设备名常是中文（如「张三的 iPhone」），直接放进 X-Device-Name 等头里会触发
  /// `FormatException: Invalid HTTP header field value`，导致请求发不出去。
  /// 这里把非 ASCII 字符按 UTF-8 百分号编码（如「陈」→ %E9%99%88），既保证 ASCII 安全，
  /// 又可被服务端解码还原，不丢信息。
  static String _asciiHeaderValue(String value) {
    final sb = StringBuffer();
    for (final rune in value.runes) {
      if (rune >= 0x20 && rune <= 0x7E) {
        sb.writeCharCode(rune);
      } else {
        for (final byte in utf8.encode(String.fromCharCode(rune))) {
          sb.write('%');
          sb.write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
        }
      }
    }
    return sb.toString();
  }

  static String get versionLabel =>
      _buildNumber.isEmpty ? _version : '$_version+$_buildNumber';

  static Future<void> initialize() async {
    _platform = _detectPlatform();

    try {
      final info = await PackageInfo.fromPlatform();
      _version = info.version.trim().isEmpty ? 'unknown' : info.version.trim();
      _buildNumber = info.buildNumber.trim();
    } catch (_) {
      _version = 'unknown';
      _buildNumber = '';
    }

    await _loadDeviceInfo();
    _userAgent = _buildUserAgent();
  }

  static String _buildUserAgent() {
    final detail = _buildDetailSegments();
    switch (_platform) {
      case 'android':
        return 'DaidaiPanelApp/$versionLabel ($detail; Flutter)';
      case 'ios':
        return 'DaidaiPanelApp/$versionLabel ($detail; Flutter)';
      case 'macos':
        return 'DaidaiPanelApp/$versionLabel ($detail; Flutter)';
      case 'windows':
        return 'DaidaiPanelApp/$versionLabel ($detail; Flutter)';
      case 'linux':
        return 'DaidaiPanelApp/$versionLabel ($detail; Flutter)';
      case 'web':
        return 'DaidaiPanelApp/$versionLabel ($detail; Flutter)';
      default:
        return _fallbackUserAgent;
    }
  }

  static Future<void> _loadDeviceInfo() async {
    _deviceModel = '';
    _deviceName = '';
    _osVersion = '';

    if (kIsWeb) {
      return;
    }

    final plugin = DeviceInfoPlugin();
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final info = await plugin.androidInfo;
          _deviceModel = _mergeAndroidBrandAndModel(
            info.manufacturer,
            info.model,
          );
          _deviceName = info.device.trim();
          _osVersion = info.version.release.trim();
          return;
        case TargetPlatform.iOS:
          final info = await plugin.iosInfo;
          final machine = info.utsname.machine.trim();
          _deviceModel = machine.isNotEmpty ? machine : info.model.trim();
          _deviceName = info.name.trim();
          _osVersion = info.systemVersion.trim();
          return;
        case TargetPlatform.macOS:
          final info = await plugin.macOsInfo;
          _deviceModel = info.model.trim();
          _deviceName = info.computerName.trim();
          _osVersion = info.osRelease.trim();
          return;
        case TargetPlatform.windows:
          final info = await plugin.windowsInfo;
          _deviceModel = info.productName.trim();
          _deviceName = info.computerName.trim();
          _osVersion = info.displayVersion.trim();
          return;
        case TargetPlatform.linux:
          final info = await plugin.linuxInfo;
          _deviceModel = info.prettyName.trim();
          _deviceName = info.name.trim();
          _osVersion = info.version?.trim() ?? '';
          return;
        case TargetPlatform.fuchsia:
          return;
      }
    } catch (_) {
      _deviceModel = '';
      _deviceName = '';
      _osVersion = '';
    }
  }

  static String _buildDetailSegments() {
    final parts = <String>[];
    final platformLabel = _platformLabel();
    if (platformLabel.isNotEmpty) {
      parts.add(platformLabel);
    }
    if (_deviceModel.isNotEmpty) {
      parts.add(_deviceModel);
    } else if (_deviceName.isNotEmpty) {
      parts.add(_deviceName);
    }
    return parts.join('; ');
  }

  static String _platformLabel() {
    switch (_platform) {
      case 'android':
        return _osVersion.isEmpty ? 'Android' : 'Android $_osVersion';
      case 'ios':
        return _osVersion.isEmpty ? 'iOS' : 'iOS $_osVersion';
      case 'macos':
        return _osVersion.isEmpty ? 'macOS' : 'macOS $_osVersion';
      case 'windows':
        return _osVersion.isEmpty ? 'Windows' : 'Windows $_osVersion';
      case 'linux':
        return _osVersion.isEmpty ? 'Linux' : 'Linux $_osVersion';
      case 'web':
        return 'Web';
      default:
        return '';
    }
  }

  static String _mergeAndroidBrandAndModel(String manufacturer, String model) {
    final maker = manufacturer.trim();
    final deviceModel = model.trim();
    if (maker.isEmpty) {
      return deviceModel;
    }
    if (deviceModel.isEmpty) {
      return maker;
    }
    final makerLower = maker.toLowerCase();
    final modelLower = deviceModel.toLowerCase();
    if (modelLower.startsWith(makerLower)) {
      return deviceModel;
    }
    return '$maker $deviceModel';
  }

  static String _detectPlatform() {
    if (kIsWeb) {
      return 'web';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  static const String _fallbackUserAgent = 'DaidaiPanelApp/unknown (Flutter)';
}
