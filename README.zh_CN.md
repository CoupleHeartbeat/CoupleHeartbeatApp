<p align="right">
  <a href="README.md">English</a> · <strong>简体中文</strong>
</p>

# CoupleHeartbeat App

CoupleHeartbeat 设备的手机配套应用。通过低功耗蓝牙给挂饰配对或做单台配置、
下发 Wi-Fi 凭据，并把大模型 API Key 写进设备。基于 Flutter 开发。

设备固件在 https://github.com/CoupleHeartbeat/CoupleHeartbeatDev

## 功能

- **两台配对**：选中两台设备，分别输入屏幕上显示的 4 位配对码并起名字，App 会
  把配对信息写入两台设备。
- **单台配置**：只买了一台的用户，可以直接设置昵称并进入配网，不需要配对。
- **Wi-Fi 配网**：把网络名称与密码经 BLE 下发给设备，并持续显示结果（状态、IP
  地址、信号强度）直到连上；同一页面也能清除已保存的配网。
- **API Key**：把大模型 API Key 交给设备。Key 只写入设备，App 不保存、也不上传
  到别处。
- **真实状态**：电量、模式、音量与对方信号强度都从设备实时读取，不再显示占位
  数据。

## 设备协议

App 只与一个主服务（`0000ffe0-...`）交互：

| UUID | 权限 | 用途 |
| --- | --- | --- |
| 0xFFE1 | 写 | 配对配置 |
| 0xFFE2 | 读 / 写 | 工牌昵称 |
| 0xFFE3 | 读 | 设备状态 |
| 0xFFE4 | 写 | Wi-Fi 凭据 |
| 0xFFE5 | 读 | 配网状态 |
| 0xFFE6 | 读 / 写 | 大模型 API Key（读取只返回是否已配置） |

连接都是短连接：连上、完成一次读写后立即断开，让设备可以继续广播。

## 编译与运行

```bash
flutter pub get
flutter analyze
flutter run
```

蓝牙权限在运行时申请：Android 需要扫描与连接权限，iOS 使用工程里已声明的蓝牙
权限说明。

## 现状

`flutter test` 里仍是 Flutter 模板自带的 widget 测试，它在应用成型之前生成，
当前会失败。其余代码通过 `flutter analyze`，无 error 与 warning。
