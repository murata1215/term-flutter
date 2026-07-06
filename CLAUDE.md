<!-- DevRelay Agreement v6 -->
See `rules/devrelay.md` for DevRelay rules.
<!-- /DevRelay Agreement -->

---

# term-flutter

> iOS/Android両対応のSSHクライアントアプリ（Flutter製）。表示専用ターミナル + コマンド入力シートの2画面構成。

## ルール参照
- `rules/devrelay.md` - DevRelay 共通ルール
- `rules/project.md` - プロジェクト固有ルール

## 技術スタック

| 項目 | 採用技術 | 備考 |
|---|---|---|
| フレームワーク | Flutter (Dart 3.x) | iOS / Android 両対応 |
| SSH | dartssh2 ^2.10.0 | 純Dart実装、SSH2対応 |
| ターミナル表示 | xterm ^4.0.0 | VT100/xtermエスケープ対応 |
| 状態管理 | flutter_riverpod ^2.6.1 | 導入済み、段階的に活用 |
| ローカル保存 | shared_preferences ^2.3.0 | 接続先メタデータの永続化 |
| セキュア保存 | flutter_secure_storage ^9.2.0 | パスワード・秘密鍵の暗号化保存 |

## ビルド & 実行

```bash
flutter pub get
flutter run          # デバッグ実行
flutter analyze      # 静的解析
flutter test         # テスト実行
```

## 主要ファイル

```
lib/
├── main.dart                          # エントリポイント（ProviderScope）
├── app.dart                           # MaterialApp（ダークテーマ）
├── models/ssh_connection_info.dart    # SSH接続情報データクラス（JSON対応）
├── services/ssh_service.dart          # SSH接続・送受信・ホスト鍵検証
├── services/connection_storage_service.dart  # 接続先の永続化サービス
├── services/host_key_storage_service.dart    # ホスト鍵フィンガープリント保存
├── screens/home_screen.dart           # 接続先一覧 + 新規接続フォーム
├── screens/terminal_screen.dart       # ターミナル表示画面
├── widgets/command_input_bar.dart     # コマンド入力バー（画面下部固定）
└── widgets/host_key_dialog.dart       # ホスト鍵確認/警告ダイアログ
```
