<p align="right">
  <a href="README.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# CoupleHeartbeat App

The phone companion for the CoupleHeartbeat devices. It pairs or configures the
gadgets over Bluetooth Low Energy, pushes the Wi-Fi credentials they need and
stores the model API key on the device. Built with Flutter.

Firmware lives in https://github.com/CoupleHeartbeat/CoupleHeartbeatDev

## What it does

- **Pair two devices** - pick both gadgets, type the 4-digit code each one shows
  on screen, give them names. The app then writes the pairing data to both.
- **Configure a single device** - for someone who owns only one gadget: set its
  nickname and go straight to provisioning, without pairing.
- **Wi-Fi provisioning** - send the network name and password to a device over
  BLE and watch the result (state, IP address, signal strength) until it
  connects. Credentials can be cleared again from the same page.
- **API key** - hand the model API key to a device. The key is written to the
  device and never stored by the app and never uploaded anywhere else.
- **Live status** - read battery, mode, volume and partner signal straight from
  the device instead of showing placeholder values.

## Device protocol

The app talks to one primary service (`0000ffe0-...`):

| UUID | Access | Purpose |
| --- | --- | --- |
| 0xFFE1 | write | pairing configuration |
| 0xFFE2 | read / write | badge name |
| 0xFFE3 | read | device status |
| 0xFFE4 | write | Wi-Fi credentials |
| 0xFFE5 | read | Wi-Fi provisioning state |
| 0xFFE6 | read / write | model API key (reads only report whether one is set) |

Connections are short lived: the app connects, performs one read or write, then
disconnects so the device keeps advertising.

## Build and run

```bash
flutter pub get
flutter analyze
flutter run
```

Bluetooth permissions are requested at runtime; on Android the app asks for
scan and connect permissions, on iOS for the Bluetooth usage description that is
already declared in the project.

## Status

`flutter test` still contains the untouched Flutter template widget test, which
fails because it was written before the app existed. Everything else passes
`flutter analyze` with no errors or warnings.
