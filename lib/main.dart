import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

/// アプリケーションのエントリポイント
///
/// ProviderScopeでアプリ全体をラップし、Riverpodによる状態管理を有効化する。
/// 現段階（Step 1-2）ではRiverpodの使用箇所は限定的だが、
/// Step 3以降の拡張（接続先管理、設定管理等）に備えて初期段階から導入する。
void main() {
  // Flutter バインディングの初期化を保証
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    // ProviderScope: Riverpodの状態管理ツリーのルート
    // アプリ内のすべてのProviderはこのスコープ内でアクセス可能
    const ProviderScope(
      child: App(),
    ),
  );
}
