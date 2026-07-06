/// SSH接続情報を保持するデータクラス
///
/// 接続先のホスト情報と認証情報をまとめて管理する。
/// パスワード認証と秘密鍵認証の両方に対応する。
///
/// 保存時は非機密情報（メタデータ）と機密情報（シークレット）を分離する:
/// - メタデータ（name, host, port, username, authType）→ shared_preferences
/// - シークレット（password, privateKey, passphrase）→ flutter_secure_storage
class SshConnectionInfo {
  /// 接続先の表示名（ユーザーが識別するための名前）
  final String name;

  /// 接続先のホスト名またはIPアドレス
  final String host;

  /// 接続先のポート番号（デフォルト: 22）
  final int port;

  /// 認証に使用するユーザー名
  final String username;

  /// 認証方式（'password' または 'key'）
  /// デフォルトは 'password'（後方互換性のため）
  final String authType;

  /// 認証に使用するパスワード（パスワード認証時に使用）
  /// flutter_secure_storage（iOS Keychain / Android Keystore）に暗号化保存
  final String password;

  /// 秘密鍵のPEM文字列（秘密鍵認証時に使用）
  /// flutter_secure_storage に暗号化保存
  final String privateKey;

  /// 秘密鍵のパスフレーズ（任意、パスフレーズ付き秘密鍵の場合に使用）
  /// flutter_secure_storage に暗号化保存
  final String passphrase;

  /// コンストラクタ
  const SshConnectionInfo({
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.authType = 'password',
    this.password = '',
    this.privateKey = '',
    this.passphrase = '',
  });

  /// 秘密鍵認証かどうかを判定するgetter
  bool get isKeyAuth => authType == 'key';

  /// 接続先の概要を表示用文字列として返す
  /// 例: "user@example.com:22"
  String get displayAddress => '$username@$host:$port';

  /// 認証方式の表示用文字列を返す
  String get authTypeLabel => isKeyAuth ? '秘密鍵' : 'パスワード';

  /// 接続先の一意キーを返す
  /// host + port + username の組み合わせで同一接続先かどうかを判定する
  String get uniqueKey => '$username@$host:$port';

  /// メタデータ（非機密情報）のみをJSON（Map）に変換する
  ///
  /// shared_preferences に保存する際に使用する。
  /// パスワード・秘密鍵・パスフレーズは含まない（secure_storage に別途保存）。
  Map<String, dynamic> toMetaJson() {
    return {
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'authType': authType,
    };
  }

  /// シークレット（機密情報）のみをJSON（Map）に変換する
  ///
  /// flutter_secure_storage に保存する際に使用する。
  Map<String, dynamic> toSecretJson() {
    return {
      'password': password,
      'privateKey': privateKey,
      'passphrase': passphrase,
    };
  }

  /// メタデータとシークレットを結合してインスタンスを生成するファクトリ
  ///
  /// [meta] shared_preferences から読み込んだメタデータ
  /// [secret] flutter_secure_storage から読み込んだシークレット（null許容）
  factory SshConnectionInfo.fromMetaAndSecret(
    Map<String, dynamic> meta, [
    Map<String, dynamic>? secret,
  ]) {
    return SshConnectionInfo(
      name: meta['name'] as String? ?? '',
      host: meta['host'] as String? ?? '',
      port: meta['port'] as int? ?? 22,
      username: meta['username'] as String? ?? '',
      authType: meta['authType'] as String? ?? 'password',
      password: secret?['password'] as String? ?? '',
      privateKey: secret?['privateKey'] as String? ?? '',
      passphrase: secret?['passphrase'] as String? ?? '',
    );
  }

  /// JSON（Map）からインスタンスを生成するファクトリコンストラクタ
  ///
  /// マイグレーション用: 旧形式（全情報が1つのJSONに含まれる）からの読み込みに使用。
  /// 新形式では fromMetaAndSecret() を使用する。
  factory SshConnectionInfo.fromJson(Map<String, dynamic> json) {
    return SshConnectionInfo(
      name: json['name'] as String? ?? '',
      host: json['host'] as String? ?? '',
      port: json['port'] as int? ?? 22,
      username: json['username'] as String? ?? '',
      authType: json['authType'] as String? ?? 'password',
      password: json['password'] as String? ?? '',
      privateKey: json['privateKey'] as String? ?? '',
      passphrase: json['passphrase'] as String? ?? '',
    );
  }
}
