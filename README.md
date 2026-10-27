<p align="right">
  <a href="README.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# CoupleHeartbeat · App

![platform](https://img.shields.io/badge/Flutter-Android-02569B)
![transport](https://img.shields.io/badge/transport-BLE-informational)

The phone companion for the CoupleHeartbeat badges. The devices never join a
network: this app keeps a BLE link, receives the recorded voice, runs speech
recognition and the chat model through Xiaomi MiMo, and sends the reply text
back to the badge. Android only.

Firmware lives in https://github.com/CoupleHeartbeat/CoupleHeartbeatDev

## Features

| Area | Behaviour |
| --- | --- |
| **Two-phone pairing** | Each phone pairs its own badge. Phone A shows a QR code with `pair_id` / `pair_key` and its device address; phone B scans it, writes its own badge as role B and shows a receipt QR; A scans the receipt and writes its badge as role A. |
| **Single-device setup** | Own only one badge? Set its nickname and use it alone; the voice relay works the same way. |
| **Voice relay** | A long-lived BLE connection subscribes to 0xFFE9 notifications, reassembles the PCM stream, wraps it in WAV, calls `mimo-v2.5-asr`, then `mimo-v2.6-flash`, and writes the reply text to 0xFFEA. |
| **Background service** | An Android foreground service (`connectedDevice`) keeps the process and the BLE link alive when the app is not in the foreground. |
| **Model API key** | The MiMo key is stored on the phone only and never sent to the badge. |
| **Badge settings** | Change the nickname shown on the badge. |
| **Volume** | Adjust the heartbeat volume (including mute) and read the current level back. |
| **Time sync** | Sends the phone's Unix time and UTC offset so the badge shows the correct local date and time. |
| **Live status** | Battery, mode, volume and partner signal are read over the existing BLE link instead of placeholders. |

## Permissions

Android:

- `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` for BLE scanning and connections.
- `CAMERA` for the pairing QR scanner.
- `POST_NOTIFICATIONS` so the foreground-service notification stays visible.
- `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_CONNECTED_DEVICE` for the
  persistent BLE session.

No Wi-Fi or location permission is requested.

## Build and run

```bash
flutter pub get
flutter analyze
flutter run
flutter build apk --release
```

`mobile_scanner` 3.5.7 still compiles its own module against android-33 while
its AndroidX dependencies require 34+, so `android/build.gradle.kts` pins the
compileSdk of every plugin subproject to 36.

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
| 0xFFE8 | write | Time sync (`unix` seconds and `tz_offset` seconds) |
| 0xFFE9 | notify | Voice uplink: 6-byte header + PCM |
| 0xFFEA | write | Reply downlink: `[status][UTF-8 text]` |

Configuration writes use short connections (connect, write, disconnect). The
voice session keeps one connection open, asks for a 512-byte MTU, subscribes to
0xFFE9 and reconnects automatically after a drop.

### Voice uplink

| Offset | Field |
| --- | --- |
| 0 | type: `1` BEGIN, `2` DATA, `3` END, `4` CANCEL |
| 1 | reserved |
| 2..3 | offset, little endian |
| 4..5 | total PCM bytes, little endian |
| 6.. | PCM payload |

`END` carries the exact valid byte count, so the phone trims the stream and
never pads it with silence. Status `0` on 0xFFEA means success, `1` carries a
short error reason for the badge screen.

## Project layout

```
lib/pages/       pairing (QR), device and badge config, AI service, volume, scan
lib/services/    BLE transport, voice session, MiMo client, storage, foreground service
android/         manifest, permissions, foreground service and release signing
```

## Development notes

`flutter test` still contains the untouched Flutter template widget test, which
fails because it predates the app. `flutter analyze` reports no errors.
