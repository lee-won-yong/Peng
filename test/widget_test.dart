import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:peng/book_splash.dart';
import 'package:peng/main.dart';
import 'support/database_channel.dart';

void main() {
  setUp(() {
    DatabaseChannelFake().install();
    SharedPreferences.setMockInitialValues({
      'peng_seed_ktv_il_seong_2020_v1': true,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (_) async => 1,
        );
  });

  testWidgets('book splash animates then opens the quiz entry point', (
    tester,
  ) async {
    await tester.pumpWidget(const PengApp());
    expect(find.byType(BookSplash), findsOneWidget);
    expect(find.text('Peng'), findsOneWidget);
    expect(find.byType(StudyDatesPage), findsNothing);
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(BookSplash), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(BookSplash), findsNothing);
    expect(find.byType(StudyDatesPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('book splash respects reduced motion', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: BookSplash(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.text('학습 자료를 불러오고 있어요…'), findsOneWidget);
  });
}
