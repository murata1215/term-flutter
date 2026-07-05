import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ssh_connection_info.dart';

/// 接続先情報の永続化を管理するサービスクラス
///
/// shared_preferences を使用して接続先情報を JSON 配列として保存する。
/// 接続成功時に自動的に保存され、次回起動時に復元される。
///
/// 保存形式:
/// - キー: 'saved_connections'
/// - 値: JSON配列の文字列（各要素は SshConnectionInfo の JSON）
///
/// 重複判定:
/// - host + port + username の組み合わせ（uniqueKey）で同一接続先を判定
/// - 同じ接続先を再度保存すると、既存のエントリを上書き（最新情報に更新）
class ConnectionStorageService {
  /// shared_preferences のキー名
  static const String _storageKey = 'saved_connections';

  /// 保存済みの接続先一覧を読み込む
  ///
  /// 戻り値: 保存済み接続先のリスト（保存順）
  /// データが存在しない場合やパースエラー時は空リストを返す
  Future<List<SshConnectionInfo>> loadConnections() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey);

    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    try {
      // JSON文字列をデコードしてリストに変換
      final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;
      return jsonList
          .map((item) =>
              SshConnectionInfo.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // パースエラー時は空リストを返す（データ破損時の安全策）
      return [];
    }
  }

  /// 接続先を保存する
  ///
  /// [info] 保存する接続先情報
  ///
  /// 同じ uniqueKey（host+port+username）の接続先が既に存在する場合は
  /// 既存のエントリを上書きする（名前やパスワードが更新される可能性があるため）。
  /// 新規の場合はリストの先頭に追加する（最近使った順）。
  Future<void> saveConnection(SshConnectionInfo info) async {
    final connections = await loadConnections();

    // 同じ接続先が既に存在する場合は削除（後で先頭に追加するため）
    connections.removeWhere((c) => c.uniqueKey == info.uniqueKey);

    // 先頭に追加（最近使った順）
    connections.insert(0, info);

    // JSON文字列に変換して保存
    await _saveToPrefs(connections);
  }

  /// 接続先を削除する
  ///
  /// [info] 削除する接続先情報
  /// uniqueKey で一致する接続先を削除する
  Future<void> deleteConnection(SshConnectionInfo info) async {
    final connections = await loadConnections();
    connections.removeWhere((c) => c.uniqueKey == info.uniqueKey);
    await _saveToPrefs(connections);
  }

  /// 接続先リストを shared_preferences に保存する内部メソッド
  Future<void> _saveToPrefs(List<SshConnectionInfo> connections) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = connections.map((c) => c.toJson()).toList();
    await prefs.setString(_storageKey, json.encode(jsonList));
  }
}
