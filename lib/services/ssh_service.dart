import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';

import '../models/ssh_connection_info.dart';

/// SSH接続を管理するサービスクラス
///
/// dartssh2ライブラリを使用してSSH接続の確立・データ送受信・切断を行う。
/// パスワード認証と秘密鍵認証（ed25519, RSA, ECDSA）の両方に対応する。
/// 1つのSSHセッション（シェルチャネル）を管理し、
/// xterm.dartのTerminalオブジェクトと連携してターミナル表示を実現する。
///
/// 切断検知:
/// - サーバー側からの切断やネットワーク断を `onDisconnected` コールバックで通知する
/// - dartssh2 の keepAliveInterval（デフォルト10秒）により接続の生存確認が自動で行われる
class SshService {
  /// dartssh2のSSHクライアントインスタンス
  SSHClient? _client;

  /// SSHシェルセッション（PTY付き）
  SSHSession? _session;

  /// 現在接続中かどうかを示すフラグ
  bool _isConnected = false;

  /// 意図的な切断かどうかを示すフラグ
  /// disconnect() が呼ばれた場合は true になり、onDisconnected コールバックを抑制する
  bool _intentionalDisconnect = false;

  /// 接続状態を外部から参照するためのgetter
  bool get isConnected => _isConnected;

  /// 外部から設定する切断通知コールバック
  /// サーバー側からの切断やネットワーク断で呼び出される
  /// 意図的な disconnect() では呼び出されない
  VoidCallback? onDisconnected;

  /// SSH接続を確立し、ターミナルとの入出力を接続する
  ///
  /// [info] SSH接続情報（ホスト、ポート、ユーザー名、認証情報）
  /// [terminal] xterm.dartのTerminalオブジェクト（出力の書き込み先）
  ///
  /// 接続の流れ:
  /// 1. SSHClient でTCP接続を確立
  /// 2. 認証方式に応じてパスワード認証 or 秘密鍵認証を実行
  /// 3. PTY付きのシェルセッションを開始（TERM=xterm-256color）
  /// 4. サーバーからの出力をTerminalに書き込むリスナーを設定
  /// 5. done Future で切断を監視
  ///
  /// 接続失敗時は例外をスローする
  Future<void> connect(SshConnectionInfo info, Terminal terminal) async {
    // 再接続時のためにフラグをリセット
    _intentionalDisconnect = false;

    try {
      // TCP接続を確立
      final socket = await SSHSocket.connect(info.host, info.port);

      // 認証方式に応じてSSHクライアントを作成
      if (info.isKeyAuth) {
        // 秘密鍵認証
        // PEM文字列からSSHKeyPairオブジェクトを生成する
        final keyPairs = SSHKeyPair.fromPem(
          info.privateKey,
          info.passphrase.isNotEmpty ? info.passphrase : null,
        );

        _client = SSHClient(
          socket,
          username: info.username,
          identities: keyPairs,
          // keepAliveInterval はデフォルト10秒で有効
        );
      } else {
        // パスワード認証
        _client = SSHClient(
          socket,
          username: info.username,
          onPasswordRequest: () => info.password,
        );
      }

      // SSHクライアントの done Future を監視
      // サーバー側からの切断やネットワーク断を検知してコールバックを呼ぶ
      _client!.done.then((_) {
        if (!_intentionalDisconnect && _isConnected) {
          _isConnected = false;
          terminal.write('\r\n\x1b[33m--- 切断されました ---\x1b[0m\r\n');
          onDisconnected?.call();
        }
      });

      // PTY付きシェルセッションの開始
      _session = await _client!.shell(
        pty: SSHPtyConfig(
          type: 'xterm-256color',
        ),
      );

      _isConnected = true;

      // サーバーからの出力をターミナルに書き込む
      _session!.stdout.listen(
        (Uint8List data) {
          terminal.write(utf8.decode(data, allowMalformed: true));
        },
        onDone: () {
          // セッション終了時の処理
          // done Future でも検知するため、ここではフラグ更新のみ
          if (_isConnected) {
            _isConnected = false;
            if (!_intentionalDisconnect) {
              terminal.write('\r\n\x1b[33m--- 切断されました ---\x1b[0m\r\n');
              onDisconnected?.call();
            }
          }
        },
        onError: (error) {
          if (_isConnected) {
            _isConnected = false;
            terminal.write('\r\n\x1b[31m[エラー: $error]\x1b[0m\r\n');
            if (!_intentionalDisconnect) {
              onDisconnected?.call();
            }
          }
        },
      );

      // stderr（標準エラー出力）も同様にターミナルに表示
      _session!.stderr.listen(
        (Uint8List data) {
          terminal.write(utf8.decode(data, allowMalformed: true));
        },
      );
    } catch (e) {
      _isConnected = false;
      rethrow;
    }
  }

  /// コマンドをSSHセッションに送信する
  ///
  /// コマンドの末尾に改行（\n）を付与してシェルチャネルに書き込む。
  /// 空文字列の場合は改行のみを送信する。
  void sendCommand(String command) {
    if (_session == null || !_isConnected) return;
    _session!.stdin.add(utf8.encode('$command\n'));
  }

  /// 生のバイトデータをSSHセッションに送信する
  ///
  /// Ctrl+Cや矢印キーなどの制御文字・エスケープシーケンスを送信する際に使用する。
  void sendRawData(Uint8List data) {
    if (_session == null || !_isConnected) return;
    _session!.stdin.add(data);
  }

  /// SSH接続を意図的に切断する
  ///
  /// 意図的な切断のため onDisconnected コールバックは呼ばれない。
  void disconnect() {
    _intentionalDisconnect = true;
    _isConnected = false;
    _session?.close();
    _client?.close();
    _session = null;
    _client = null;
  }

  /// 再接続のためにリソースをクリーンアップする
  ///
  /// disconnect() と異なり、_intentionalDisconnect を設定しない。
  /// 再接続前の古いセッション/クライアントの破棄に使用する。
  void cleanup() {
    _isConnected = false;
    try {
      _session?.close();
    } catch (_) {}
    try {
      _client?.close();
    } catch (_) {}
    _session = null;
    _client = null;
  }
}
