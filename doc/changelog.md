# Changelog

## 2026-07-06 — セキュリティ強化（v0.2）

### flutter_secure_storage への移行
- パスワード・秘密鍵・パスフレーズを flutter_secure_storage（iOS Keychain / Android Keystore）で暗号化保存
- 非機密情報（name, host, port, username, authType）は shared_preferences に残す
- 旧形式（平文保存）からの自動マイグレーション対応

### ホスト鍵検証（TOFU）
- TOFU（Trust On First Use）方式でホスト鍵を検証
- 初回接続時: フィンガープリント確認ダイアログを表示
- 2回目以降: 保存済みフィンガープリントと自動照合
- 鍵変更検知: 中間者攻撃の警告ダイアログ（赤枠）を表示
- フィンガープリントは flutter_secure_storage に暗号化保存
- 接続先削除時にホスト鍵も合わせて削除

## 2026-07-06 — 初期実装（v0.1）

### SSH接続
- dartssh2 によるSSH接続（パスワード認証・秘密鍵認証対応）
- ed25519 / RSA / ECDSA の秘密鍵をPEM貼り付けで入力可能
- パスフレーズ付き秘密鍵にも対応
- PTYセッション（TERM=xterm-256color）でシェルチャネルを確立
- keepalive はdartssh2のデフォルト（10秒）で有効

### ターミナル表示
- xterm.dart によるフルスクリーンターミナル表示（VT100/xtermエスケープ対応）
- スクロールバックバッファ 10,000行
- SSH出力が来るたびに自動スクロール（Terminal listener + 50ms debounce + postFrameCallback）
- キーボード表示/非表示時の自動スクロール（didChangeMetrics）

### コマンド入力
- 画面下部固定の入力バー（↑↓ + TextField + 送信ボタン）
- ↑↓ボタンでシェルに矢印キーのエスケープシーケンスを送信（bash履歴ナビゲーション）
- Enter押下時にキーボードが閉じないよう onEditingComplete で制御
- ターミナルタッチでキーボードを閉じ、入力バータッチで再表示
- Ctrl+C ボタンをAppBarに配置

### 接続先管理
- shared_preferences で接続先メタデータを永続化
- SSH接続成功時に自動保存
- ホーム画面に保存済み接続先一覧を表示（タップで即接続）
- スワイプで削除（確認ダイアログ + 取り消し可能）
- 「+」ボタンでモーダル入力フォーム表示

### 再接続
- サーバー側からの切断を自動検知（SSHClient.done + stdout.onDone）
- 切断時にオーバーレイバナー「切断されました [再接続]」を表示
- 入力バーの無効化（切断中）
- アプリ復帰時（WidgetsBindingObserver.resumed）に自動再接続を1回試行
- 再接続は同じTerminalオブジェクトを再利用（出力履歴を保持）

### UI
- ダークテーマ基調（黒背景 + グリーンアクセント）
- AppBar: 接続先名、接続状態インジケーター、C-cボタン、切断ボタン
- 状態管理に flutter_riverpod を導入（ProviderScope）
