<p align="right">
  <a href="README.md">English</a> · <strong>简体中文</strong>
</p>

# CoupleHeartbeat · 手机 App

![platform](https://img.shields.io/badge/Flutter-Android-02569B)
![transport](https://img.shields.io/badge/transport-BLE-informational)

CoupleHeartbeat 挂饰的手机配套应用。设备不再连接网络：App 保持一条 BLE 长连接，
接收设备录音，调用小米 MiMo 完成语音识别与对话，再把回复文本回传给设备显示。
仅支持 Android。

设备固件在 https://github.com/CoupleHeartbeat/CoupleHeartbeatDev

## 功能

| 模块 | 行为 |
| --- | --- |
| **两台手机配对** | 两台手机各配自己的一台设备。A 手机展示含 `pair_id` / `pair_key` 与自身设备地址的二维码；B 手机扫码后把本机设备写为角色 B 并展示回执二维码；A 再扫回执，把本机设备写为角色 A。 |
| **单台配置** | 只有一台设备时，设置昵称后即可单独使用，语音链路完全一致。 |
| **语音中继** | BLE 长连接订阅 0xFFE9 通知，重组 PCM 后封装 WAV，依次调用 `mimo-v2.5-asr` 与 `mimo-v2.6-flash`，最后把回复文本写入 0xFFEA。 |
| **后台服务** | Android 前台服务（`connectedDevice`）让进程与 BLE 连接在退到后台后继续存活。 |
| **模型 API Key** | MiMo Key 只保存在手机本地，不再下发给设备。 |
| **工牌设置** | 修改设备上显示的昵称。 |
| **音量** | 调节心跳音量（含静音模式）并回读当前档位。 |
| **时间同步** | 复用当前连接下发手机 Unix 时间与 UTC 偏移，让工牌显示正确的本地日期与时间。 |
| **实时状态** | 电量、模式、音量与对方信号都通过现有 BLE 连接读取，不显示占位数据。 |

## 权限说明

Android：

- `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT`：BLE 扫描与连接。
- `CAMERA`：扫描配对二维码。
- `POST_NOTIFICATIONS`：显示前台服务通知。
- `FOREGROUND_SERVICE` 与 `FOREGROUND_SERVICE_CONNECTED_DEVICE`：常驻语音连接。

不再申请 Wi-Fi 或定位权限。

## 编译与运行

```bash
flutter pub get
flutter analyze
flutter run
flutter build apk --release
```

`mobile_scanner` 3.5.7 自身仍按 android-33 编译，而其 AndroidX 依赖要求 34+，
因此 `android/build.gradle.kts` 把所有插件子工程的 compileSdk 统一为 36。

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
| 0xFFE8 | 写 | 时间同步（`unix` 秒与 `tz_offset` 秒） |
| 0xFFE9 | 通知 | 语音上行：6 字节头 + PCM |
| 0xFFEA | 写 | 回复下行：`[status][UTF-8 文本]` |

配置类写入使用短连接（连上、写入、断开）。语音会话则保持一条长连接，协商
512 字节 MTU、订阅 0xFFE9，断线后自动重连。

### 语音上行

| 偏移 | 字段 |
| --- | --- |
| 0 | 类型：`1` BEGIN，`2` DATA，`3` END，`4` CANCEL |
| 1 | 保留 |
| 2..3 | offset，小端 |
| 4..5 | PCM 总字节数，小端 |
| 6.. | PCM 数据 |

`END` 携带实际有效字节数，手机按此截断，绝不补静音。0xFFEA 的 status `0`
表示成功，`1` 表示失败并附带简短原因，供设备屏幕显示。

## 目录结构

```
lib/pages/       配对（二维码）、设备/工牌配置、AI 服务、音量、扫描
lib/services/    BLE 传输、语音会话、MiMo 客户端、本地存储、前台服务
android/         Manifest、权限、前台服务与发行版签名
```

## 开发说明

`flutter test` 中仍是 Flutter 模板自带的 widget 测试，它在应用成型前生成，
当前会失败。`flutter analyze` 无 error。
