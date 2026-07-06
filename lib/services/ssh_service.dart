import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';

import '../models/ssh_connection_info.dart';
import 'host_key_storage_service.dart';

/// ホスト鍵検証の結果を表す列挙型
enum HostKeyVerifyResult {
  /// 接続を許可し、フィンガープリントを保存する
  accept,

  /// 接続を拒否する
  reject,
}

/// ホスト鍵検証コールバックの型定義
///
/// [host] 接続先ホスト名
/// [port] 接続先ポート番号
/// [type] 鍵タイプ（例: 'ssh-ed25519'）
/// [fingerprint] 新しいフィンガープリント（例: 'SHA256:xxxx'）
/// [storedFingerprint] 保存済みフィンガープリント（初回接続時は null）
///
/// 戻り値: accept（接続許可）または reject（接続拒否）
typedef HostKeyVerifyCallback = Future<HostKeyVerifyResult> Function(
  String host,
  int port,
  String type,
  String fingerprint,
  String? storedFingerprint,
);

/// SSH接続を管理するサービスクラス
///
/// dartssh2ライブラリを使用してSSH接続の確立・データ送受信・切断を行う。
/// パスワード認証と秘密鍵認証（ed25519, RSA, ECDSA）の両方に対応する。
/// TOFU方式のホスト鍵検証により中間者攻撃を検知する。
class SshService {
  /// dartssh2のSSHクライアントインスタンス
  SSHClient? _client;

  /// SSHシェルセッション（PTY付き）
  SSHSession? _session;

  /// 現在接続中かどうかを示すフラグ
  bool _isConnected = false;

  /// 意図的な切断かどうかを示すフラグ
  bool _intentionalDisconnect = false;

  /// ホスト鍵ストレージサービス
  final HostKeyStorageService _hostKeyStorage = HostKeyStorageService();

  /// 接続状態を外部から参照するためのgetter
  bool get isConnected => _isConnected;

  /// 外部から設定する切断通知コールバック
  VoidCallback? onDisconnected;

  /// SSH接続を確立し、ターミナルとの入出力を接続する
  ///
  /// [info] SSH接続情報
  /// [terminal] xterm.dartのTerminalオブジェクト
  /// [onHostKeyVerify] ホスト鍵検証コールバック（null の場合は自動承認）
  ///
  /// ホスト鍵検証の流れ:
  /// 1. サーバーからホスト鍵を受信
  /// 2. 保存済みフィンガープリントと照合
  /// 3. 初回 or 変更時: onHostKeyVerify コールバックでUIに確認を求める
  /// 4. 承認された場合: フィンガープリントを保存して接続続行
  /// 5. 拒否された場合: 例外をスローして接続中止
  Future<void> connect(
    SshConnectionInfo info,
    Terminal terminal, {
    HostKeyVerifyCallback? onHostKeyVerify,
  }) async {
    _intentionalDisconnect = false;

    try {
      // TCP接続を確立
      final socket = await SSHSocket.connect(info.host, info.port);

      // ホスト鍵検証コールバックを構築
      // dartssh2 の onVerifyHostKey は FutureOr<bool> を返す
      Future<bool> verifyHostKey(String type, Uint8List fingerprint) async {
        final fingerprintStr = utf8.decode(fingerprint);

        // 保存済みフィンガープリントを取得
        final stored = await _hostKeyStorage.getStoredFingerprint(
          info.host,
          info.port,
        );

        if (stored != null) {
          // 保存済みと一致する場合: 自動承認（ダイアログなし）
          final storedValue = '$type:$fingerprintStr';
          if (stored == storedValue) {
            return true;
          }
        }

        // 初回接続 or 鍵変更: コールバックで確認を求める
        if (onHostKeyVerify != null) {
          // stored から保存済みフィンガープリント文字列を抽出（表示用）
          final storedFpDisplay = stored;

          final result = await onHostKeyVerify(
            info.host,
            info.port,
            type,
            fingerprintStr,
            storedFpDisplay,
          );

          if (result == HostKeyVerifyResult.accept) {
            // 承認: フィンガープリントを保存
            await _hostKeyStorage.saveFingerprint(
              info.host,
              info.port,
              type,
              fingerprintStr,
            );
            return true;
          } else {
            // 拒否
            return false;
          }
        }

        // コールバックが未設定の場合: 自動承認して保存（再接続時など）
        await _hostKeyStorage.saveFingerprint(
          info.host,
          info.port,
          type,
          fingerprintStr,
        );
        return true;
      }

      // 認証方式に応じてSSHクライアントを作成
      if (info.isKeyAuth) {
        final keyPairs = SSHKeyPair.fromPem(
          info.privateKey,
          info.passphrase.isNotEmpty ? info.passphrase : null,
        );

        _client = SSHClient(
          socket,
          username: info.username,
          identities: keyPairs,
          onVerifyHostKey: verifyHostKey,
        );
      } else {
        _client = SSHClient(
          socket,
          username: info.username,
          onPasswordRequest: () => info.password,
          onVerifyHostKey: verifyHostKey,
        );
      }

      // SSHクライアントの done Future を監視
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
  void sendCommand(String command) {
    if (_session == null || !_isConnected) return;
    _session!.stdin.add(utf8.encode('$command\n'));
  }

  /// 生のバイトデータをSSHセッションに送信する
  void sendRawData(Uint8List data) {
    if (_session == null || !_isConnected) return;
    _session!.stdin.add(data);
  }

  /// SSH接続を意図的に切断する
  void disconnect() {
    _intentionalDisconnect = true;
    _isConnected = false;
    _session?.close();
    _client?.close();
    _session = null;
    _client = null;
  }

  /// 再接続のためにリソースをクリーンアップする
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
