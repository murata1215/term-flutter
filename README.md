# term-flutter

iOS/Android 両対応の SSH クライアントアプリ（Flutter製）。
表示専用ターミナル + コマンド入力バーの構成で、スマホからのサーバー管理を快適にします。

## 特徴

- **SSH接続** — パスワード認証・秘密鍵認証（ed25519/RSA/ECDSA）対応
- **ターミナル表示** — xterm.dart による VT100/xterm エスケープシーケンス対応
- **コマンド入力** — 画面下部の入力バー + OSキーボード。↑↓でbash履歴ナビゲーション
- **接続先管理** — 接続成功時に自動保存。次回からワンタップで接続
- **再接続** — 切断検知 + ワンタップ再接続 + アプリ復帰時の自動再接続
- **セキュリティ** — パスワード/秘密鍵の暗号化保存（Keychain/Keystore）+ TOFU方式ホスト鍵検証
- **ダークテーマ** — ターミナルらしい黒背景 + グリーンアクセント

## 技術スタック

| 項目 | 採用技術 |
|---|---|
| フレームワーク | Flutter (Dart 3.x) |
| SSH | dartssh2 |
| ターミナル表示 | xterm.dart |
| 状態管理 | flutter_riverpod |
| ローカル保存 | shared_preferences |
| セキュア保存 | flutter_secure_storage |

## ビルド & 実行

```bash
flutter pub get
flutter run          # デバッグ実行
flutter analyze      # 静的解析
flutter test         # テスト実行
```

## プロジェクト構成

```
lib/
├── main.dart                          # エントリポイント
├── app.dart                           # MaterialApp（ダークテーマ）
├── models/ssh_connection_info.dart    # SSH接続情報データクラス
├── services/
│   ├── ssh_service.dart               # SSH接続・送受信・ホスト鍵検証
│   ├── connection_storage_service.dart # 接続先の永続化
│   └── host_key_storage_service.dart  # ホスト鍵フィンガープリントの保存
├── screens/
│   ├── home_screen.dart               # 接続先一覧 + 新規接続フォーム
│   └── terminal_screen.dart           # ターミナル表示画面
└── widgets/
    ├── command_input_bar.dart          # コマンド入力バー
    └── host_key_dialog.dart           # ホスト鍵確認/警告ダイアログ
```

## セキュリティ

- パスワード・秘密鍵・パスフレーズは **flutter_secure_storage** で暗号化保存（iOS Keychain / Android Keystore）
- ホスト鍵は **TOFU（Trust On First Use）** 方式で検証。鍵変更時は中間者攻撃の警告を表示

## ライセンス

Private
