import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../models/ssh_connection_info.dart';
import '../services/ssh_service.dart';
import '../widgets/command_input_bar.dart';

/// ターミナル画面
///
/// SSH接続先の出力を表示する全画面ターミナル。
/// xterm.dartのTerminalViewを使用して、VT100/xtermのエスケープシーケンスに対応した
/// リッチなターミナル表示を実現する。
///
/// 画面構成:
/// - 上部: AppBar（接続先名、接続状態、切断ボタン）
/// - 中央: TerminalView（SSH出力表示、タップでキーボード表示）
///   - 切断時: オーバーレイバナー（再接続ボタン付き）
/// - 下部: CommandInputBar（固定の入力バー、切断時は無効化）
///
/// 再接続機能:
/// - サーバー側からの切断を自動検知し、再接続ボタンを表示
/// - アプリがバックグラウンドから復帰した際に、切断済みなら自動再接続を試行
/// - 再接続は新しいシェルセッションとして開始（既存のターミナル出力は保持）
class TerminalScreen extends StatefulWidget {
  /// SSH接続情報
  final SshConnectionInfo connectionInfo;

  /// 接続成功時に呼び出されるコールバック
  /// ホーム画面で接続先を保存するために使用する
  final VoidCallback? onConnectionSuccess;

  const TerminalScreen({
    super.key,
    required this.connectionInfo,
    this.onConnectionSuccess,
  });

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen>
    with WidgetsBindingObserver {
  /// xterm.dartのTerminalオブジェクト
  /// SSH出力の書き込み先であり、TerminalViewの表示データソース
  /// 再接続時もこのオブジェクトを再利用し、既存出力を保持する
  late final Terminal _terminal;

  /// SSH接続サービス
  final SshService _sshService = SshService();

  /// TerminalView のスクロール制御用コントローラー
  final ScrollController _scrollController = ScrollController();

  /// コマンド入力バーのフォーカスノード
  final FocusNode _inputFocusNode = FocusNode();

  /// 初回接続処理中かどうか（ローディング画面の表示用）
  bool _isConnecting = true;

  /// 初回接続エラーメッセージ（エラー発生時にnull以外）
  String? _errorMessage;

  /// SSH切断状態（サーバー側からの切断を検知した場合に true）
  /// 初回接続失敗（_errorMessage != null）とは別の状態
  bool _isDisconnected = false;

  /// 再接続処理中かどうか（オーバーレイのローディング表示用）
  bool _isReconnecting = false;

  /// 再接続エラーメッセージ（再接続失敗時にnull以外）
  String? _reconnectError;

  /// 自動スクロールの debounce 用タイマー
  /// Terminal の listener は1文字ごとに呼ばれる可能性があるため、
  /// 16ms（≒1フレーム）の debounce でパフォーマンスを確保する
  Timer? _scrollDebounceTimer;

  @override
  void initState() {
    super.initState();

    // ライフサイクル監視を登録（アプリ復帰時の自動再接続用）
    WidgetsBinding.instance.addObserver(this);

    // ターミナルオブジェクトの初期化
    _terminal = Terminal(maxLines: 10000);

    // ターミナル出力の変更を監視して自動スクロールする
    // SSH出力が来るたびに listener が呼ばれ、最下部にスクロールする
    _terminal.addListener(_onTerminalOutput);

    // SSH接続サービスの切断コールバックを設定
    _sshService.onDisconnected = _onDisconnected;

    // SSH接続を開始
    _connectSsh();
  }

  /// アプリのライフサイクル変化を監視する
  ///
  /// iOSでバックグラウンドに入るとSSH接続が切断されるため、
  /// resumed（フォアグラウンドに復帰）時に切断済みなら自動再接続を試みる。
  /// 自動再接続は1回のみ試行し、失敗した場合は手動再接続ボタンにフォールバックする。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // アプリ復帰時: 切断済みかつ再接続中でなければ自動再接続を試行
      if (_isDisconnected && !_isReconnecting) {
        _reconnect();
      }
    }
  }

  /// キーボード表示/非表示などのメトリクス変化を検知する
  ///
  /// キーボードが表示されるとビューポートサイズが変わり、
  /// xterm の _stickToBottom が false になってしまう場合がある。
  /// レイアウト完了後にスクロールを最下部に合わせることで、
  /// キーボード表示後も最新出力が見えるようにする。
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  /// サーバー側からの切断を検知した際のコールバック
  ///
  /// UI状態を更新して切断オーバーレイを表示し、入力バーを無効化する。
  /// このコールバックは意図的な disconnect() では呼ばれない。
  void _onDisconnected() {
    if (mounted) {
      setState(() {
        _isDisconnected = true;
        _reconnectError = null;
      });
    }
  }

  /// SSH接続を非同期で実行する（初回接続用）
  ///
  /// 接続成功時: ローディングを解除してターミナル表示に切り替え
  /// 接続失敗時: エラーメッセージを表示
  Future<void> _connectSsh() async {
    try {
      await _sshService.connect(widget.connectionInfo, _terminal);

      // 接続成功コールバックを呼び出し（接続先の自動保存用）
      widget.onConnectionSuccess?.call();

      if (mounted) {
        setState(() {
          _isConnecting = false;
          _isDisconnected = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  /// 再接続を実行する
  ///
  /// 切断済みの状態から同じ接続情報を使って新しいセッションを確立する。
  /// 成功: ターミナルに再接続メッセージを出力し、入力バーを再有効化
  /// 失敗: エラーメッセージを表示し、再試行ボタンを維持
  ///
  /// 既存のターミナル出力（Terminal オブジェクト）は保持され、
  /// 新しいセッションの出力が続けて表示される。
  Future<void> _reconnect() async {
    if (_isReconnecting) return;

    setState(() {
      _isReconnecting = true;
      _reconnectError = null;
    });

    // 古いセッション/クライアントをクリーンアップ
    _sshService.cleanup();

    try {
      // 同じターミナルオブジェクトに接続（出力が続けて表示される）
      await _sshService.connect(widget.connectionInfo, _terminal);

      // 再接続成功メッセージをターミナルに出力（黄色で目立たせる）
      _terminal.write('\r\n\x1b[32m--- 再接続しました ---\x1b[0m\r\n');

      if (mounted) {
        setState(() {
          _isDisconnected = false;
          _isReconnecting = false;
          _reconnectError = null;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isReconnecting = false;
          _reconnectError = e.toString();
        });
      }
    }
  }

  /// Terminal の出力変更を検知して自動スクロールする
  ///
  /// SSH出力が来るたびに呼ばれる。
  /// 50ms の debounce で出力の塊が終わるのを待ち、
  /// さらに addPostFrameCallback でレイアウト完了後にスクロールする。
  /// これにより xterm の performLayout() で maxScrollExtent が確定した後に
  /// 正しい位置にスクロールできる。
  void _onTerminalOutput() {
    _scrollDebounceTimer?.cancel();
    _scrollDebounceTimer = Timer(const Duration(milliseconds: 50), () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    });
  }

  /// ターミナルを最下部にスクロールする
  ///
  /// コマンド送信後やキーボード表示時に明示的に呼び出す。
  /// _onTerminalOutput の debounce とは別に、即座のスクロールも行う。
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  /// コマンドをSSHセッションに送信する
  void _sendCommand(String command) {
    _sshService.sendCommand(command);
    _scrollToBottom();
  }

  /// Ctrl+C（SIGINT）をSSHセッションに送信する
  void _sendCtrlC() {
    _sshService.sendRawData(Uint8List.fromList([3]));
  }

  /// シェルに矢印キー上を送信する（bash履歴ナビゲーション）
  void _sendArrowUp() {
    _sshService.sendRawData(Uint8List.fromList([0x1b, 0x5b, 0x41]));
    _scrollToBottom();
  }

  /// シェルに矢印キー下を送信する（bash履歴ナビゲーション）
  void _sendArrowDown() {
    _sshService.sendRawData(Uint8List.fromList([0x1b, 0x5b, 0x42]));
    _scrollToBottom();
  }

  /// ターミナル部分をタッチした時にキーボードを閉じる
  ///
  /// フォーカスを外すことでOSキーボードが非表示になる。
  /// 入力バーの TextField をタップすれば再びキーボードが表示される。
  void _unfocusInput() {
    _inputFocusNode.unfocus();
  }

  /// SSH切断してホーム画面に戻る（意図的な切断）
  void _disconnect() {
    _sshService.disconnect();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    // Terminal の出力変更リスナーを解除
    _terminal.removeListener(_onTerminalOutput);
    // debounce タイマーをキャンセル
    _scrollDebounceTimer?.cancel();
    // ライフサイクル監視を解除
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _sshService.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 現在の接続状態に応じたインジケーター色を決定
    final indicatorColor = _isDisconnected || _isReconnecting
        ? (_isReconnecting ? Colors.orange : Colors.red)
        : (_sshService.isConnected ? Colors.greenAccent : Colors.red);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.connectionInfo.name,
              style: const TextStyle(fontSize: 16, color: Colors.white),
            ),
            Text(
              widget.connectionInfo.displayAddress,
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
          ],
        ),
        actions: [
          // Ctrl+C 送信ボタン（実行中コマンドの中断用）
          // 接続中のみ有効
          if (!_isConnecting && _errorMessage == null && !_isDisconnected)
            SizedBox(
              width: 36,
              height: 28,
              child: ElevatedButton(
                onPressed: _sendCtrlC,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[700],
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                child: const Text(
                  'C-c',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 4),
          // 接続状態インジケーター
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(
              Icons.circle,
              size: 12,
              color: indicatorColor,
            ),
          ),
          // 切断ボタン
          IconButton(
            onPressed: _disconnect,
            icon: const Icon(Icons.logout, color: Colors.white70),
            tooltip: '切断',
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: _buildBody(),
    );
  }

  /// 画面本体を構築する
  Widget _buildBody() {
    // 初回接続中のローディング表示
    if (_isConnecting) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.greenAccent),
            const SizedBox(height: 16),
            Text(
              '${widget.connectionInfo.displayAddress} に接続中...',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    // 初回接続エラー表示
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              const Text(
                '接続に失敗しました',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _isConnecting = true;
                    _errorMessage = null;
                  });
                  _connectSsh();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('再試行'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[800],
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ターミナル表示 + 入力バー
    // 切断時はオーバーレイバナーを表示し、入力バーを無効化
    return Column(
      children: [
        // ターミナル表示領域 + 切断オーバーレイ
        Expanded(
          child: Stack(
            children: [
              // ターミナルビュー
              // タップでキーボードを閉じる（入力バーをタッチすれば再び開く）
              GestureDetector(
                onTap: _unfocusInput,
                child: TerminalView(
                  _terminal,
                  readOnly: true,
                  scrollController: _scrollController,
                  textStyle: const TerminalStyle(
                    fontSize: 14,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              // 切断時のオーバーレイバナー
              if (_isDisconnected) _buildDisconnectedOverlay(),
            ],
          ),
        ),
        // 固定入力バー（切断時は無効化）
        CommandInputBar(
          onCommandSubmit: _sendCommand,
          onHistoryUp: _sendArrowUp,
          onHistoryDown: _sendArrowDown,
          focusNode: _inputFocusNode,
          enabled: !_isDisconnected,
        ),
      ],
    );
  }

  /// 切断時のオーバーレイバナーを構築する
  ///
  /// ターミナルビューの下部中央に表示されるバナー。
  /// 再接続ボタンと、再接続中のローディングインジケーターを含む。
  /// 再接続エラー時はエラーメッセージも表示する。
  Widget _buildDisconnectedOverlay() {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          // 半透明の暗い背景でターミナル上に表示
          color: Colors.grey[900]!.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _reconnectError != null ? Colors.red : Colors.orange,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 切断/再接続中メッセージ
            Row(
              children: [
                Icon(
                  _isReconnecting
                      ? Icons.sync
                      : Icons.link_off,
                  color: _isReconnecting ? Colors.orange : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isReconnecting ? '再接続中...' : '切断されました',
                    style: TextStyle(
                      color: _isReconnecting ? Colors.orange : Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                // 再接続ボタン（再接続中はローディングインジケーター）
                if (_isReconnecting)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.orange,
                    ),
                  )
                else
                  ElevatedButton(
                    onPressed: _reconnect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: const Text(
                      '再接続',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
            // 再接続エラーメッセージ
            if (_reconnectError != null) ...[
              const SizedBox(height: 8),
              Text(
                _reconnectError!,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
