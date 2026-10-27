import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

// GATT 服务与特征 UUID（情侣配置服务，与固件 couple_gatt.c 一一对应）
class BleUuids {
  // 情侣配置服务
  static const String service = '0000ffe0-0000-1000-8000-00805f9b34fb';
  // 配对配置特征（写入：角色 + pair_id + pair_key + 对方地址）
  static const String pairConfig = '0000ffe1-0000-1000-8000-00805f9b34fb';
  // 工牌信息特征（写入/读取：昵称、签名）
  static const String badgeInfo = '0000ffe2-0000-1000-8000-00805f9b34fb';
  // 设备状态特征（通知：电量、模式、RSSI）
  static const String deviceStatus = '0000ffe3-0000-1000-8000-00805f9b34fb';
  // 时间同步特征（写入：{"unix":1767225600,"tz_offset":28800}）
  static const String timeSync = '0000ffe8-0000-1000-8000-00805f9b34fb';
  // 语音上行特征（Notify）：设备 -> 手机，6 字节头 + PCM
  static const String voiceUp = '0000ffe9-0000-1000-8000-00805f9b34fb';
  // 回复下行特征（Write）：手机 -> 设备，[status][UTF-8 文本]
  static const String voiceReply = '0000ffea-0000-1000-8000-00805f9b34fb';

  // ---- 产品身份识别（严格扫描过滤用）----
  static const int mfgCompanyId = 0x02E5;
  static const int mfgHeartbeatMinLen = 22;
  static const String deviceNamePrefix = 'AI-Passport';

  // flutter_blue_plus 的 Guid.toString() 对 16 位 UUID 只返回 "ffe0" 短形式，
  // 直接与 36 位完整 UUID 做 == 永远不相等，统一归一化为 128 位再比较。
  static bool eq(Guid uuid, String target) =>
      uuid.str128.toLowerCase() == target.toLowerCase();
}

class BleDeviceInfo {
  final BluetoothDevice device;
  final String name;
  final int rssi;
  String? role; // 'A' or 'B' or null

  BleDeviceInfo({
    required this.device,
    required this.name,
    required this.rssi,
    this.role,
  });
}

// 设备真实状态（由设备 GATT 0xFFE2 / 0xFFE3 读取）
class DeviceStatus {
  final bool paired;
  final String? badgeName;
  final int? battery; // 0..100，读取失败为 null
  final int? mode; // 0=工牌（含靠近光效） 1=对话
  final int? volume; // 0..100
  final int? partnerRssi; // 对方设备信号强度（dBm）

  const DeviceStatus({
    required this.paired,
    this.badgeName,
    this.battery,
    this.mode,
    this.volume,
    this.partnerRssi,
  });

  static const List<String> modeNames = ['工牌', '对话'];

  String get modeName =>
      (mode != null && mode! >= 0 && mode! < modeNames.length)
          ? modeNames[mode!]
          : '未知';
}

class BleService {
  // Android 12+ 的附近设备权限（扫描 + 连接）。已授予时不会弹窗。
  static Future<bool> ensurePermissions() async {
    if (!Platform.isAndroid) return true;
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    return results.values.every((s) => s.isGranted);
  }

  // 扫描设备（过滤 AI Passport 设备）
  static Stream<List<BleDeviceInfo>> scanDevices(
      {Duration timeout = const Duration(seconds: 10)}) {
    Map<String, BleDeviceInfo> devices = {};
    final controller = StreamController<List<BleDeviceInfo>>();

    FlutterBluePlus.startScan(timeout: timeout, androidUsesFineLocation: false)
        .catchError((Object e) {
      if (!controller.isClosed) {
        controller.addError(e);
        controller.close();
      }
      return FlutterBluePlus;
    });

    final sub = FlutterBluePlus.scanResults.map((results) {
      for (var r in results) {
        final name = r.device.localName;
        // 三条身份信号任一命中即认：服务 UUID 0xFFE0、厂家心跳数据、名称前缀
        final hasService = r.advertisementData.serviceUuids
            .any((uuid) => BleUuids.eq(uuid, BleUuids.service));
        final mfg = r.advertisementData.manufacturerData[BleUuids.mfgCompanyId];
        final hasMfg = mfg != null && mfg.length >= BleUuids.mfgHeartbeatMinLen;
        final isTarget =
            hasService || hasMfg || name.startsWith(BleUuids.deviceNamePrefix);
        if (isTarget && name.isNotEmpty) {
          devices[r.device.id.id] = BleDeviceInfo(
            device: r.device,
            name: name,
            rssi: r.rssi,
          );
        }
      }
      return devices.values.toList()
        ..sort((a, b) => b.rssi.compareTo(a.rssi));
    }).listen((list) {
      if (!controller.isClosed) {
        controller.add(list);
      }
    }, onError: (Object e) {
      if (!controller.isClosed) {
        controller.addError(e);
        controller.close();
      }
    });

    controller.onCancel = () {
      sub.cancel();
      FlutterBluePlus.stopScan().catchError((_) {});
    };

    return controller.stream;
  }

  static Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  // 生成随机 pair_id（8 字节十六进制字符串）
  static String generatePairId() {
    final random = Random.secure();
    final bytes = List<int>.generate(8, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // 生成随机 pair_key（16 字节十六进制字符串）
  static String generatePairKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // 连接设备并写入配对信息
  // 返回 null 表示成功，返回非空字符串表示失败原因。
  // 设备屏幕上的 4 位配对码必须一致，否则设备拒绝写入。
  static Future<String?> pairDevice({
    required BluetoothDevice device,
    required String role,
    required String pairId,
    required String pairKey,
    required String partnerAddress,
    required String badgeName,
    required String pairCode,
  }) async {
    try {
      await device.connect(timeout: const Duration(seconds: 15));
    } catch (e) {
      return '无法连接设备，请靠近后重试';
    }

    // 配对 JSON 约 100 字节，不协商 MTU 会在写入时报 value too long
    try {
      await device.requestMtu(185);
    } catch (_) {
      // 部分平台不支持则维持默认，由后续写入报错
    }

    try {
      List<BluetoothService> services = <BluetoothService>[];
      Object? lastErr;
      for (int i = 0; i < 3; i++) {
        try {
          services = await device.discoverServices();
          if (services.isNotEmpty) break;
        } catch (e) {
          lastErr = e;
        }
        await Future.delayed(const Duration(milliseconds: 400));
      }
      if (services.isEmpty && lastErr != null) {
        return '服务发现失败：$lastErr';
      }
      BluetoothService? svc;
      for (var s in services) {
        if (BleUuids.eq(s.uuid, BleUuids.service)) {
          svc = s;
          break;
        }
      }
      if (svc == null) {
        final uuids = services.map((s) => s.uuid.str128).join(', ');
        return '未找到配对服务(0xFFE0)：该设备可能不是 AI Passport，'
            '或固件未更新。已发现服务: ${services.isEmpty ? '(空)' : uuids}';
      }

      // 预检：读取设备配对状态
      BluetoothCharacteristic? badgeChar;
      for (var c in svc.characteristics) {
        if (BleUuids.eq(c.uuid, BleUuids.badgeInfo)) {
          badgeChar = c;
          break;
        }
      }
      if (badgeChar != null) {
        try {
          final raw = await badgeChar.read();
          final decoded = jsonDecode(utf8.decode(raw));
          if (decoded is Map && decoded['paired'] == true) {
            return '设备已配对，请先在设备上短按 OK 键进入设置菜单，选择"恢复出厂设置"';
          }
        } catch (_) {
          // 状态读取失败不阻塞配对，最终由设备端校验
        }
      }

      BluetoothCharacteristic? pairChar;
      for (var c in svc.characteristics) {
        if (BleUuids.eq(c.uuid, BleUuids.pairConfig)) {
          pairChar = c;
          break;
        }
      }
      if (pairChar == null) {
        return '未找到配对配置特征';
      }

      final data = {
        'role': role,
        'pair_id': pairId,
        'pair_key': pairKey,
        'partner_addr': partnerAddress,
        'badge_name': badgeName,
        'pair_code': int.tryParse(pairCode) ?? -1,
      };
      final payload = utf8.encode(jsonEncode(data));

      await pairChar.write(payload, withoutResponse: false);
      return null;
    } catch (e) {
      return describePairWriteError(e);
    } finally {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  // 将底层 BLE 写入异常翻译为具体的中文原因。
  static String describePairWriteError(Object e) {
    final s = e.toString().toUpperCase();
    if (s.contains('INSUFFICIENT_AUTHENTICATION') ||
        s.contains('INSUFFICIENT_ENCRYPTION') ||
        s.contains('INSUFFICIENT_AUTHORIZATION')) {
      return '设备拒绝了配对写入（鉴权失败）。若配对码正确，'
          '通常是设备已配对或手机残留旧蓝牙配对记录：'
          '请在设备上短按 OK 键进入设置菜单，选择"恢复出厂设置"，'
          '并在手机系统蓝牙设置中忽略该设备后重试';
    }
    if (s.contains('GATT_UNLIKELY')) {
      return '设备保存配对信息失败，请短按 OK 键进入设置菜单，选择"恢复出厂设置"后重试';
    }
    if (s.contains('GATT_WRITE_NOT_PERMITTED') ||
        s.contains('PROPERTY IS NOT SUPPORTED')) {
      return '该设备特征不可写，固件可能不是配对版本，请刷新固件';
    }
    if (s.contains('TIMEOUT') || s.contains('TIME EXPIRED')) {
      return '写入配对数据超时，请靠近设备后重试';
    }
    if (s.contains('DISCONNECT')) {
      return '写入过程中设备断开连接，请靠近设备后重试';
    }
    return '配对写入失败：$e';
  }

  // 读取设备真实状态：按地址重连，读取 0xFFE2 与 0xFFE3 后断开。
  // 返回 null 表示设备不可达（离线）。
  static Future<DeviceStatus?> readDeviceStatus(
      {required String address}) async {
    if (address.isEmpty) return null;

    final device = BluetoothDevice.fromId(address);
    try {
      await device.connect(timeout: const Duration(seconds: 8));
    } catch (_) {
      return null;
    }

    try {
      final services = await device.discoverServices();
      BluetoothService? svc;
      for (var s in services) {
        if (BleUuids.eq(s.uuid, BleUuids.service)) {
          svc = s;
          break;
        }
      }
      if (svc == null) return null;

      BluetoothCharacteristic? badgeChar;
      BluetoothCharacteristic? statusChar;
      for (var c in svc.characteristics) {
        if (BleUuids.eq(c.uuid, BleUuids.badgeInfo)) badgeChar = c;
        if (BleUuids.eq(c.uuid, BleUuids.deviceStatus)) statusChar = c;
      }

      bool paired = false;
      String? badgeName;
      if (badgeChar != null) {
        try {
          final decoded = jsonDecode(utf8.decode(await badgeChar.read()));
          if (decoded is Map) {
            paired = decoded['paired'] == true;
            badgeName = decoded['badge_name'] as String?;
          }
        } catch (_) {
          // 单个特征读取失败不阻塞整体状态
        }
      }

      int? battery, mode, volume, rssi;
      if (statusChar != null) {
        try {
          final decoded = jsonDecode(utf8.decode(await statusChar.read()));
          if (decoded is Map) {
            battery = (decoded['battery'] as num?)?.toInt();
            mode = (decoded['mode'] as num?)?.toInt();
            volume = (decoded['volume'] as num?)?.toInt();
            rssi = (decoded['rssi'] as num?)?.toInt();
          }
        } catch (_) {
          // 状态特征不可读时保留空值，由 UI 显示“--”
        }
      }

      return DeviceStatus(
        paired: paired,
        badgeName: badgeName,
        battery: battery,
        mode: mode,
        volume: volume,
        partnerRssi: rssi,
      );
    } catch (_) {
      return null;
    } finally {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  // 向单台设备同步时间（0xFFE8）：下发手机当前 Unix 秒 + 时区偏移秒。
  static Future<String?> writeDeviceTime({
    required String address,
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();
    final unixSec = t.toUtc().millisecondsSinceEpoch ~/ 1000;
    final tzOffset = t.timeZoneOffset.inSeconds;
    return _writeJsonToChar(
      address: address,
      uuid: BleUuids.timeSync,
      payload: {'unix': unixSec, 'tz_offset': tzOffset},
      notFoundMsg: '未找到时间同步特征（固件版本过旧）：'
          '该设备固件不支持时间同步，请先升级固件',
    );
  }

  // 同时向多台设备同步同一时刻（成对双设备场景）。
  static Future<Map<String, String?>> writeDeviceTimeToMany({
    required List<String> addresses,
    DateTime? now,
  }) async {
    final t = now ?? DateTime.now();
    final results = <String, String?>{};
    for (final addr in addresses) {
      results[addr] = await writeDeviceTime(address: addr, now: t);
    }
    return results;
  }

  // 通用 JSON 写入：连接 → 尽力协商 MTU → 发现服务 → 写入 → 断开。
  static Future<String?> _writeJsonToChar({
    required String address,
    required String uuid,
    required Map<String, dynamic> payload,
    required String notFoundMsg,
    int mtu = 185,
  }) async {
    if (address.isEmpty) return '设备地址为空，请重新选择设备';

    final device = BluetoothDevice.fromId(address);
    try {
      await device.connect(timeout: const Duration(seconds: 12));
    } catch (_) {
      return '连接失败：无法连接设备，请靠近后重试';
    }

    try {
      await device.requestMtu(mtu);
    } catch (_) {
      // 部分平台不支持则维持默认，由后续写入报错
    }

    try {
      List<BluetoothService> services = <BluetoothService>[];
      Object? lastErr;
      for (int i = 0; i < 3; i++) {
        try {
          services = await device.discoverServices();
          if (services.isNotEmpty) break;
        } catch (e) {
          lastErr = e;
        }
        await Future.delayed(const Duration(milliseconds: 400));
      }
      if (services.isEmpty && lastErr != null) {
        return '服务发现失败：$lastErr';
      }

      BluetoothService? svc;
      for (var s in services) {
        if (BleUuids.eq(s.uuid, BleUuids.service)) {
          svc = s;
          break;
        }
      }
      if (svc == null) {
        return notFoundMsg;
      }

      BluetoothCharacteristic? targetChar;
      for (var c in svc.characteristics) {
        if (BleUuids.eq(c.uuid, uuid)) {
          targetChar = c;
          break;
        }
      }
      if (targetChar == null) {
        return notFoundMsg;
      }

      final payloadBytes = utf8.encode(jsonEncode(payload));
      await targetChar.write(payloadBytes, withoutResponse: false);
      return null;
    } catch (e) {
      return '写入失败：$e';
    } finally {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  // 写入工牌昵称（0xFFE2）。允许未配对设备写入。
  static Future<String?> writeBadgeName({
    required String address,
    required String name,
  }) async {
    if (address.isEmpty) return '设备地址为空，请重新选择设备';

    final device = BluetoothDevice.fromId(address);
    try {
      await device.connect(timeout: const Duration(seconds: 12));
    } catch (_) {
      return '连接失败：无法连接设备，请靠近后重试';
    }

    try {
      List<BluetoothService> services = <BluetoothService>[];
      Object? lastErr;
      for (int i = 0; i < 3; i++) {
        try {
          services = await device.discoverServices();
          if (services.isNotEmpty) break;
        } catch (e) {
          lastErr = e;
        }
        await Future.delayed(const Duration(milliseconds: 400));
      }
      if (services.isEmpty && lastErr != null) {
        return '服务发现失败：$lastErr';
      }

      BluetoothService? svc;
      for (var s in services) {
        if (BleUuids.eq(s.uuid, BleUuids.service)) {
          svc = s;
          break;
        }
      }
      if (svc == null) {
        return '未找到设备服务(0xFFE0)：该设备可能不是 AI Passport，或固件未更新';
      }

      BluetoothCharacteristic? badgeChar;
      for (var c in svc.characteristics) {
        if (BleUuids.eq(c.uuid, BleUuids.badgeInfo)) {
          badgeChar = c;
          break;
        }
      }
      if (badgeChar == null) {
        return '未找到工牌信息特征(0xFFE2)，固件版本可能过旧';
      }

      final payload = utf8.encode(jsonEncode({'badge_name': name}));
      await badgeChar.write(payload, withoutResponse: false);
      return null;
    } catch (e) {
      return describeBadgeWriteError(e);
    } finally {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  static String describeBadgeWriteError(Object e) {
    final s = e.toString().toUpperCase();
    if (s.contains('GATT_WRITE_NOT_PERMITTED') ||
        s.contains('PROPERTY IS NOT SUPPORTED')) {
      return '写入失败：该设备特征不可写，固件版本可能过旧';
    }
    if (s.contains('GATT_UNLIKELY') ||
        s.contains('INSUFFICIENT_AUTHENTICATION') ||
        s.contains('INSUFFICIENT_ENCRYPTION') ||
        s.contains('INSUFFICIENT_AUTHORIZATION')) {
      return '写入失败：设备拒绝了昵称写入（参数非法或队列已满）';
    }
    if (s.contains('TIMEOUT') || s.contains('TIME EXPIRED')) {
      return '写入失败：写入昵称超时，请靠近设备后重试';
    }
    if (s.contains('DISCONNECT')) {
      return '写入失败：写入过程中设备断开连接，请靠近设备后重试';
    }
    return '写入失败：$e';
  }
}
