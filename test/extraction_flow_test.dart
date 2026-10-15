import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:peng/main.dart';
import 'support/database_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DatabaseChannelFake database;
  setUp(() {
    database = DatabaseChannelFake()..install();
    SharedPreferences.setMockInitialValues({
      'peng_seed_ktv_il_seong_2020_v1': true,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (_) async => 1,
        );
  });

  testWidgets('missing API key does not register incomplete vocabulary', (
    tester,
  ) async {
    await tester.pumpWidget(const PengApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'Customers once lined the alley.',
    );
    await tester.ensureVisible(find.text('이 문장에서 단어 뽑기'));
    await tester.tap(find.text('이 문장에서 단어 뽑기'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('peng_words_v1'), isNull);
    expect(database.words, isEmpty);
    expect(find.byType(ScanPage), findsOneWidget);
  });

  testWidgets('empty input explains why nothing was extracted', (tester) async {
    await tester.pumpWidget(const PengApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('이 문장에서 단어 뽑기'));
    await tester.tap(find.text('이 문장에서 단어 뽑기'));
    await tester.pumpAndSettle();
    expect(find.byType(ScanPage), findsOneWidget);
    expect(find.text('추출할 영어 단어가 없어요. 영어 문장을 입력해 주세요.'), findsOneWidget);
  });

  testWidgets('seed import preserves existing meanings and quiz scores', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'peng_words_v1': jsonEncode([
        const VocabWord(word: ' Alley ', meaning: '내 뜻', correct: 3).toJson(),
        const VocabWord(word: 'ALLEY', wrong: 2).toJson(),
      ]),
    });
    await tester.pumpWidget(const PengApp());
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final words = database.words.values.toList();
    expect(prefs.getString('peng_words_v1'), isNull);
    expect(words.length, 14);
    final alley = words.singleWhere((entry) => entry['word'] == 'alley');
    expect(alley['meaning'], '내 뜻');
    expect(alley['correct'], 3);
    expect(alley['wrong'], 2);
    expect(alley['example'], isNotEmpty);
    expect(find.byType(StudyDatesPage), findsOneWidget);
    expect(prefs.getBool('peng_seed_ktv_il_seong_2020_v1'), isNull);
    expect(database.initialized, isTrue);
  });
  testWidgets('date cards filter words and allow return to dates', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'peng_seed_ktv_il_seong_2020_v1': true,
      'peng_words_v1': jsonEncode([
        const VocabWord(
          word: 'apple',
          meaning: '사과',
          example: 'An apple.',
          dates: ['2026-10-14'],
        ).toJson(),
        const VocabWord(
          word: 'bird',
          meaning: '새',
          example: 'A bird.',
          dates: ['2026-10-15'],
        ).toJson(),
      ]),
    });
    await tester.pumpWidget(const PengApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Words'));
    await tester.pumpAndSettle();
    expect(find.text('2026-10-14'), findsOneWidget);
    expect(find.text('2026-10-15'), findsOneWidget);
    await tester.tap(find.text('2026-10-14'));
    await tester.pumpAndSettle();
    expect(find.text('apple'), findsOneWidget);
    expect(find.text('bird'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(StudyDatesPage), findsOneWidget);
  });
  testWidgets('migration keeps API key and runs only once', (tester) async {
    SharedPreferences.setMockInitialValues({
      'peng_openai_key_v1': 'unchanged-test-key',
      'peng_words_v1': jsonEncode([
        const VocabWord(
          word: 'alley',
          correct: 3,
          dates: ['2026-10-14'],
        ).toJson(),
      ]),
    });
    await tester.pumpWidget(const PengApp());
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('peng_openai_key_v1'), 'unchanged-test-key');
    expect(prefs.getString('peng_words_v1'), isNull);
    expect(database.words['alley']!['correct'], 3);
    expect(database.dates['alley'], {'2026-10-14'});
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const PengApp());
    await tester.pumpAndSettle();
    expect(database.words['alley']!['correct'], 3);
    expect(prefs.getString('peng_openai_key_v1'), 'unchanged-test-key');
  });

  testWidgets('failed import retains original preferences', (tester) async {
    final original = jsonEncode([
      const VocabWord(word: 'alley', correct: 3).toJson(),
    ]);
    SharedPreferences.setMockInitialValues({'peng_words_v1': original});
    database.failImport = true;
    await tester.pumpWidget(const PengApp());
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('peng_words_v1'), original);
    expect(database.initialized, isFalse);
  });
}
