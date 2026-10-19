<p align="right">
  <a href="README.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# CoupleHeartbeat · App

![platform](https://img.shields.io/badge/Flutter-Android%20%7C%20iOS-02569B)
![transport](https://img.shields.io/badge/transport-BLE-informational)

The phone companion for the CoupleHeartbeat badges. It pairs or configures the
gadgets over Bluetooth Low Energy, provisions them with Wi-Fi credentials,
writes the model API key and keeps their clock in sync. Built with Flutter.

Firmware lives in https://github.com/CoupleHeartbeat/CoupleHeartbeatDev

## Features

| Area | Behaviour |
| --- | --- |
| **Pair two devices** | Pick both badges, enter the 4-digit code shown on each screen and give them names; the app writes the pairing data to both. |
| **Single-device setup** | Own only one badge? Set its nickname and go straight to provisioning, no pairing required. |
| **Wi-Fi provisioning** | Scans nearby networks on the phone first (2.4 GHz only, 5/6 GHz filtered) and falls back to a device-side scan. Credentials can be sent to one or both badges, and the page polls state, IP and signal until the device connects. The same page can clear saved credentials. |
| **Badge settings** | Change the nickname shown on the badge. |
| **Model API key** | Written to the device only. The app neither stores nor uploads it anywhere else. |
| **Volume** | Adjust the heartbeat volume (including mute) and read the current level back. |
| **Time sync** | Sends the phone's Unix time and UTC offset so the badge shows the correct local date and time. |
| **Live status** | Battery, mode, volume and partner signal are read from the device instead of placeholders. |

## Permissions

Android:

- `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` for BLE.
- `ACCESS_FINE_LOCATION` plus the system location switch for Wi-Fi scanning.
  Android treats scan results as location data even on recent versions.
- `NEARBY_WIFI_DEVICES` on Android 13+; the app requests it at runtime before
  the first scan.

iOS: only the Bluetooth usage description is needed. iOS does not expose a
public Wi-Fi list API, so iPhone users enter the SSID manually or rely on the
device-side scan.

## Build and run

```bash
flutter pub get
flutter analyze
flutter run
flutter build apk --release
```

### Release signing

Create `android/key.properties` (ignored by git) with:

```
storePassword=...
keyPassword=...
keyAlias=...
storeFile=release-key.jks
```

Place the keystore next to the app module (for example
`android/app/release-key.jks`) and point `storeFile` at it. Both
`android/key.properties` and `*.jks` are excluded by `.gitignore`.

## Device protocol

The app talks to one primary service
(`0000ffe0-0000-1000-8000-00805f9b34fb`):

| UUID | Access | Purpose |
| --- | --- | --- |
| 0xFFE1 | write | Pairing configuration |
| 0xFFE2 | read / write | Badge name |
| 0xFFE3 | read / notify | Device status |
| 0xFFE4 | write | Wi-Fi credentials |
| 0xFFE5 | read / notify | Wi-Fi provisioning state |
| 0xFFE6 | read / write | Model API key (reads only report whether one is set) |
| 0xFFE7 | read / write | Nearby Wi-Fi scan (write a request, read the list) |
| 0xFFE8 | write | Time sync (`unix` seconds and `tz_offset` seconds) |

Connections are short lived: the app connects, performs one read or write, then
disconnects so the device can keep advertising.

## Project layout

```
lib/pages/       pairing, device and badge config, API key, volume, Wi-Fi, scan
lib/services/    BLE transport and local storage
android/         manifest, permissions and release signing
ios/             Runner project and Bluetooth usage description
```

## Development notes

`flutter test` still contains the untouched Flutter template widget test, which
fails because it predates the app. `flutter analyze` reports no errors.
