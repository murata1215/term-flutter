# プロジェクト固有ルール

## 設計判断

### ターミナル入力方式
- 入力は画面下部の固定バー（TextField + OSキーボード）で行う
- 自作キーパッドは不要（標準キーボードで十分）
- ターミナル部分をタッチ → キーボードを閉じる / 入力バーをタッチ → キーボードを開く

### 履歴ナビゲーション
- ↑↓ボタンはシェルに矢印キーのエスケープシーケンス（\x1b[A / \x1b[B）を直接送信
- アプリ内での bash_history 管理は行わない（bashのreadlineに委ねる）
- su後のユーザーの履歴にもそのまま対応できる

### コマンド送信
- sendCommand() はシンプルに `command\n` を送信するだけ
- readline バッファのクリア（Ctrl+U等）は行わない（パスワード入力等に副作用があるため）
- ↑↓で展開したコマンドの後ろにテキストが追加される問題は仕様として許容

### 自動スクロール
- Terminal の addListener で出力変更を監視し、50ms debounce + addPostFrameCallback でスクロール
- didChangeMetrics でキーボード表示/非表示のリサイズを検知してスクロール補正
- xterm内部の _stickToBottom に依存せず、外部から ScrollController.jumpTo で制御

### キーボード制御
- onEditingComplete を上書きしてフォーカス維持（キーボードのチラつき防止）
- TextInputAction.send のまま、onSubmitted は使わない

### 再接続
- SSHClient.done Future と stdout.onDone の両方で切断を検知
- 意図的な disconnect() では onDisconnected コールバックを呼ばない（_intentionalDisconnect フラグ）
- 再接続時は cleanup() で古いリソースを破棄してから connect()
- 同じ Terminal オブジェクトを再利用し、出力履歴を保持

### 接続先保存
- 接続成功時に自動保存（接続前ではなく成功後）
- host + port + username の組み合わせで重複判定

### セキュリティ: 機密情報の保存
- パスワード・秘密鍵・パスフレーズは flutter_secure_storage に暗号化保存
- 非機密情報（name, host, port, username, authType）は shared_preferences
- 旧形式（平文保存）からの自動マイグレーション対応

### セキュリティ: ホスト鍵検証（TOFU）
- TOFU（Trust On First Use）方式でホスト鍵を管理
- 初回接続: ダイアログでフィンガープリントを確認 → 承認で保存
- 2回目以降: 保存済みと自動照合 → 一致なら自動接続
- 鍵変更: 赤枠の警告ダイアログ（中間者攻撃の可能性）
- 再接続時はコールバックなし（保存済みなら自動承認）
- 接続先削除時にホスト鍵フィンガープリントも合わせて削除
- フィンガープリントは flutter_secure_storage に暗号化保存
