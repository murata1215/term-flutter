import 'package:flutter/material.dart';

import '../services/ssh_service.dart';

/// ホスト鍵確認ダイアログを表示する
///
/// TOFU（Trust On First Use）方式でホスト鍵を検証するためのダイアログ。
/// 初回接続時はフィンガープリントの確認を求め、
/// 鍵変更時は中間者攻撃の警告を表示する。
///
/// [context] ダイアログを表示するBuildContext
/// [host] 接続先ホスト名
/// [port] 接続先ポート番号
/// [type] 鍵タイプ（例: 'ssh-ed25519'）
/// [fingerprint] サーバーから受信したフィンガープリント
/// [storedFingerprint] 保存済みフィンガープリント（初回接続時は null）
///
/// 戻り値: accept（接続許可）または reject（接続拒否）
Future<HostKeyVerifyResult> showHostKeyDialog({
  required BuildContext context,
  required String host,
  required int port,
  required String type,
  required String fingerprint,
  String? storedFingerprint,
}) async {
  // 初回接続か鍵変更かを判定
  final isFirstConnection = storedFingerprint == null;

  final result = await showDialog<HostKeyVerifyResult>(
    context: context,
    // ダイアログ外タップでは閉じない（明示的な選択を求める）
    barrierDismissible: false,
    builder: (context) {
      if (isFirstConnection) {
        // 初回接続: フィンガープリント確認ダイアログ
        return _FirstConnectionDialog(
          host: host,
          port: port,
          type: type,
          fingerprint: fingerprint,
        );
      } else {
        // 鍵変更: 警告ダイアログ
        return _KeyChangedDialog(
          host: host,
          port: port,
          type: type,
          fingerprint: fingerprint,
          storedFingerprint: storedFingerprint,
        );
      }
    },
  );

  return result ?? HostKeyVerifyResult.reject;
}

/// 初回接続時のフィンガープリント確認ダイアログ
class _FirstConnectionDialog extends StatelessWidget {
  final String host;
  final int port;
  final String type;
  final String fingerprint;

  const _FirstConnectionDialog({
    required this.host,
    required this.port,
    required this.type,
    required this.fingerprint,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          Icon(Icons.vpn_key, color: Colors.greenAccent, size: 24),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'ホスト鍵の確認',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$host:$port に初めて接続します。',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 4),
          const Text(
            'サーバーのフィンガープリントを確認してください。',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 16),
          // 鍵タイプ
          _buildInfoRow('タイプ', type),
          const SizedBox(height: 8),
          // フィンガープリント
          _buildFingerprintBox(fingerprint),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(HostKeyVerifyResult.reject),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(
          onPressed: () =>
              Navigator.of(context).pop(HostKeyVerifyResult.accept),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.greenAccent,
            foregroundColor: Colors.black,
          ),
          child: const Text('接続する'),
        ),
      ],
    );
  }
}

/// 鍵変更時の警告ダイアログ
///
/// 前回と異なるフィンガープリントが検出された場合に表示する。
/// 中間者攻撃（MITM）の可能性があるため、赤い警告UIで注意を促す。
class _KeyChangedDialog extends StatelessWidget {
  final String host;
  final int port;
  final String type;
  final String fingerprint;
  final String storedFingerprint;

  const _KeyChangedDialog({
    required this.host,
    required this.port,
    required this.type,
    required this.fingerprint,
    required this.storedFingerprint,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey[900],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.red, width: 2),
      ),
      title: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.red, size: 28),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'ホスト鍵が変更されました',
              style: TextStyle(color: Colors.red, fontSize: 16),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$host:$port のホスト鍵が前回と異なります。',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withAlpha(25),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.red.withAlpha(76)),
            ),
            child: const Text(
              '中間者攻撃（MITM）の可能性があります。\n'
              'サーバーの鍵が正当に変更された場合を除き、\n'
              '接続しないことを推奨します。',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),
          // 保存済みフィンガープリント
          const Text(
            '前回:',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          _buildFingerprintBox(storedFingerprint),
          const SizedBox(height: 8),
          // 新しいフィンガープリント
          const Text(
            '今回:',
            style: TextStyle(
              color: Colors.orange,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          _buildFingerprintBox('$type:$fingerprint'),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () =>
              Navigator.of(context).pop(HostKeyVerifyResult.reject),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey[700],
            foregroundColor: Colors.white,
          ),
          child: const Text('接続しない'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(HostKeyVerifyResult.accept),
          child: const Text(
            'それでも接続',
            style: TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }
}

/// 情報行（ラベル + 値）を構築するヘルパー
Widget _buildInfoRow(String label, String value) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '$label: ',
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(
            color: Colors.greenAccent,
            fontSize: 13,
            fontFamily: 'monospace',
          ),
        ),
      ),
    ],
  );
}

/// フィンガープリント表示ボックスを構築するヘルパー
Widget _buildFingerprintBox(String fingerprint) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Colors.black,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: Colors.grey[700]!),
    ),
    child: Text(
      fingerprint,
      style: const TextStyle(
        color: Colors.greenAccent,
        fontSize: 11,
        fontFamily: 'monospace',
      ),
    ),
  );
}
