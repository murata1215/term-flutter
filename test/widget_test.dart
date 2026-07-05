// SSHターミナルアプリの基本ウィジェットテスト

import 'package:flutter_test/flutter_test.dart';

import 'package:term_flutter/app.dart';

void main() {
  testWidgets('ホーム画面が正しく表示される', (WidgetTester tester) async {
    // アプリを起動
    await tester.pumpWidget(const App());
    // フレームを進めて非同期処理の結果を反映
    await tester.pump();

    // AppBarのタイトルが表示されていることを確認
    expect(find.text('SSH Terminal'), findsOneWidget);
  });
}
