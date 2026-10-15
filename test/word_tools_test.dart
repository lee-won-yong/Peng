import 'package:flutter_test/flutter_test.dart';
import 'package:peng/main.dart';

void main() {
  test('extractWords removes common stop words and duplicates', () {
    final words = extractWords(
      'The little rabbit and the Little Bird are running to school.',
    );

    expect(
      words,
      containsAll(<String>['little', 'rabbit', 'bird', 'running', 'school']),
    );
    expect(words.where((word) => word == 'little').length, 1);
    expect(words, isNot(contains('the')));
    expect(words, isNot(contains('and')));
  });
}
