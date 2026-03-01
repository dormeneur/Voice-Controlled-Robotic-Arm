# Voice-Controlled Robotic Arm

A minimal Flutter app that controls a robotic arm via voice commands over Bluetooth Classic.

**Speak → Recognize → Map → Transmit → Move.**

## How It Works

```
Voice ──► speech_to_text ──► Command Mapper ──► Bluetooth SPP ──► HC-05 ──► Arduino ──► Servos
```

The app uses the device's built-in speech engine to recognize commands, maps keywords to single-character codes, and sends them over Bluetooth Classic to an Arduino Uno driving four servos.

## Commands

| Voice Input        | Code | Action        |
| ------------------ | ---- | ------------- |
| "left"             | `L`  | Rotate base ← |
| "right"            | `R`  | Rotate base → |
| "up"               | `U`  | Shoulder up   |
| "down"             | `D`  | Shoulder down |
| "pick"             | `P`  | Close gripper |
| "release" / "open" | `O`  | Open gripper  |
| "reset"            | `X`  | Neutral (90°) |

Manual control buttons are included as backup.

## Tech Stack

| Layer    | Tech                                                  |
| -------- | ----------------------------------------------------- |
| Mobile   | Flutter, `speech_to_text`, `flutter_bluetooth_serial` |
| Hardware | Arduino Uno, HC-05 Bluetooth Module, 4× Servo Motors  |

No cloud. No AI. No BLE. Just serial over Bluetooth Classic.

## Project Structure

```
lib/
  main.dart
  screens/home_screen.dart        # UI — connect, speak, tap
  services/bluetooth_service.dart  # HC-05 SPP connection & TX
  services/speech_service.dart     # Device speech recognition
  utils/command_mapper.dart        # Keyword → char mapping
arduino/
  robotic_arm.ino                  # Serial listener + servo control
```

## Setup

### Flutter App

```bash
flutter pub get
flutter run
```

> Android only. Pair HC-05 in system Bluetooth settings first.

### Arduino

1. Wire HC-05: `TX→RX`, `RX→TX` (voltage divider), `VCC→5V`, `GND→GND`
2. Attach servos to pins **3, 5, 6, 9**
3. Upload `arduino/robotic_arm.ino` at **9600 baud**
4. Power servos from an external supply if using more than 2

## Permissions (Android)

Bluetooth, Location, Microphone, and Internet — requested at runtime via `permission_handler`.

## License

MIT
