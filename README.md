# Even G2 Controller App

Even Realities G2 スマートグラス用のFlutterアプリケーションです。

## 機能

- **BLEスキャン**: Even G2デバイスを自動検出
- **接続管理**: 標準BLE接続、認証ハンドシェイク
- **テレプロンプター**: カスタムテキストをグラスに表示
- **通信ログ**: 全BLE通信をリアルタイムで記録・エクスポート

## プロジェクト構成

```
lib/
├── main.dart                 # アプリエントリーポイント
├── models/
│   └── g2_constants.dart     # プロトコル定数、パケット構造
├── services/
│   ├── ble_service.dart      # BLE接続管理
│   ├── ble_log_service.dart  # 通信ログ記録
│   └── g2_protocol.dart      # G2パケット生成・解析
├── screens/
│   ├── scan_screen.dart      # デバイススキャン画面
│   ├── control_screen.dart   # テレプロンプター操作画面
│   └── log_screen.dart       # 通信ログ表示画面
└── utils/
    └── crc16.dart            # CRC-16/CCITT実装
```

## 技術仕様

### BLE UUID
| 機能 | UUID |
|------|------|
| メインサービス | `00002760-08c2-11e1-9073-0e8ac72e0000` |
| コマンド送信 | `...5401` |
| 応答受信 | `...5402` |
| ディスプレイ | `...6402` |

### パケット構造
```
[AA] [21] [seq] [len] [01] [01] [svc_hi] [svc_lo] [payload...] [crc_lo] [crc_hi]
```

- CRC-16/CCITT (init: 0xFFFF, poly: 0x1021)
- ペイロード部分のみCRC計算

## セットアップ

### 必要要件
- Flutter 3.10+
- iOS 13+ / Android 6.0+

### インストール

```bash
cd even_g2_app
flutter pub get
```

### ビルド・実行

```bash
# iOS
flutter run -d ios

# Android
flutter run -d android
```

## 権限

### Android
- `BLUETOOTH`, `BLUETOOTH_ADMIN` (API < 31)
- `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` (API >= 31)
- `ACCESS_FINE_LOCATION`

### iOS
- `NSBluetoothAlwaysUsageDescription`
- `bluetooth-central` (Background Modes)

## 参考

- [Even G2 Protocol](https://github.com/i-soxi/even-g2-protocol) - コミュニティによるプロトコル解析
