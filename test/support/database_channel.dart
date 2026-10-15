import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peng/learning_database.dart';

/// Channel fake for UI tests. Actual SQL is verified by check_learning_sqlite.py.
class DatabaseChannelFake {
  final words = <String, Map<String, Object?>>{};
  final dates = <String, Set<String>>{};
  bool initialized = false;
  bool failImport = false;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LearningDatabase.channel, (call) async {
          if (call.method == 'query') {
            final sql = (call.arguments as Map)['sql'] as String;
            if (sql.contains('FROM metadata')) {
              return initialized
                  ? [
                      {'value': '1'},
                    ]
                  : [];
            }
            if (sql.contains('FROM study_day_words')) {
              return [
                for (final entry in dates.entries)
                  for (final date in entry.value)
                    {'word': entry.key, 'date': date},
              ];
            }
            return words.values.toList();
          }
          final statements = call.arguments as List;
          if (failImport &&
              statements.any(
                (s) => (s['sql'] as String).startsWith('INSERT INTO metadata'),
              )) {
            throw PlatformException(code: 'sqlite');
          }
          for (final raw in statements) {
            final sql = raw['sql'] as String;
            final args = raw['args'] as List;
            if (sql.startsWith('INSERT OR IGNORE INTO words')) {
              words.putIfAbsent(
                args[0] as String,
                () => {
                  'word': args[0],
                  'meaning': args[1],
                  'example': args[2],
                  'correct': args[3],
                  'wrong': args[4],
                },
              );
            } else if (sql.startsWith('UPDATE words SET meaning')) {
              words[args.last]!.addAll({
                'meaning': args[0],
                'example': args[1],
                if (args.length == 5) ...{'correct': args[2], 'wrong': args[3]},
              });
            } else if (sql.startsWith(
              'INSERT OR IGNORE INTO study_day_words',
            )) {
              dates
                  .putIfAbsent(args[1] as String, () => {})
                  .add(args[0] as String);
            } else if (sql.startsWith('INSERT INTO metadata')) {
              initialized = true;
            }
          }
          return null;
        });
  }
}
