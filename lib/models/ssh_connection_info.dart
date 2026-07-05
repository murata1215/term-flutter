/// SSH接続情報を保持するデータクラス
///
/// 接続先のホスト情報と認証情報をまとめて管理する。
/// パスワード認証と秘密鍵認証の両方に対応する。
/// shared_preferences に JSON として保存するための
/// シリアライズ/デシリアライズメソッドを持つ。
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
  /// TODO: 将来的に flutter_secure_storage に移行予定
  final String password;

  /// 秘密鍵のPEM文字列（秘密鍵認証時に使用）
  /// OpenSSH形式（-----BEGIN OPENSSH PRIVATE KEY-----）や
  /// PEM形式（-----BEGIN RSA PRIVATE KEY-----）に対応
  final String privateKey;

  /// 秘密鍵のパスフレーズ（任意、パスフレーズ付き秘密鍵の場合に使用）
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

  /// JSON（Map）からインスタンスを生成するファクトリコンストラクタ
  ///
  /// shared_preferences から読み込んだデータを復元する際に使用する。
  /// 旧バージョン（authType未対応）のデータも後方互換性を保って読み込む。
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

  /// インスタンスを JSON（Map）に変換する
  ///
  /// shared_preferences に保存する際に使用する。
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'authType': authType,
      'password': password,
      'privateKey': privateKey,
      'passphrase': passphrase,
    };
  }
}
