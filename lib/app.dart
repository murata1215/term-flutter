import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

/// アプリケーションのルートウィジェット
///
/// MaterialAppの設定を行う。
/// ダークテーマ基調のターミナルらしいデザインを適用する。
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SSH Terminal',
      // デバッグバナーを非表示
      debugShowCheckedModeBanner: false,
      // ダークテーマを基調としたターミナルらしいデザイン
      theme: ThemeData(
        brightness: Brightness.dark,
        // 黒背景にグリーンアクセントのターミナルカラースキーム
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.greenAccent,
          brightness: Brightness.dark,
        ),
        // 全体の背景色を黒に
        scaffoldBackgroundColor: Colors.black,
        // AppBarのスタイル
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        // 等幅フォントをデフォルトに（ターミナルらしさ）
        fontFamily: 'monospace',
      ),
      home: const HomeScreen(),
    );
  }
}
