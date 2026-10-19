<p align="right">
  <a href="README.md">English</a> · <strong>简体中文</strong>
</p>

# CoupleHeartbeat · 手机 App

![platform](https://img.shields.io/badge/Flutter-Android%20%7C%20iOS-02569B)
![transport](https://img.shields.io/badge/transport-BLE-informational)

CoupleHeartbeat 挂饰的手机配套应用。通过低功耗蓝牙完成配对或单台配置、下发
Wi-Fi 凭据、写入大模型 API Key，并给设备校准时间。基于 Flutter 开发。

设备固件在 https://github.com/CoupleHeartbeat/CoupleHeartbeatDev

## 功能

| 模块 | 行为 |
| --- | --- |
| **两台配对** | 选中两台设备，分别输入屏幕上显示的 4 位配对码并起名，App 会把配对信息写入两台设备。 |
| **单台配置** | 只有一台设备时，可直接设置昵称并进入配网，无需配对。 |
| **Wi-Fi 配网** | 优先用手机扫描附近网络（仅保留 2.4GHz，过滤 5/6GHz），不可用时降级为设备端扫描。凭据可同时下发给两台设备，页面持续轮询状态、IP 与信号直到连上；同一页面也能清除已保存的配网。 |
| **工牌设置** | 修改设备上显示的昵称。 |
| **大模型 API Key** | 只写入设备，App 不保存、也不上传到其他位置。 |
| **音量** | 调节心跳音量（含静音模式）并回读当前档位。 |
| **时间同步** | 下发手机的 Unix 时间与 UTC 偏移，让工牌显示正确的本地日期与时间。 |
| **实时状态** | 电量、模式、音量与对方信号都从设备实时读取，不显示占位数据。 |

## 权限说明

Android：

- `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT`：BLE 扫描与连接。
- `ACCESS_FINE_LOCATION` 与系统定位开关：Android 将 Wi-Fi 扫描结果视为位置
  信息，即使较新版本也要求定位权限。
- `NEARBY_WIFI_DEVICES`（Android 13+）：首次扫描前在运行时申请。

iOS：只需蓝牙用途说明。iOS 没有公开的 Wi-Fi 列表 API，iPhone 用户需手动输入
SSID，或改用设备端扫描。

## 编译与运行

```bash
flutter pub get
flutter analyze
flutter run
flutter build apk --release
```

### 发行版签名

创建 `android/key.properties`（已被 git 忽略）：

```
storePassword=...
keyPassword=...
keyAlias=...
storeFile=release-key.jks
```

把 keystore 放在 app 模块旁（例如 `android/app/release-key.jks`），并让
`storeFile` 指向它。`android/key.properties` 与 `*.jks` 都在 `.gitignore` 中，
不会进入仓库。

## 设备协议

App 只与一个主服务（`0000ffe0-0000-1000-8000-00805f9b34fb`）交互：

| UUID | 权限 | 用途 |
| --- | --- | --- |
| 0xFFE1 | 写 | 配对配置 |
| 0xFFE2 | 读 / 写 | 工牌昵称 |
| 0xFFE3 | 读 / 通知 | 设备状态 |
| 0xFFE4 | 写 | Wi-Fi 凭据 |
| 0xFFE5 | 读 / 通知 | 配网状态 |
| 0xFFE6 | 读 / 写 | 大模型 API Key（读取只返回是否已配置） |
| 0xFFE7 | 读 / 写 | 扫描附近 Wi-Fi（写请求，读列表） |
| 0xFFE8 | 写 | 时间同步（`unix` 秒与 `tz_offset` 秒） |

连接都是短连接：连上、完成一次读写后立即断开，让设备可以继续广播。

## 目录结构

```
lib/pages/       配对、设备/工牌配置、API Key、音量、Wi-Fi、扫描
lib/services/    BLE 传输与本地存储
android/         Manifest、权限与发行版签名
ios/             Runner 工程与蓝牙用途说明
```

## 开发说明

`flutter test` 中仍是 Flutter 模板自带的 widget 测试，它在应用成型前生成，
当前会失败。`flutter analyze` 无 error。
