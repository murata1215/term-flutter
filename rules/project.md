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
- パスワード/秘密鍵は shared_preferences に平文保存（将来 secure_storage に移行予定）
