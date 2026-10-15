import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:peng/vocabulary_service.dart';
import 'dart:io';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

http.Response response(
  Object words, {
  String finish = 'stop',
  String? refusal,
}) => http.Response(
  jsonEncode({
    'choices': [
      {
        'finish_reason': finish,
        'message': {
          'content': jsonEncode({'words': words}),
          'refusal': refusal,
        },
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<void> main() async {
  var calls = 0;
  final service = VocabularyService(
    client: MockClient((request) async {
      calls++;
      final body = jsonDecode(request.body) as Map;
      check(
        body['response_format']['json_schema']['strict'] == true,
        'strict schema required',
      );
      return response([
        {'word': ' Alley ', 'meaning': '골목', 'example': 'The alley is narrow.'},
        {'word': 'ALLEY', 'meaning': '골목', 'example': 'I see an alley.'},
      ]);
    }),
  );
  final words = await service.generate(
    text: 'People lined the alley.',
    apiKey: 'fake-test-key',
  );
  check(
    words.length == 1 && words.first['word'] == 'alley',
    'duplicates must be normalized',
  );
  check(words.first['meaning'] == '골목', 'Korean meaning must survive decoding');
  try {
    await service.generate(text: 'alley', apiKey: '');
    throw StateError('missing key accepted');
  } on Exception catch (error) {
    check(error is! StateError, 'missing key must fail');
  }
  check(calls == 1, 'missing key must not send request');
  for (final bad in [
    http.Response('secret error body', 401),
    http.Response('not json', 200),
    response([
      {'word': 'alley', 'meaning': '', 'example': 'An alley.'},
    ]),
    response([], finish: 'length'),
    response([], refusal: 'refused'),
  ]) {
    var failed = false;
    try {
      await VocabularyService(
        client: MockClient((_) async => bad),
      ).generate(text: 'alley', apiKey: 'fake-test-key');
    } catch (error) {
      failed = true;
      check(
        !error.toString().contains('secret error body'),
        'raw API errors must not leak',
      );
    }
    check(failed, 'invalid response accepted');
  }
  stdout.writeln(
    'PASS: generation schema, Korean decoding, normalized deduplication, missing key, HTTP errors, malformed data, empty fields, truncation, refusal.',
  );
}
