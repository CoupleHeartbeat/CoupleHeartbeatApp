import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// GATT 服务与特征 UUID（情侣配置服务）
class BleUuids {
  // 情侣配置服务
  static const String service = '0000ffe0-0000-1000-8000-00805f9b34fb';
  // 配对配置特征（写入：角色 + pair_id + pair_key + 对方地址）
  static const String pairConfig = '0000ffe1-0000-1000-8000-00805f9b34fb';
  // 工牌信息特征（写入/读取：昵称、签名）
  static const String badgeInfo = '0000ffe2-0000-1000-8000-00805f9b34fb';
  // 设备状态特征（通知：电量、模式、RSSI）
  static const String deviceStatus = '0000ffe3-0000-1000-8000-00805f9b34fb';
  // Wi-Fi 配置特征（写入：{"ssid":"xxx","password":"yyy"}，password 允许空串）
  static const String wifiConfig = '0000ffe4-0000-1000-8000-00805f9b34fb';
  // Wi-Fi 状态特征（读取：{"state":0|1|2|3,"ssid":"...","ip":"...","rssi":-55}）
  static const String wifiStatus = '0000ffe5-0000-1000-8000-00805f9b34fb';
  // AI 对话配置特征（写入：{"api_key":"sk-xxxx"} 保存、{"clear":true} 清除；
  // 读取：{"configured":true|false}。设备绝不回传 Key 明文）
  static const String aiConfig = '0000ffe6-0000-1000-8000-00805f9b34fb';
  // Wi-Fi 扫描特征（写入：{"scan":true} 让设备开始扫描；
  // 读取：{"scanning":true|false,"aps":[{"ssid":"MyWiFi","rssi":-55}, ...]}）
  static const String wifiScan = '0000ffe7-0000-1000-8000-00805f9b34fb';

  // flutter_blue_plus 的 Guid.toString() 对 16 位 UUID 只返回 "ffe0" 这样的
  // 4 字符短形式，直接与上面的 36 位完整 UUID 做 == 永远不相等。
  // 统一先归一化为 128 位形式再比较（str128 恒为 36 字符）。
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

// Wi-Fi 配网状态（由设备 GATT 0xFFE5 读取）
// state 含义：0=未配置、1=连接中、2=已连接、3=失败。
// 未连接时 ip 为空串、rssi 为 0。reason 是设备记录的最近一次断开原因码。
class WifiStatus {
  final int state;
  final String? ssid;
  final String? ip;
  final int? rssi;
  final int? reason;

  const WifiStatus({
    required this.state,
    this.ssid,
    this.ip,
    this.rssi,
    this.reason,
  });

  // 仅当设备已成功连上路由器时为 true
  bool get isConnected => state == 2;

  // 把设备的断开原因码翻译成可操作的中文提示（ESP-IDF wifi_err_reason_t）。
  // 让“未连上”能区分成密码错、找不到网络、信号太弱等，不必靠猜。
  String? get reasonHint {
    switch (reason) {
      case null:
      case 0:
        return null;
      case 15: // WIFI_REASON_4WAY_HANDSHAKE_TIMEOUT
      case 204: // WIFI_REASON_HANDSHAKE_TIMEOUT
        return '密码不正确，或路由器加密方式不兼容';
      case 2: // WIFI_REASON_AUTH_EXPIRE
      case 4: // WIFI_REASON_AUTH_FAIL
      case 23: // WIFI_REASON_802_1X_AUTH_FAILED
        return '路由器拒绝了认证，请核对密码';
      case 201: // WIFI_REASON_NO_AP_FOUND
        return '没扫到这个网络：名称是否打错，或它不是 2.4GHz 网络';
      case 203: // WIFI_REASON_ASSOC_FAIL
      case 205: // WIFI_REASON_CONNECTION_FAIL
        return '路由器拒绝连接，可能是信号太弱或设备数已满';
      case 200: // WIFI_REASON_BEACON_TIMEOUT
        return '连接中断，信号太弱';
      default:
        return '连接失败（原因码 $reason）';
    }
  }

  // 状态中文标签，未知取值退回“未知”
  String get stateLabel {
    switch (state) {
      case 0:
        return '未配置';
      case 1:
        return '连接中';
      case 2:
        return '已连接';
      case 3:
        return '连接失败';
      default:
        return '未知';
    }
  }
}

// 附近 Wi-Fi 热点（由设备 GATT 0xFFE7 扫描返回）
class WifiAp {
  final String ssid;
  final int rssi; // 信号强度（dBm，负值，越接近 0 越强）

  const WifiAp({required this.ssid, required this.rssi});
}

// Wi-Fi 扫描结果（由设备 GATT 0xFFE7 读取）
// scanning 为 true 表示设备仍在扫描，此时 aps 可能是上一次的结果或空数组。
// aps 已由设备按信号从强到弱排序，同名网络只保留最强的一条；
// 设备受 ATT 负载限制，最多返回约 13 条。
class WifiScanResult {
  final bool scanning;
  final List<WifiAp> aps;

  const WifiScanResult({required this.scanning, required this.aps});
}

class BleService {
  // 扫描设备（过滤 AI Passport 设备）
  // 权限被拒、蓝牙未开等错误会以 stream error 形式抛出，
  // 调用方需在 listen(onError: ...) 中处理。
  static Stream<List<BleDeviceInfo>> scanDevices({Duration timeout = const Duration(seconds: 10)}) {
    Map<String, BleDeviceInfo> devices = {};
    final controller = StreamController<List<BleDeviceInfo>>();

    // 权限被拒绝时 startScan 会抛 PlatformException，转发给监听者
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
        // 过滤：名称包含 "Passport" 或 "AI" 或广播中包含我们的服务 UUID
        bool isTarget = name.toLowerCase().contains('passport') ||
                       name.toLowerCase().contains('ai') ||
                       r.advertisementData.serviceUuids.any(
                         (uuid) => BleUuids.eq(uuid, BleUuids.service)
                       );
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

  // 生成随机 pair_id（8字节十六进制字符串）
  static String generatePairId() {
    final random = Random.secure();
    final bytes = List<int>.generate(8, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // 生成随机 pair_key（16字节十六进制字符串）
  static String generatePairKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // 连接设备并写入配对信息
  // 返回 null 表示成功，返回非空字符串表示失败原因。
  // 安全校验：必须携带设备屏幕显示的 4 位配对码；
  // 已配对设备会拒绝写入（需先在设备上长按 OK 恢复出厂）。
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

    // 协商 MTU：默认 23 字节只够传 20 字节负载，
    // 配对 JSON 约 100 字节，不协商会在写入时报 value too long
    try {
      await device.requestMtu(185);
    } catch (_) {
      // 部分平台不支持则维持默认，由后续写入报错
    }

    try {
      // 发现服务：Android 刚连接时可能瞬时失败或返回空列表，重试最多 3 次
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
        final uuids = services
            .map((s) => s.uuid.str128)
            .join(', ');
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

      // 找到配对配置特征
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

      // 构造配对数据（JSON 格式），pair_code 为设备屏幕上的 4 位配对码
      final data = {
        'role': role,
        'pair_id': pairId,
        'pair_key': pairKey,
        'partner_addr': partnerAddress,
        'badge_name': badgeName,
        'pair_code': int.tryParse(pairCode) ?? -1,
      };
      final payload = utf8.encode(jsonEncode(data));

      // 写入数据（设备端校验配对码，不通过会返回鉴权错误）
      await pairChar.write(payload, withoutResponse: false);
      return null;
    } catch (e) {
      return describePairWriteError(e);
    } finally {
      try { await device.disconnect(); } catch (_) {}
    }
  }

  // 将底层 BLE 写入异常翻译为具体的中文原因。
  // 设备端三种拒绝在手机侧都是异常：已配对/配对码不符 → ATT 鉴权错误，
  // 存储失败 → GATT_UNLIKELY，超时/链路中断各有别的错误码。
  // 之前一律提示"配对码错误"，导致配对码正确时用户无法定位真实原因。
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

  // 写入工牌信息
  static Future<bool> writeBadgeInfo({
    required BluetoothDevice device,
    required String badgeName,
  }) async {
    try {
      await device.connect(timeout: const Duration(seconds: 10));

      List<BluetoothService> services = await device.discoverServices();
      BluetoothService? svc;
      for (var s in services) {
        if (BleUuids.eq(s.uuid, BleUuids.service)) {
          svc = s;
          break;
        }
      }

      if (svc == null) {
        await device.disconnect();
        return false;
      }

      BluetoothCharacteristic? badgeChar;
      for (var c in svc.characteristics) {
        if (BleUuids.eq(c.uuid, BleUuids.badgeInfo)) {
          badgeChar = c;
          break;
        }
      }

      if (badgeChar == null) {
        await device.disconnect();
        return false;
      }

      final data = {'badge_name': badgeName};
      final payload = utf8.encode(jsonEncode(data));

      await badgeChar.write(payload, withoutResponse: false);

      await device.disconnect();
      return true;
    } catch (e) {
      try { await device.disconnect(); } catch (_) {}
      return false;
    }
  }

  // 读取设备真实状态：按地址重连，读取 0xFFE2（配对信息）与 0xFFE3（电量/模式/音量），
  // 随后断开，避免长时间占用设备连接与广播。返回 null 表示设备不可达（离线）。
  static Future<DeviceStatus?> readDeviceStatus({required String address}) async {
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
      try { await device.disconnect(); } catch (_) {}
    }
  }

  // 写入 Wi-Fi 凭据（配网）。
  // 返回 null 表示成功（设备已收到参数并开始连接），非 null 为中文失败原因。
  // password 允许为空串，表示开放网络。
  static Future<String?> writeWifiCredentials({
    required String address,
    required String ssid,
    required String password,
  }) =>
      _writeJsonToChar(
        address: address,
        uuid: BleUuids.wifiConfig,
        payload: {'ssid': ssid, 'password': password},
        notFoundMsg: '未找到 Wi-Fi 配置特征（固件版本过旧）：'
            '该设备可能不是 AI Passport，或固件未更新',
        onError: describeWifiWriteError,
      );

  // 清除设备已保存的 Wi-Fi 配置：下发 {"clear":true}。
  // 不能下发空 SSID——设备端会把空 SSID 当成非法参数并返回 ATT 错误。
  static Future<String?> clearWifiCredentials({required String address}) =>
      _writeJsonToChar(
        address: address,
        uuid: BleUuids.wifiConfig,
        payload: {'clear': true},
        notFoundMsg: '未找到 Wi-Fi 配置特征（固件版本过旧）：'
            '该设备可能不是 AI Passport，或固件未更新',
        onError: describeWifiWriteError,
      );

  // 让设备开始扫描附近 Wi-Fi（0xFFE7，写入 {"scan":true}）。
  // 返回 null 表示指令已下发成功，非 null 为中文失败原因。
  // 设备侧约需 2~4 秒完成扫描，调用方随后用 readWifiScanResult 轮询结果。
  // 该特征负载较大，写入前把 MTU 请求值提高到 512。
  static Future<String?> startWifiScan({required String address}) =>
      _writeJsonToChar(
        address: address,
        uuid: BleUuids.wifiScan,
        payload: {'scan': true},
        notFoundMsg: '未找到 Wi-Fi 扫描特征（固件版本过旧）：'
            '该设备可能不是 AI Passport，或固件未更新',
        onError: describeWifiWriteError,
        mtu: 512,
      );

  // 读取 Wi-Fi 扫描结果（0xFFE7）。
  // 返回 null 表示读不到（设备离线或固件不支持），调用方按失败处理。
  // scanning 为 true 表示设备仍在扫描，aps 可能是上一次的结果或空数组。
  // 该特征负载较大，连接成功后先把 MTU 请求提高到 512（失败则维持默认，不中断）。
  static Future<WifiScanResult?> readWifiScanResult({required String address}) async {
    if (address.isEmpty) return null;

    final device = BluetoothDevice.fromId(address);
    try {
      await device.connect(timeout: const Duration(seconds: 8));
    } catch (_) {
      return null;
    }

    // 扫描结果 JSON 较大，优先协商更大的 MTU；
    // 部分平台不支持时失败不报错，直接按默认 MTU 继续读取。
    try {
      await device.requestMtu(512);
    } catch (_) {
      // 忽略：维持默认 MTU，由后续读取决定成败
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

      BluetoothCharacteristic? scanChar;
      for (var c in svc.characteristics) {
        if (BleUuids.eq(c.uuid, BleUuids.wifiScan)) {
          scanChar = c;
          break;
        }
      }
      if (scanChar == null) return null;

      final decoded = jsonDecode(utf8.decode(await scanChar.read()));
      if (decoded is! Map) return null;

      final scanning = decoded['scanning'] == true;
      final aps = <WifiAp>[];
      final rawAps = decoded['aps'];
      if (rawAps is List) {
        for (final item in rawAps) {
          if (item is Map) {
            final ssid = item['ssid'];
            // 只保留有效 SSID，跳过解析不了的空项
            if (ssid is String && ssid.isNotEmpty) {
              aps.add(WifiAp(
                ssid: ssid,
                rssi: (item['rssi'] as num?)?.toInt() ?? 0,
              ));
            }
          }
        }
      }
      return WifiScanResult(scanning: scanning, aps: aps);
    } catch (_) {
      return null;
    } finally {
      try { await device.disconnect(); } catch (_) {}
    }
  }

  // 同时给多台设备下发同一套 Wi-Fi 凭据。
  // 按 addresses 顺序逐台串行下发（避免并发连接互相干扰），
  // 返回「地址 -> 错误原因」：null 表示该台成功，非 null 为该台的中文失败原因。
  // 单台失败不影响后续设备继续下发。
  static Future<Map<String, String?>> writeWifiCredentialsToMany({
    required List<String> addresses,
    required String ssid,
    required String password,
  }) async {
    final results = <String, String?>{};
    for (final addr in addresses) {
      results[addr] = await writeWifiCredentials(
        address: addr,
        ssid: ssid,
        password: password,
      );
    }
    return results;
  }

  // 写入 AI 对话 API Key（0xFFE6）：下发 {"api_key":"sk-xxxx"}。
  // 返回 null 表示成功，非 null 为中文失败原因。
  // Key 只写入设备本地，App 不保存也不上传；设备端 Key 非法/超长会返回 ATT 错误。
  static Future<String?> writeAiKey({
    required String address,
    required String apiKey,
  }) =>
      _writeJsonToChar(
        address: address,
        uuid: BleUuids.aiConfig,
        payload: {'api_key': apiKey},
        notFoundMsg: '未找到 AI 配置特征（固件版本过旧）：'
            '该设备可能不是 AI Passport，或固件未更新',
      );

  // 同时给多台设备下发同一个 AI 对话 API Key（成对双设备场景）。
  // 与 writeWifiCredentialsToMany 相同：按 addresses 顺序逐台串行下发，
  // 返回「地址 -> 错误原因」：null 表示该台成功，单台失败不影响后续设备。
  static Future<Map<String, String?>> writeAiKeyToMany({
    required List<String> addresses,
    required String apiKey,
  }) async {
    final results = <String, String?>{};
    for (final addr in addresses) {
      results[addr] = await writeAiKey(address: addr, apiKey: apiKey);
    }
    return results;
  }

  // 清除设备已保存的 AI 对话 API Key：下发 {"clear":true}。
  static Future<String?> clearAiKey({required String address}) =>
      _writeJsonToChar(
        address: address,
        uuid: BleUuids.aiConfig,
        payload: {'clear': true},
        notFoundMsg: '未找到 AI 配置特征（固件版本过旧）：'
            '该设备可能不是 AI Passport，或固件未更新',
      );

  // 同时清除多台设备的 AI 对话 API Key（成对双设备场景），语义同上。
  static Future<Map<String, String?>> clearAiKeyToMany({
    required List<String> addresses,
  }) async {
    final results = <String, String?>{};
    for (final addr in addresses) {
      results[addr] = await clearAiKey(address: addr);
    }
    return results;
  }

  // 通用 JSON 写入：连接（超时 12 秒）→ 尽力协商 MTU（默认 185）
  // → discoverServices 最多重试 3 次 → 找到 0xFFE0 服务与目标特征
  // → 写入 JSON（utf8 + jsonEncode），最后无论如何都断开连接。
  // 返回 null 表示成功，非 null 为中文失败原因。
  // notFoundMsg 在服务或目标特征缺失（通常是固件版本过旧）时返回；
  // onError 负责把底层 BLE 写入异常翻译为中文，缺省按 AI Key 场景翻译。
  // mtu 为协商的 MTU 请求值：默认 185（既有特征行为不变）；
  // 0xFFE7 等负载较大的特征可传入 512。
  static Future<String?> _writeJsonToChar({
    required String address,
    required String uuid,
    required Map<String, dynamic> payload,
    required String notFoundMsg,
    String Function(Object e)? onError,
    int mtu = 185,
  }) async {
    if (address.isEmpty) return '设备地址为空，请重新选择设备';

    final device = BluetoothDevice.fromId(address);
    try {
      await device.connect(timeout: const Duration(seconds: 12));
    } catch (_) {
      return '连接失败：无法连接设备，请靠近后重试';
    }

    // 协商 MTU：JSON 负载可能超过默认 23 字节，默认只够传 20 字节
    try {
      await device.requestMtu(mtu);
    } catch (_) {
      // 部分平台不支持则维持默认，由后续写入报错
    }

    try {
      // 发现服务：Android 刚连接时可能瞬时失败或返回空列表，重试最多 3 次
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

      // 写入数据（设备端校验参数合法性，参数非法会返回 ATT 错误）
      await targetChar.write(payloadBytes, withoutResponse: false);
      return null;
    } catch (e) {
      return (onError ?? describeAiWriteError)(e);
    } finally {
      try { await device.disconnect(); } catch (_) {}
    }
  }

  // 读取 AI 对话配置状态（0xFFE6）：返回是否已配置 Key。
  // 读不到（设备离线或固件不支持）返回 null，调用方按未知处理。
  // 设备绝不回传 Key 明文，App 只关心"是否已配置"。
  static Future<bool?> readAiKeyStatus({required String address}) async {
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

      BluetoothCharacteristic? aiChar;
      for (var c in svc.characteristics) {
        if (BleUuids.eq(c.uuid, BleUuids.aiConfig)) {
          aiChar = c;
          break;
        }
      }
      if (aiChar == null) return null;

      final decoded = jsonDecode(utf8.decode(await aiChar.read()));
      if (decoded is! Map) return null;
      final configured = decoded['configured'];
      if (configured is bool) return configured;
      return null;
    } catch (_) {
      return null;
    } finally {
      try { await device.disconnect(); } catch (_) {}
    }
  }

  // 读取 Wi-Fi 状态（0xFFE5）：按地址重连读取后断开。
  // 返回 null 表示读不到（设备离线或固件不支持），调用方应按离线处理。
  static Future<WifiStatus?> readWifiStatus({required String address}) async {
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

      BluetoothCharacteristic? wifiChar;
      for (var c in svc.characteristics) {
        if (BleUuids.eq(c.uuid, BleUuids.wifiStatus)) {
          wifiChar = c;
          break;
        }
      }
      if (wifiChar == null) return null;

      final decoded = jsonDecode(utf8.decode(await wifiChar.read()));
      if (decoded is! Map) return null;

      return WifiStatus(
        state: (decoded['state'] as num?)?.toInt() ?? 0,
        ssid: decoded['ssid'] as String?,
        ip: decoded['ip'] as String?,
        rssi: (decoded['rssi'] as num?)?.toInt(),
        reason: (decoded['reason'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    } finally {
      try { await device.disconnect(); } catch (_) {}
    }
  }

  // 写入工牌昵称（0xFFE2，"badge_name" 字段）。允许未配对设备写入。
  // 返回 null 表示成功，非 null 为明确的中文失败原因。
  // 连接流程参考 writeBadgeInfo，但补齐了服务发现重试与失败原因。
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
      // 发现服务：Android 刚连接时可能瞬时失败或返回空列表，重试最多 3 次
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
      try { await device.disconnect(); } catch (_) {}
    }
  }

  // 将 Wi-Fi 写入的底层 BLE 异常翻译为具体的中文原因（风格参考 describePairWriteError）。
  // 设备返回 ATT 错误即表示参数非法（如 SSID 为空）或下发队列已满。
  static String describeWifiWriteError(Object e) {
    final s = e.toString().toUpperCase();
    if (s.contains('GATT_WRITE_NOT_PERMITTED') ||
        s.contains('PROPERTY IS NOT SUPPORTED')) {
      return '写入失败：该设备特征不可写，固件版本可能过旧';
    }
    if (s.contains('GATT_UNLIKELY') ||
        s.contains('INSUFFICIENT_AUTHENTICATION') ||
        s.contains('INSUFFICIENT_ENCRYPTION') ||
        s.contains('INSUFFICIENT_AUTHORIZATION')) {
      return '写入失败：设备拒绝了 Wi-Fi 配置（参数非法或队列已满）';
    }
    if (s.contains('TIMEOUT') || s.contains('TIME EXPIRED')) {
      return '写入失败：写入 Wi-Fi 配置超时，请靠近设备后重试';
    }
    if (s.contains('DISCONNECT')) {
      return '写入失败：写入过程中设备断开连接，请靠近设备后重试';
    }
    return '写入失败：$e';
  }

  // 将 AI Key 写入的底层 BLE 异常翻译为具体的中文原因（风格参考 describeWifiWriteError）。
  // 设备端 Key 非法/超长会返回 ATT 错误，此处统一提示。
  static String describeAiWriteError(Object e) {
    final s = e.toString().toUpperCase();
    if (s.contains('GATT_WRITE_NOT_PERMITTED') ||
        s.contains('PROPERTY IS NOT SUPPORTED')) {
      return '写入失败：该设备特征不可写，固件版本可能过旧';
    }
    if (s.contains('GATT_UNLIKELY') ||
        s.contains('INSUFFICIENT_AUTHENTICATION') ||
        s.contains('INSUFFICIENT_ENCRYPTION') ||
        s.contains('INSUFFICIENT_AUTHORIZATION')) {
      return '写入失败：设备拒绝了 API Key（Key 非法或过长）';
    }
    if (s.contains('TIMEOUT') || s.contains('TIME EXPIRED')) {
      return '写入失败：写入 API Key 超时，请靠近设备后重试';
    }
    if (s.contains('DISCONNECT')) {
      return '写入失败：写入过程中设备断开连接，请靠近设备后重试';
    }
    return '写入失败：$e';
  }

  // 将工牌昵称写入的底层 BLE 异常翻译为具体的中文原因。
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
