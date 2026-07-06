import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ssh_connection_info.dart';

/// 接続先情報の永続化を管理するサービスクラス
///
/// 非機密情報と機密情報を分離して保存する:
/// - **shared_preferences**: メタデータ（name, host, port, username, authType）
/// - **flutter_secure_storage**: シークレット（password, privateKey, passphrase）
///   iOS では Keychain、Android では Keystore + AES暗号化で保護される
///
/// 保存形式:
/// - shared_preferences キー: 'saved_connections' → JSON配列（メタデータのみ）
/// - secure_storage キー: 'secret_{uniqueKey}' → JSON文字列（シークレットのみ）
///
/// マイグレーション:
/// - 旧形式（全情報が shared_preferences に平文保存）からの自動移行に対応
class ConnectionStorageService {
  /// shared_preferences のキー名（メタデータ用）
  static const String _storageKey = 'saved_connections';

  /// secure_storage のキープレフィックス（シークレット用）
  static const String _secretPrefix = 'secret_';

  /// flutter_secure_storage インスタンス
  /// iOS: Keychain に暗号化保存
  /// Android: Keystore + AES暗号化で保存
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// マイグレーション済みかどうかのフラグキー
  static const String _migrationKey = 'secure_storage_migrated';

  /// 保存済みの接続先一覧を読み込む
  ///
  /// 1. shared_preferences からメタデータを読み込む
  /// 2. 各接続先のシークレットを secure_storage から読み込んでマージ
  /// 3. 旧形式データがあれば自動マイグレーション
  ///
  /// 戻り値: 保存済み接続先のリスト（保存順）
  Future<List<SshConnectionInfo>> loadConnections() async {
    final prefs = await SharedPreferences.getInstance();

    // 旧形式からのマイグレーションを実行（未実施の場合のみ）
    if (prefs.getBool(_migrationKey) != true) {
      await _migrateFromLegacy(prefs);
    }

    final jsonString = prefs.getString(_storageKey);
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    try {
      final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;
      final connections = <SshConnectionInfo>[];

      for (final item in jsonList) {
        final meta = item as Map<String, dynamic>;

        // secure_storage からシークレットを読み込む
        final uniqueKey = '${meta['username']}@${meta['host']}:${meta['port']}';
        final secretJson = await _secureStorage.read(
          key: '$_secretPrefix$uniqueKey',
        );

        Map<String, dynamic>? secret;
        if (secretJson != null) {
          try {
            secret = json.decode(secretJson) as Map<String, dynamic>;
          } catch (_) {
            // シークレットのパースエラーは無視
          }
        }

        connections.add(SshConnectionInfo.fromMetaAndSecret(meta, secret));
      }

      return connections;
    } catch (e) {
      return [];
    }
  }

  /// 接続先を保存する
  ///
  /// [info] 保存する接続先情報
  ///
  /// メタデータは shared_preferences に、シークレットは secure_storage に保存する。
  /// 同じ uniqueKey の接続先が既に存在する場合は上書きし、先頭に移動する。
  Future<void> saveConnection(SshConnectionInfo info) async {
    final connections = await loadConnections();

    // 同じ接続先が既に存在する場合は削除（後で先頭に追加するため）
    // 古いシークレットも削除
    for (final c in connections) {
      if (c.uniqueKey == info.uniqueKey) {
        await _secureStorage.delete(key: '$_secretPrefix${c.uniqueKey}');
        break;
      }
    }
    connections.removeWhere((c) => c.uniqueKey == info.uniqueKey);

    // 先頭に追加（最近使った順）
    connections.insert(0, info);

    // メタデータを shared_preferences に保存
    await _saveMetaToPrefs(connections);

    // シークレットを secure_storage に保存
    await _secureStorage.write(
      key: '$_secretPrefix${info.uniqueKey}',
      value: json.encode(info.toSecretJson()),
    );
  }

  /// 接続先を削除する
  ///
  /// [info] 削除する接続先情報
  /// shared_preferences と secure_storage の両方から削除する
  Future<void> deleteConnection(SshConnectionInfo info) async {
    final connections = await loadConnections();
    connections.removeWhere((c) => c.uniqueKey == info.uniqueKey);
    await _saveMetaToPrefs(connections);

    // secure_storage からシークレットを削除
    await _secureStorage.delete(key: '$_secretPrefix${info.uniqueKey}');
  }

  /// メタデータのリストを shared_preferences に保存する内部メソッド
  ///
  /// シークレット情報（password, privateKey, passphrase）は含まない
  Future<void> _saveMetaToPrefs(List<SshConnectionInfo> connections) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = connections.map((c) => c.toMetaJson()).toList();
    await prefs.setString(_storageKey, json.encode(jsonList));
  }

  /// 旧形式（全情報が shared_preferences に平文保存）からの自動マイグレーション
  ///
  /// 旧形式のデータにパスワードや秘密鍵が含まれている場合:
  /// 1. シークレットを secure_storage に移動
  /// 2. shared_preferences からシークレットを除去（メタデータのみ残す）
  /// 3. マイグレーション完了フラグを設定
  Future<void> _migrateFromLegacy(SharedPreferences prefs) async {
    try {
      final jsonString = prefs.getString(_storageKey);
      if (jsonString == null || jsonString.isEmpty) {
        // データなし: マイグレーション完了とする
        await prefs.setBool(_migrationKey, true);
        return;
      }

      final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;
      var needsMigration = false;

      for (final item in jsonList) {
        final data = item as Map<String, dynamic>;
        // 旧形式のデータにシークレットが含まれているかチェック
        final hasSecret = (data['password'] as String?)?.isNotEmpty == true ||
            (data['privateKey'] as String?)?.isNotEmpty == true ||
            (data['passphrase'] as String?)?.isNotEmpty == true;

        if (hasSecret) {
          needsMigration = true;
          // シークレットを secure_storage に移動
          final info = SshConnectionInfo.fromJson(data);
          await _secureStorage.write(
            key: '$_secretPrefix${info.uniqueKey}',
            value: json.encode(info.toSecretJson()),
          );
        }
      }

      if (needsMigration) {
        // shared_preferences をメタデータのみに書き換え
        final metaList = jsonList.map((item) {
          final data = item as Map<String, dynamic>;
          return {
            'name': data['name'],
            'host': data['host'],
            'port': data['port'],
            'username': data['username'],
            'authType': data['authType'] ?? 'password',
          };
        }).toList();
        await prefs.setString(_storageKey, json.encode(metaList));
      }

      // マイグレーション完了フラグを設定
      await prefs.setBool(_migrationKey, true);
    } catch (e) {
      // マイグレーションエラーは無視（次回再試行）
    }
  }
}
