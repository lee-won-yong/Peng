import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peng/main.dart';

void main() {
  testWidgets(
    'reset requires confirmation and does not save or change the API key',
    (tester) async {
      var resets = 0;
      final savedKeys = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => ApiKeyDialog(
                      initialKey: 'existing-key',
                      initialPhone: '',
                      onSaved: savedKeys.add,
                      onSavedPhone: (_) {},
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
      await tester.ensureVisible(find.text('학습 데이터 초기화'));
      await tester.tap(find.text('학습 데이터 초기화'));
      await tester.pumpAndSettle();
      expect(resets, 0);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(resets, 0);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'existing-key',
      );
      await tester.tap(find.text('학습 데이터 초기화'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('초기화'));
      await tester.pumpAndSettle();
      expect(resets, 1);
      expect(savedKeys, isEmpty);
      expect(find.byType(ApiKeyDialog), findsNothing);
    },
  );
}
