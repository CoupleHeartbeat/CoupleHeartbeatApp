import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // 配对状态
  static Future<bool> isPaired() async {
    return _prefs.getBool('is_paired') ?? false;
  }

  static Future<void> setPaired(bool paired) async {
    await _prefs.setBool('is_paired', paired);
  }

  // 运行模式：'pair'=两台配对（默认），'single'=单台配置
  static Future<String?> getMode() async {
    return _prefs.getString('mode');
  }

  static Future<void> setMode(String mode) async {
    await _prefs.setString('mode', mode);
  }

  // 设备名称
  static Future<String?> getDeviceName(String role) async {
    return _prefs.getString('device_${role}_name');
  }

  static Future<void> setDeviceName(String role, String name) async {
    await _prefs.setString('device_${role}_name', name);
  }

  // 设备 MAC 地址
  static Future<String?> getDeviceAddress(String role) async {
    return _prefs.getString('device_${role}_addr');
  }

  static Future<void> setDeviceAddress(String role, String addr) async {
    await _prefs.setString('device_${role}_addr', addr);
  }

  // Pair ID
  static Future<String?> getPairId() async {
    return _prefs.getString('pair_id');
  }

  static Future<void> setPairId(String id) async {
    await _prefs.setString('pair_id', id);
  }

  // 音量设置
  static Future<int?> getVolume() async {
    return _prefs.getInt('volume');
  }

  static Future<void> setVolume(int vol) async {
    await _prefs.setInt('volume', vol);
  }


  // 本机配对的是哪一台设备：'A' 或 'B'（两台手机各配各自的一台）
  static Future<String?> getLocalRole() async {
    return _prefs.getString('local_role');
  }

  static Future<void> setLocalRole(String role) async {
    await _prefs.setString('local_role', role);
  }

  // 本机所配设备的蓝牙地址
  static Future<String?> getLocalAddress() async {
    final role = await getLocalRole();
    if (role == null || role.isEmpty) return null;
    return getDeviceAddress(role);
  }

  // 小米 MiMo API Key 只保存在手机本地，不下发设备
  static Future<String?> getApiKey() async {
    return _prefs.getString('mimo_api_key');
  }

  static Future<void> setApiKey(String apiKey) async {
    await _prefs.setString('mimo_api_key', apiKey);
  }

  static Future<void> clearApiKey() async {
    await _prefs.remove('mimo_api_key');
  }

  // 后台语音服务是否启用（默认开启，配对后自动常驻）
  static Future<bool> getVoiceEnabled() async {
    return _prefs.getBool('voice_enabled') ?? true;
  }

  static Future<void> setVoiceEnabled(bool enabled) async {
    await _prefs.setBool('voice_enabled', enabled);
  }

  // 清除所有配对数据
  static Future<void> clearAll() async {
    await _prefs.clear();
  }
}
