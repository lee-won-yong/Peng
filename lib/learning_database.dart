import 'package:flutter/services.dart';

/// SQL is shared by both native SQLite implementations.
class LearningDatabase {
  static const channel = MethodChannel('peng/database');
  static const schema = [
    'CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    'CREATE TABLE IF NOT EXISTS words (word TEXT PRIMARY KEY COLLATE NOCASE CHECK(word = lower(trim(word)) AND length(word) > 0), meaning TEXT NOT NULL, example TEXT NOT NULL, correct INTEGER NOT NULL DEFAULT 0, wrong INTEGER NOT NULL DEFAULT 0)',
    'CREATE TABLE IF NOT EXISTS study_days (date TEXT PRIMARY KEY)',
    'CREATE TABLE IF NOT EXISTS study_day_words (date TEXT NOT NULL REFERENCES study_days(date), word TEXT NOT NULL REFERENCES words(word), PRIMARY KEY(date, word))',
    'CREATE TABLE IF NOT EXISTS quiz_attempts (id INTEGER PRIMARY KEY, word TEXT NOT NULL REFERENCES words(word), study_date TEXT NOT NULL REFERENCES study_days(date), answered_at TEXT NOT NULL, correct INTEGER NOT NULL CHECK(correct IN (0,1)), FOREIGN KEY(study_date,word) REFERENCES study_day_words(date,word))',
  ];

  Map<String, Object?> _statement(
    String sql, [
    List<Object?> args = const [],
  ]) => {'sql': sql, 'args': args};

  Future<void> _batch(List<Map<String, Object?>> statements) async {
    await channel.invokeMethod<void>('batch', statements);
  }

  Future<List<Map<String, Object?>>> _query(String sql) async {
    final rows = await channel.invokeListMethod<dynamic>(
      'query',
      _statement(sql),
    );
    return rows!.map((row) => Map<String, Object?>.from(row as Map)).toList();
  }

  Future<bool> isInitialized() async {
    await _batch(schema.map((sql) => _statement(sql)).toList());
    return (await _query(
      "SELECT value FROM metadata WHERE key = 'legacy_import_v1'",
    )).isNotEmpty;
  }

  Future<void> importLegacy(List<Map<String, Object?>> words) async {
    // The import marker and all rows commit together. A restart cannot import twice.
    await _batch([
      ..._wordStatements(words, importScores: true),
      _statement(
        "INSERT INTO metadata(key,value) VALUES ('legacy_import_v1','1')",
      ),
    ]);
  }

  List<Map<String, Object?>> _wordStatements(
    List<Map<String, Object?>> words, {
    bool importScores = false,
  }) {
    return [
      for (final word in words) ...[
        _statement(
          'INSERT OR IGNORE INTO words(word,meaning,example,correct,wrong) VALUES (?,?,?,?,?)',
          [
            word['word'],
            word['meaning'],
            word['example'],
            word['correct'],
            word['wrong'],
          ],
        ),
        _statement(
          importScores
              ? 'UPDATE words SET meaning=?,example=?,correct=?,wrong=? WHERE word=?'
              : 'UPDATE words SET meaning=?,example=? WHERE word=?',
          [
            word['meaning'],
            word['example'],
            if (importScores) ...[word['correct'], word['wrong']],
            word['word'],
          ],
        ),
        for (final date in word['dates'] as List) ...[
          _statement('INSERT OR IGNORE INTO study_days(date) VALUES (?)', [
            date,
          ]),
          _statement(
            'INSERT OR IGNORE INTO study_day_words(date,word) VALUES (?,?)',
            [date, word['word']],
          ),
        ],
      ],
    ];
  }

  Future<void> saveWords(List<Map<String, Object?>> words) =>
      _batch(_wordStatements(words));

  Future<void> resetLearningData() => _batch([
    _statement('DELETE FROM quiz_attempts'),
    _statement('DELETE FROM study_day_words'),
    _statement('DELETE FROM study_days'),
    _statement('DELETE FROM words'),
    // Keep metadata so a restart cannot restore seed or legacy data.
  ]);

  Future<void> recordAnswer({
    required String word,
    required String date,
    required bool correct,
  }) async {
    await _batch([
      _statement(
        'INSERT INTO quiz_attempts(word,study_date,answered_at,correct) VALUES (?,?,?,?)',
        [word, date, DateTime.now().toUtc().toIso8601String(), correct ? 1 : 0],
      ),
      _statement(
        'UPDATE words SET correct=correct+?, wrong=wrong+? WHERE word=?',
        [correct ? 1 : 0, correct ? 0 : 1, word],
      ),
    ]);
  }

  Future<List<Map<String, Object?>>> loadWords() async {
    final words = await _query(
      'SELECT word,meaning,example,correct,wrong FROM words ORDER BY word',
    );
    final links = await _query(
      'SELECT date,word FROM study_day_words ORDER BY date',
    );
    return [
      for (final word in words)
        {
          ...word,
          'dates': links
              .where((link) => link['word'] == word['word'])
              .map((link) => link['date'])
              .toList(),
        },
    ];
  }

  Future<String?> path() => channel.invokeMethod<String>('path');
}
