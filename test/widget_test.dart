import 'package:flutter_test/flutter_test.dart';
import 'package:leetcode_daily_bot/main.dart';

void main() {
  testWidgets('shows the daily challenge button', (tester) async {
    await tester.pumpWidget(const LeetCodeBotApp());

    expect(find.text('LeetCode Daily Bot'), findsOneWidget);
    expect(find.text('Solve today’s challenge'), findsOneWidget);
  });
}
