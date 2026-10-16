import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peng/main.dart';

void main() {
  testWidgets('settings only edits phone and reset requires confirmation', (
    tester,
  ) async {
    var resets = 0;
    final savedPhones = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => SettingsDialog(
                    initialPhone: '010-1234-5678',
                    onSavedPhone: savedPhones.add,
                    onResetData: () async {
                      resets++;
                      return true;
                    },
                  ),
                ),
                child: const Text('설정 열기'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('설정 열기'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('sk-...'), findsNothing);
    await tester.ensureVisible(find.text('학습 데이터 초기화'));
    await tester.tap(find.text('학습 데이터 초기화'));
    await tester.pumpAndSettle();
    expect(resets, 0);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(resets, 0);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '010-1234-5678',
    );
    await tester.tap(find.text('학습 데이터 초기화'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('초기화'));
    await tester.pumpAndSettle();
    expect(resets, 1);
    expect(savedPhones, isEmpty);
    expect(find.byType(SettingsDialog), findsNothing);
  });
}
