import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:peng/ar_level.dart';
import 'package:peng/main.dart';
import 'package:peng/vocabulary_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/database_channel.dart';

void main() {
  test('AR range persists and corrupt settings use the default', () {
    final restored = ArLevelRange.decode(const ArLevelRange(5, 7).encode());
    expect(restored.minimum, 5);
    expect(restored.maximum, 7);
    for (final invalid in [null, '', '{}', 'null',
      '{"minimum":9,"maximum":3}', '{"minimum":0,"maximum":99}']) {
      expect(ArLevelRange.decode(invalid).label, 'AR 3.0–5.0');
    }
  });

  test('selected AR range reaches API and phrasal verbs survive decoding', () async {
    final requests = <String>[];
    final service = VocabularyService(client: MockClient((request) async {
      final body = jsonDecode(request.body) as Map;
      requests.add(body['messages'][0]['content'] as String);
      return http.Response(jsonEncode({'choices': [{
        'finish_reason': 'stop',
        'message': {'content': jsonEncode({'words': [{
          'word': ' Carry   Out ',
          'meaning': '수행하다',
          'example': 'The researchers carry out experiments to test their predictions.',
        }]})},
      }]}), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    final result = await service.generate(text: 'Researchers carry out experiments.',
      apiKey: 'fake-test-key', arLevel: const ArLevelRange(5, 7));
    await service.generate(text: 'Researchers carry out experiments.',
      apiKey: 'fake-test-key', arLevel: const ArLevelRange(1, 2));
    expect(requests[0], contains('AR 5.0–7.0'));
    expect(requests[0], contains('12–22 words'));
    expect(requests[1], contains('AR 1.0–2.0'));
    expect(requests[1], contains('5–9 words'));
    expect(result.single['word'], 'carry out');
    expect(result.single['meaning'], '수행하다');
  });

  testWidgets('settings saves AR selection and restores it after restart', (tester) async {
    rootBundle.evict('assets/data/il_seong_interview.json');
    DatabaseChannelFake().install();
    SharedPreferences.setMockInitialValues({
      'peng_seed_ktv_il_seong_2020_v1': true,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('flutter_tts'), (_) async => 1);
    await tester.pumpWidget(const PengApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    expect(find.text('AR 3.0–5.0'), findsOneWidget);
    final sliderRect = tester.getRect(find.byType(RangeSlider));
    await tester.tapAt(Offset(sliderRect.right - 24, sliderRect.center.dy));
    await tester.pumpAndSettle();
    final selected = tester.widget<RangeSlider>(find.byType(RangeSlider)).values;
    expect(selected.end, greaterThan(5));
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final saved = ArLevelRange.decode(prefs.getString('peng_ar_level_v1'));
    expect(saved.minimum, selected.start);
    expect(saved.maximum, selected.end);
    await tester.pumpWidget(const SizedBox.shrink());
    rootBundle.evict('assets/data/il_seong_interview.json');
    await tester.pumpWidget(const PengApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    expect(find.text(saved.label), findsOneWidget);
    expect(find.text('sk-...'), findsNothing);
  });
}
