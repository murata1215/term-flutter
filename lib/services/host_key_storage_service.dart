import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// ホスト鍵フィンガープリントの永続化を管理するサービスクラス
///
/// TOFU（Trust On First Use）方式でホスト鍵を管理する:
/// - 初回接続時にフィンガープリントを保存
/// - 2回目以降は保存済みフィンガープリントと照合
/// - 鍵が変更された場合は中間者攻撃の警告を表示
///
/// flutter_secure_storage を使用して暗号化保存する。
/// キー形式: `hostkey_{host}:{port}`
/// 値形式: `{type}:{fingerprint}`（例: `ssh-ed25519:SHA256:xxxx`）
class HostKeyStorageService {
  /// secure_storage のキープレフィックス
  static const String _prefix = 'hostkey_';

  /// flutter_secure_storage インスタンス
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// 保存済みホスト鍵フィンガープリントを取得する
  ///
  /// [host] ホスト名またはIPアドレス
  /// [port] ポート番号
  ///
  /// 戻り値: 保存済みの値（`type:fingerprint` 形式）。未保存の場合は null
  Future<String?> getStoredFingerprint(String host, int port) async {
    final key = '$_prefix$host:$port';
    return await _secureStorage.read(key: key);
  }

  /// ホスト鍵フィンガープリントを保存する
  ///
  /// [host] ホスト名またはIPアドレス
  /// [port] ポート番号
  /// [type] 鍵タイプ（例: 'ssh-ed25519', 'ssh-rsa'）
  /// [fingerprint] SHA256フィンガープリント文字列（例: 'SHA256:xxxx'）
  Future<void> saveFingerprint(
    String host,
    int port,
    String type,
    String fingerprint,
  ) async {
    final key = '$_prefix$host:$port';
    await _secureStorage.write(key: key, value: '$type:$fingerprint');
  }

  /// ホスト鍵フィンガープリントを削除する
  ///
  /// [host] ホスト名またはIPアドレス
  /// [port] ポート番号
  ///
  /// 接続先を削除する際に合わせて呼び出す
  Future<void> deleteFingerprint(String host, int port) async {
    final key = '$_prefix$host:$port';
    await _secureStorage.delete(key: key);
  }
}
