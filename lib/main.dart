import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'vocabulary_service.dart';
import 'learning_database.dart';

void main() {
  runApp(const PengApp());
}

const _storageKey = 'peng_words_v1';
const _apiKeyStorageKey = 'peng_openai_key_v1';
const _parentPhoneStorageKey = 'peng_parent_phone_v1';
const _completedDatesStorageKey = 'peng_completed_dates_v1';
const _openAiModel = 'gpt-4o-mini';

const _stopWords = <String>{
  'a',
  'an',
  'and',
  'are',
  'as',
  'at',
  'be',
  'but',
  'by',
  'for',
  'from',
  'has',
  'he',
  'her',
  'his',
  'i',
  'in',
  'is',
  'it',
  'its',
  'me',
  'my',
  'of',
  'on',
  'or',
  'our',
  'she',
  'that',
  'the',
  'their',
  'they',
  'this',
  'to',
  'was',
  'we',
  'were',
  'with',
  'you',
  'your',
};

List<String> extractWords(String text) {
  final matches = RegExp(r"[A-Za-z][A-Za-z'-]{2,}").allMatches(text);
  final seen = <String>{};
  final words = <String>[];

  for (final match in matches) {
    final word = match
        .group(0)!
        .toLowerCase()
        .replaceAll(RegExp(r"(^'|'$)"), '');
    if (_stopWords.contains(word) || seen.contains(word)) {
      continue;
    }
    seen.add(word);
    words.add(word);
  }

  words.sort();
  return words;
}

String studyDateToday() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

class VocabWord {
  const VocabWord({
    required this.word,
    this.meaning = '',
    this.example = '',
    this.correct = 0,
    this.wrong = 0,
    this.dates = const [],
  });

  final String word;
  final String meaning;
  final String example;
  final int correct;
  final int wrong;
  final List<String> dates;

  VocabWord copyWith({
    String? meaning,
    String? example,
    int? correct,
    int? wrong,
    List<String>? dates,
  }) {
    return VocabWord(
      word: word,
      meaning: meaning ?? this.meaning,
      example: example ?? this.example,
      correct: correct ?? this.correct,
      wrong: wrong ?? this.wrong,
      dates: dates ?? this.dates,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'word': word,
      'meaning': meaning,
      'example': example,
      'correct': correct,
      'wrong': wrong,
      'dates': dates,
    };
  }

  factory VocabWord.fromJson(Map<String, Object?> json) {
    return VocabWord(
      word: (json['word'] as String).trim().toLowerCase(),
      meaning: json['meaning'] as String? ?? '',
      example: json['example'] as String? ?? '',
      correct: json['correct'] as int? ?? 0,
      wrong: json['wrong'] as int? ?? 0,
      dates: (json['dates'] is List && (json['dates'] as List).isNotEmpty)
          ? (json['dates'] as List).cast<String>().toSet().toList()
          : [studyDateToday()],
    );
  }
}

class PengApp extends StatelessWidget {
  const PengApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Peng',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff1f7a8c),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xfff7fbfb),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _database = LearningDatabase();
  bool _databaseReady = false;
  bool _isResettingData = false;
  final _picker = ImagePicker();
  final _tts = FlutterTts();
  final _textController = TextEditingController();

  List<VocabWord> _words = <VocabWord>[];
  bool _isScanning = false;
  String? _preparationMessage;
  bool _isLoadingWords = true;
  int _selectedIndex = 2;
  String? _selectedStudyDate;
  String? _statusMessage;
  String _apiKey = '';
  String _parentPhone = '';
  Set<String> _completedDates = <String>{};

  @override
  void initState() {
    super.initState();
    _initializeLearning();
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.42);
  }

  @override
  void dispose() {
    _textController.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _initializeLearning() async {
    try {
      await _loadApiKey();
    } catch (_) {
      _showStatus('설정을 불러오지 못했어요.');
    }
    if (!mounted) return;
    await _loadWords();
    if (mounted) await _completeMissingWords();
  }

  Future<void> _completeMissingWords() async {
    final missing = _words
        .where((word) => word.meaning.isEmpty || word.example.isEmpty)
        .toList();
    if (!_databaseReady ||
        _isResettingData ||
        missing.isEmpty ||
        _apiKey.isEmpty ||
        _isScanning) {
      return;
    }
    await _mergeExtractedWords(
      missing.map((word) => word.word).join(', '),
      openQuiz: false,
    );
  }

  Future<void> _loadWords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final initialized = await _database.isInitialized();
      final raw = initialized ? null : prefs.getString(_storageKey);
      final decoded = initialized
          ? await _database.loadWords()
          : (raw == null ? <dynamic>[] : jsonDecode(raw) as List<dynamic>);
      final words = decoded
          .map(
            (json) =>
                VocabWord.fromJson(Map<String, Object?>.from(json as Map)),
          )
          .toList();
      const seedKey = 'peng_seed_ktv_il_seong_2020_v1';
      final seed =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/data/il_seong_interview.json',
                ),
              )
              as Map<String, dynamic>;
      final existing = <String, VocabWord>{};
      for (final word in words) {
        final old = existing[word.word];
        existing[word.word] = old == null
            ? word
            : old.copyWith(
                meaning: old.meaning.isEmpty ? word.meaning : old.meaning,
                example: old.example.isEmpty ? word.example : old.example,
                correct: old.correct + word.correct,
                wrong: old.wrong + word.wrong,
                dates: {...old.dates, ...word.dates}.toList(),
              );
      }
      for (final json in seed['words'] as List<dynamic>) {
        final word = VocabWord.fromJson(Map<String, Object?>.from(json as Map));
        final old = existing[word.word];
        if (old != null) {
          existing[word.word] = old.copyWith(
            meaning: old.meaning.isEmpty ? word.meaning : old.meaning,
            example: old.example.isEmpty ? word.example : old.example,
          );
        } else if (!initialized && prefs.getBool(seedKey) != true) {
          existing[word.word] = word;
        }
      }
      words
        ..clear()
        ..addAll(existing.values);
      final rows = words.map((word) => word.toJson()).toList();
      if (initialized) {
        await _database.saveWords(rows);
      } else {
        await _database.importLegacy(rows);
      }
      final persisted = await _database.loadWords();
      if (persisted.length != words.length) throw StateError('데이터 이관 확인 실패');
      for (final row in persisted) {
        final actual = VocabWord.fromJson(row);
        final expected = existing[actual.word];
        if (expected == null ||
            actual.meaning != expected.meaning ||
            actual.example != expected.example ||
            actual.correct != expected.correct ||
            actual.wrong != expected.wrong ||
            actual.dates.length != expected.dates.length ||
            !actual.dates.toSet().containsAll(expected.dates)) {
          throw StateError('데이터 이관 내용 확인 실패');
        }
      }
      // Only learning-data keys are removed; the existing API-key setting is untouched.
      await prefs.remove(_storageKey);
      await prefs.remove(seedKey);
      _databaseReady = true;
      if (!mounted) {
        return;
      }
      setState(() {
        _words = words..sort((a, b) => a.word.compareTo(b.word));
      });
    } catch (error) {
      _showStatus('저장된 단어를 불러오지 못했어요: $error');
    } finally {
      if (mounted) {
        setState(() => _isLoadingWords = false);
      }
    }
  }

  Future<bool> _saveWords() async {
    try {
      if (!_databaseReady) throw StateError('저장소 준비 중');
      await _database.saveWords(_words.map((word) => word.toJson()).toList());
      return true;
    } catch (error) {
      _showStatus('단어를 저장하지 못했어요: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('단어를 저장하지 못했어요. 다시 시도해 주세요.')),
        );
      }
      return false;
    }
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(_apiKeyStorageKey) ?? '';
    final phone = prefs.getString(_parentPhoneStorageKey) ?? '';
    final completed = prefs.getStringList(_completedDatesStorageKey) ?? const [];
    if (!mounted) {
      return;
    }
    setState(() {
      _apiKey = key;
      _parentPhone = phone;
      _completedDates = completed.toSet();
    });
  }

  Future<void> _markDateCompleted(String date) async {
    if (_completedDates.contains(date)) return;
    final updated = {..._completedDates, date};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_completedDatesStorageKey, updated.toList());
    if (!mounted) return;
    setState(() => _completedDates = updated);
  }

  Future<void> _saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = key.trim();
    await prefs.setString(_apiKeyStorageKey, trimmed);
    if (!mounted) {
      return;
    }
    setState(() => _apiKey = trimmed);
    _showStatus('API 키를 저장했어요.');
    await _completeMissingWords();
  }

  Future<void> _saveParentPhone(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = phone.trim();
    await prefs.setString(_parentPhoneStorageKey, trimmed);
    if (!mounted) {
      return;
    }
    setState(() => _parentPhone = trimmed);
  }

  Future<void> _sendResultToParent(int correct, int total) async {
    final phone = _parentPhone.trim();
    if (phone.isEmpty) {
      _showStatus('설정에서 엄마·아빠 전화번호를 먼저 입력해 주세요.');
      return;
    }
    final body = '엄마 아빠! 저 오늘 영어 퀴즈 $total문제 중 $correct개 맞췄어요! 🏆';
    // sms:번호?body=내용 (Android·iOS 공통 포맷)
    final uri = Uri.parse(
      'sms:$phone?body=${Uri.encodeComponent(body)}',
    );
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        _showStatus('문자 앱을 열 수 없어요. 전화번호를 확인해 주세요.');
      }
    } catch (_) {
      if (mounted) _showStatus('문자 앱을 열 수 없어요. 전화번호를 확인해 주세요.');
    }
  }

  Future<String> _recognizeTextWithOpenAI(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_apiKey.trim()}',
      },
      body: jsonEncode({
        'model': _openAiModel,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text':
                    '이 이미지에서 읽을 수 있는 영어 텍스트를 모두 그대로 추출해 줘. '
                    '설명이나 번역 없이 원문 영어 텍스트만 반환해.',
              },
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/jpeg;base64,$base64Image'},
              },
            ],
          },
        ],
        'max_tokens': 1000,
      }),
    );

    if (response.statusCode != 200) {
      final body = utf8.decode(response.bodyBytes);
      throw Exception('OpenAI API 오류 (${response.statusCode}): $body');
    }

    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;
    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      return '';
    }
    final message =
        (choices.first as Map<String, Object?>)['message']
            as Map<String, Object?>?;
    return (message?['content'] as String?)?.trim() ?? '';
  }

  Future<void> _pickAndScan(ImageSource source) async {
    if (_apiKey.trim().isEmpty) {
      _showStatus('먼저 오른쪽 위 ⚙️ 설정에서 OpenAI API 키를 입력해 주세요.');
      return;
    }

    setState(() {
      _isScanning = true;
      _statusMessage = null;
    });

    try {
      final image = await _picker.pickImage(source: source, imageQuality: 88);
      if (image == null) {
        return;
      }

      final text = await _recognizeTextWithOpenAI(File(image.path));
      if (text.isEmpty) {
        _showStatus('이미지에서 영어 글자를 찾지 못했어요.');
        return;
      }
      _textController.text = text;
      await _mergeExtractedWords(text);
    } catch (error) {
      _showStatus('사진에서 글자를 읽지 못했어요: $error');
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  void _openSettings() {
    showDialog<void>(
      context: context,
      builder: (_) => ApiKeyDialog(
        initialKey: _apiKey,
        initialPhone: _parentPhone,
        onSaved: _saveApiKey,
        onSavedPhone: _saveParentPhone,
        onResetData: _resetLearningData,
      ),
    );
  }

  Future<bool> _resetLearningData() async {
    if (_isResettingData || _isScanning || _isLoadingWords || !_databaseReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('학습 자료 처리가 끝난 뒤 다시 초기화해 주세요.')),
      );
      return false;
    }
    setState(() => _isResettingData = true);
    try {
      await _database.resetLearningData();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_completedDatesStorageKey);
      if (!mounted) return true;
      try {
        await _tts.stop();
      } catch (_) {
        /* Data reset has already committed. */
      }
      if (!mounted) return true;
      _textController.clear();
      setState(() {
        _words = [];
        _completedDates = <String>{};
        _selectedStudyDate = null;
        _selectedIndex = 2;
        _statusMessage = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('학습 데이터를 초기화했어요. API 키는 유지됩니다.')),
      );
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('초기화하지 못했어요. 잠시 후 다시 시도해 주세요.')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _isResettingData = false);
    }
  }

  Future<void> _mergeExtractedWords(
    String text, {
    bool openQuiz = true,
    bool force = false,
  }) async {
    if (_preparationMessage != null || _isResettingData) return;
    if (!_databaseReady) {
      _showStatus('학습 저장소가 준비되지 않았어요. 앱을 다시 실행해 주세요.');
      return;
    }
    final extracted = extractWords(text);
    if (extracted.isEmpty) {
      _showStatus('추출할 영어 단어가 없어요. 영어 문장을 입력해 주세요.');
      return;
    }
    // 강제 반영은 실제 생성 시도가 가능한 경우(API 키 존재)에만 적용한다.
    // 키가 없으면 기존처럼 "키 등록" 안내 흐름을 탄다.
    final effectiveForce = force && _apiKey.trim().isNotEmpty;
    setState(() {
      _isScanning = true;
      _statusMessage = null;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _preparationMessage = '단어를 분석하고 뜻과 예문을 만들고 있어요…');
    var enrichAfter = false;
    try {
      List<Map<String, Object?>> generated;
      try {
        generated = await VocabularyService().generate(
          text: text,
          apiKey: _apiKey,
        );
      } catch (_) {
        // 직접 입력(force)은 API가 실패해도 단어를 그대로 반영한다
        if (!effectiveForce) rethrow;
        generated = const [];
      }
      if (!mounted) return;
      // 직접 입력은 생성 결과가 비어도 막지 않고 무조건 반영한다
      if (generated.isEmpty && !effectiveForce) {
        _showStatus('이 문장에서 학습할 단어를 찾지 못했어요. 다른 문장을 넣어 주세요.');
        return;
      }
      final current = {for (final word in _words) word.word: word};
      final studyDate = studyDateToday();
      for (final json in generated) {
        final word = VocabWord.fromJson(json);
        final previous = current[word.word];
        current[word.word] = previous == null
            ? word
            : previous.copyWith(
                dates: openQuiz
                    ? {...previous.dates, studyDate}.toList()
                    : previous.dates,
                meaning: previous.meaning.isEmpty
                    ? word.meaning
                    : previous.meaning,
                example: previous.example.isEmpty
                    ? word.example
                    : previous.example,
              );
      }
      // 직접 입력: 생성 결과와 무관하게 추출된 단어를 모두 반영
      if (effectiveForce) {
        for (final w in extracted) {
          final previous = current[w];
          if (previous == null) {
            current[w] = VocabWord(
              word: w,
              dates: openQuiz ? [studyDate] : const [],
            );
          } else if (openQuiz && !previous.dates.contains(studyDate)) {
            current[w] = previous.copyWith(
              dates: {...previous.dates, studyDate}.toList(),
            );
          }
        }
      }
      final reflectedCount = effectiveForce ? extracted.length : generated.length;
      setState(() {
        _words = current.values.toList()
          ..sort((a, b) => a.word.compareTo(b.word));
        _preparationMessage = '단어와 학습 날짜를 저장하고 있어요…';
      });
      final saved = await _saveWords();
      if (!mounted || !saved) return;
      // 반영된 빈 단어들의 뜻/예문은 이후 best-effort로 채운다
      enrichAfter = effectiveForce;
      if (openQuiz) {
        setState(() {
          _selectedIndex = 2;
          _selectedStudyDate = studyDate;
        });
      }
      FocusManager.instance.primaryFocus?.unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            effectiveForce
                ? '$reflectedCount개 단어를 학습 목록에 반영했어요.'
                : '$reflectedCount개 단어의 뜻과 예문을 준비했어요.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      final message = _apiKey.isEmpty
          ? '새 학습 자료를 준비하려면 설정에서 API 키를 등록해 주세요. 준비된 퀴즈는 바로 풀 수 있어요.'
          : '뜻과 예문을 준비하지 못했어요. 연결과 API 설정을 확인하고 다시 시도해 주세요.';
      _showStatus(message);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _preparationMessage = null;
        });
        // 강제 반영된 빈 단어들의 뜻/예문을 best-effort로 보완
        if (enrichAfter) _completeMissingWords();
      }
    }
  }

  Future<void> _speak(String text) async {
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (error) {
      _showStatus('발음을 재생하지 못했어요: $error');
    }
  }

  Future<bool> _updateWord(VocabWord updated) async {
    final date = _selectedStudyDate;
    if (date == null || !_databaseReady || _isResettingData) return false;
    final previous = _words.firstWhere((word) => word.word == updated.word);
    try {
      await _database.recordAnswer(
        word: updated.word,
        date: date,
        correct: updated.correct > previous.correct,
      );
      if (mounted) {
        setState(() {
          _words = [
            for (final word in _words)
              if (word.word == updated.word)
                word.copyWith(correct: updated.correct, wrong: updated.wrong)
              else
                word,
          ];
        });
      }
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('퀴즈 결과를 저장하지 못했어요. 다시 선택해 주세요.')),
        );
      }
      return false;
    }
  }

  void _showStatus(String message) {
    if (!mounted) {
      return;
    }
    setState(() => _statusMessage = message);
  }

  @override
  Widget build(BuildContext context) {
    final dayWords = _words
        .where((word) => word.dates.contains(_selectedStudyDate))
        .toList();
    final pages = [
      ScanPage(
        isScanning: _isScanning || _isLoadingWords || _isResettingData,
        statusMessage: _statusMessage,
        preparationMessage: _preparationMessage,
        textController: _textController,
        onCamera: () => _pickAndScan(ImageSource.camera),
        onGallery: () => _pickAndScan(ImageSource.gallery),
        onUseText: () => _mergeExtractedWords(_textController.text, force: true),
      ),
      _selectedStudyDate == null
          ? StudyDatesPage(
              words: _words,
              quiz: false,
              completedDates: _completedDates,
              onSelected: (date) => setState(() => _selectedStudyDate = date),
            )
          : WordListPage(words: dayWords, onSpeak: _speak),
      _selectedStudyDate == null
          ? StudyDatesPage(
              words: _words,
              quiz: true,
              completedDates: _completedDates,
              onSelected: (date) => setState(() => _selectedStudyDate = date),
            )
          : QuizPage(
              key: ValueKey(_selectedStudyDate),
              words: dayWords,
              onSpeak: _speak,
              onAnswered: _updateWord,
              hasParentPhone: _parentPhone.trim().isNotEmpty,
              onSendResult: _sendResultToParent,
              onCompleted: () {
                final date = _selectedStudyDate;
                if (date != null) _markDateCompleted(date);
              },
            ),
    ];

    return PopScope(
      canPop: _selectedStudyDate == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) setState(() => _selectedStudyDate = null);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _selectedStudyDate == null
              ? null
              : BackButton(
                  onPressed: () => setState(() => _selectedStudyDate = null),
                ),
          title: Text(
            _selectedStudyDate == null
                ? 'Peng'
                : '${_selectedStudyDate!} · ${_selectedIndex == 1 ? 'Words' : 'Quiz'}',
          ),
          actions: [
            Center(child: Text('${_words.length} words')),
            IconButton(
              tooltip: '설정',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings),
            ),
          ],
        ),
        body: SafeArea(child: pages[_selectedIndex]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) => setState(() {
            _selectedIndex = index;
            _selectedStudyDate = null;
          }),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.document_scanner_outlined),
              selectedIcon: Icon(Icons.document_scanner),
              label: 'Scan',
            ),
            NavigationDestination(
              icon: Icon(Icons.style_outlined),
              selectedIcon: Icon(Icons.style),
              label: 'Words',
            ),
            NavigationDestination(
              icon: Icon(Icons.quiz_outlined),
              selectedIcon: Icon(Icons.quiz),
              label: 'Quiz',
            ),
          ],
        ),
      ),
    );
  }
}

class StudyDatesPage extends StatelessWidget {
  const StudyDatesPage({
    required this.words,
    required this.quiz,
    required this.completedDates,
    required this.onSelected,
    super.key,
  });
  final List<VocabWord> words;
  final bool quiz;
  final Set<String> completedDates;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final dates = words.expand((word) => word.dates).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    if (dates.isEmpty) {
      return const EmptyState(
        icon: Icons.calendar_today,
        title: '아직 학습 기록이 없어요',
        message: '문장을 추가하면 날짜별 학습 카드가 만들어져요.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          quiz ? '퀴즈를 풀 날짜를 선택하세요' : '단어를 볼 날짜를 선택하세요',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        for (final date in dates)
          Card(
            child: ListTile(
              leading: Icon(quiz ? Icons.quiz_outlined : Icons.style_outlined),
              title: Row(
                children: [
                  Flexible(child: Text(date)),
                  if (completedDates.contains(date)) ...[
                    const SizedBox(width: 8),
                    const _CompletedBadge(),
                  ],
                ],
              ),
              subtitle: Text(_summary(date)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onSelected(date),
            ),
          ),
      ],
    );
  }

  String _summary(String date) {
    final items = words.where((word) => word.dates.contains(date)).toList();
    final ready = items
        .where((word) => word.meaning.isNotEmpty && word.example.isNotEmpty)
        .length;
    return quiz
        ? '학습 가능 $ready개 · ${ready >= 4 ? '퀴즈 시작' : '단어 4개부터 시작'}'
        : '단어 ${items.length}개';
  }
}

/// 하루 퀴즈(10문제)를 완료한 날짜에 표시하는 완료 뱃지.
class _CompletedBadge extends StatelessWidget {
  const _CompletedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.green.shade600,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 14, color: Colors.white),
          SizedBox(width: 4),
          Text(
            '완료',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class ScanPage extends StatelessWidget {
  const ScanPage({
    required this.isScanning,
    required this.statusMessage,
    required this.textController,
    required this.onCamera,
    required this.onGallery,
    required this.onUseText,
    this.preparationMessage,
    super.key,
  });

  final bool isScanning;
  final String? statusMessage;
  final String? preparationMessage;
  final TextEditingController textController;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onUseText;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '책 한 페이지를 찍고 단어를 모아요',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: isScanning ? null : onCamera,
                icon: const Icon(Icons.camera_alt),
                label: const Text('사진 찍기'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isScanning ? null : onGallery,
                icon: const Icon(Icons.photo_library),
                label: const Text('앨범'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (isScanning) const LinearProgressIndicator(),
        if (statusMessage != null) ...[
          const SizedBox(height: 12),
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                statusMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: textController,
          readOnly: isScanning,
          minLines: 8,
          maxLines: 14,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: '인식된 영어 문장',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: isScanning ? null : onUseText,
          icon: preparationMessage == null
              ? const Icon(Icons.auto_awesome)
              : const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
          label: Text(
            preparationMessage == null ? '이 문장에서 단어 뽑기' : '학습 자료 준비 중…',
          ),
        ),
        if (preparationMessage != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(preparationMessage!, textAlign: TextAlign.center),
          ),
        ],
      ],
    );
  }
}

class WordListPage extends StatelessWidget {
  const WordListPage({required this.words, required this.onSpeak, super.key});

  final List<VocabWord> words;
  final ValueChanged<String> onSpeak;

  @override
  Widget build(BuildContext context) {
    if (words.isEmpty) {
      return const EmptyState(
        icon: Icons.style,
        title: '아직 단어가 없어요',
        message: '책 사진을 먼저 스캔하거나 문장을 붙여넣어 보세요.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: words.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = words[index];
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: ListTile(
            onTap: () => showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                scrollable: true,
                title: Text(item.word),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.meaning.isNotEmpty) Text(item.meaning),
                    const SizedBox(height: 16),
                    Text(
                      '예문',
                      style: Theme.of(dialogContext).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.example.trim().isEmpty
                          ? '예문을 준비하고 있어요.'
                          : item.example,
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('닫기'),
                  ),
                  FilledButton.icon(
                    onPressed: item.example.trim().isEmpty
                        ? null
                        : () => onSpeak(item.example),
                    icon: const Icon(Icons.volume_up),
                    label: const Text('예문 듣기'),
                  ),
                ],
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            title: Text(
              item.word,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              item.meaning.isEmpty || item.example.isEmpty
                  ? '학습 자료 준비 대기 중'
                  : item.meaning,
            ),
            leading: IconButton(
              tooltip: '발음 듣기',
              onPressed: () => onSpeak(item.word),
              icon: const Icon(Icons.volume_up),
            ),
          ),
        );
      },
    );
  }
}

class QuizPage extends StatefulWidget {
  const QuizPage({
    required this.words,
    required this.onSpeak,
    required this.onAnswered,
    required this.hasParentPhone,
    required this.onSendResult,
    required this.onCompleted,
    super.key,
  });

  final List<VocabWord> words;
  final ValueChanged<String> onSpeak;
  final Future<bool> Function(VocabWord) onAnswered;
  final bool hasParentPhone;
  final Future<void> Function(int correct, int total) onSendResult;
  final VoidCallback onCompleted;

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  static const int _sessionLength = 10; // 10문제 통과하면 학습 종료

  final _random = Random();
  VocabWord? _question;
  List<VocabWord> _choices = <VocabWord>[];
  String? _result;
  bool _isAnswering = false;

  int _answered = 0; // 이번 세션에서 푼 문제 수
  int _correctCount = 0; // 이번 세션 정답 수
  bool _finished = false; // 10문제 완료 여부
  bool _askForWord = true; // true: 뜻→영어 단어 고르기 / false: 영어 단어→뜻 고르기
  final Set<String> _askedWords = <String>{}; // 세션 내 이미 출제한 단어(중복 방지)

  @override
  void initState() {
    super.initState();
    _nextQuestion();
  }

  void _restartSession() {
    setState(() {
      _answered = 0;
      _correctCount = 0;
      _finished = false;
      _askedWords.clear();
    });
    _nextQuestion();
  }

  @override
  void didUpdateWidget(covariant QuizPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.words.length != widget.words.length ||
        (_question == null &&
            widget.words
                    .where(
                      (word) =>
                          word.meaning.isNotEmpty && word.example.isNotEmpty,
                    )
                    .length >=
                4)) {
      _nextQuestion();
    }
  }

  void _nextQuestion() {
    // 10문제를 모두 풀었으면 학습 종료 화면으로 전환
    if (_answered >= _sessionLength) {
      setState(() {
        _finished = true;
        _question = null;
        _choices = <VocabWord>[];
        _result = null;
      });
      widget.onCompleted(); // 10문제 완료 → 날짜에 완료 뱃지 기록
      return;
    }

    final eligible = widget.words
        .where((word) => word.meaning.isNotEmpty && word.example.isNotEmpty)
        .toList();
    if (eligible.length < 4) {
      setState(() {
        _question = null;
        _choices = <VocabWord>[];
        _result = null;
      });
      return;
    }

    eligible.shuffle(_random);
    // 세션 내 이미 출제한 단어는 제외해 중복 출제를 막는다
    final unasked = eligible
        .where((word) => !_askedWords.contains(word.word))
        .toList();
    if (unasked.isEmpty) {
      // 낼 수 있는 새로운 단어가 없으면 세션을 종료한다
      setState(() {
        _finished = true;
        _question = null;
        _choices = <VocabWord>[];
        _result = null;
      });
      widget.onCompleted();
      return;
    }

    final question = unasked.first;
    final choices = <VocabWord>[
      question,
      ...eligible.where((word) => word.word != question.word).take(3),
    ]..shuffle(_random);

    setState(() {
      _question = question;
      _choices = choices;
      _result = null;
      _askForWord = _random.nextBool(); // 문제마다 유형 랜덤 혼합
      _askedWords.add(question.word);
    });
  }

  Future<void> _answer(VocabWord choice) async {
    final question = _question;
    if (question == null || _result != null || _isAnswering) {
      return;
    }

    final isCorrect = choice.word == question.word;
    setState(() => _isAnswering = true);
    final saved = await widget.onAnswered(
      question.copyWith(
        correct: question.correct + (isCorrect ? 1 : 0),
        wrong: question.wrong + (isCorrect ? 0 : 1),
      ),
    );

    if (!mounted) return;
    setState(() {
      _isAnswering = false;
      if (saved) {
        _answered += 1;
        if (isCorrect) _correctCount += 1;
        _result = isCorrect ? '정답!' : '다시 볼 단어예요';
      }
    });

    // 정답을 맞췄을 때 캐릭터가 나와 칭찬
    if (saved && isCorrect && mounted) {
      await _showPraise();
    }
  }

  Future<void> _showPraise() {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '칭찬',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (context, animation, secondaryAnimation) =>
          const SizedBox.shrink(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        // 통통 튀는 등장 애니메이션
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.elasticOut,
        );
        return Transform.scale(
          scale: curved.value,
          child: Opacity(
            opacity: animation.value.clamp(0.0, 1.0),
            child: _PraiseDialog(seed: _answered),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final question = _question;

    if (widget.words
            .where((word) => word.meaning.isNotEmpty && word.example.isNotEmpty)
            .length <
        4) {
      return const EmptyState(
        icon: Icons.quiz,
        title: '퀴즈 준비 중',
        message: '시스템이 뜻과 예문을 준비한 단어가 4개 이상이면 퀴즈가 시작돼요.',
      );
    }

    // 10문제를 모두 푼 뒤 학습 종료 화면
    if (_finished) {
      return _QuizCompleteView(
        correct: _correctCount,
        total: _sessionLength,
        onRestart: _restartSession,
        hasParentPhone: widget.hasParentPhone,
        onSend: () => widget.onSendResult(_correctCount, _sessionLength),
      );
    }

    if (question == null) {
      return Center(
        child: FilledButton.icon(
          onPressed: _nextQuestion,
          icon: const Icon(Icons.play_arrow),
          label: const Text('퀴즈 시작'),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                _askForWord ? '뜻에 맞는 영어 단어는?' : '이 단어의 뜻은?',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${_answered + 1} / $_sessionLength',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _answered / _sessionLength,
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 18),
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.primaryContainer,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_askForWord)
                  // 뜻 → 영어 단어 고르기: 한글 뜻을 보여줌
                  Text(
                    question.meaning,
                    style: Theme.of(context).textTheme.headlineSmall,
                  )
                else
                  // 영어 단어 → 뜻 고르기: 영어 단어 + 발음 듣기
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          question.word,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: '발음 듣기',
                        onPressed: () => widget.onSpeak(question.word),
                        icon: const Icon(Icons.volume_up),
                      ),
                    ],
                  ),
                if (_result != null) ...[
                  // 정답 공개 후: 반대편 정보(단어↔뜻)와 예문 노출
                  const SizedBox(height: 12),
                  if (!_askForWord)
                    Text(
                      question.meaning,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  if (question.example.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(question.example),
                  ],
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (final choice in _choices) ...[
          if (_askForWord)
            // 보기: 영어 단어 (발음 듣기 버튼 포함)
            Row(
              children: [
                IconButton.outlined(
                  tooltip: '발음 듣기',
                  onPressed: () => widget.onSpeak(choice.word),
                  icon: const Icon(Icons.volume_up),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _result == null && !_isAnswering
                        ? () => _answer(choice)
                        : null,
                    child: Text(choice.word),
                  ),
                ),
              ],
            )
          else
            // 보기: 한글 뜻
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _result == null && !_isAnswering
                    ? () => _answer(choice)
                    : null,
                child: Text(choice.meaning, textAlign: TextAlign.center),
              ),
            ),
          const SizedBox(height: 8),
        ],
        if (_result != null) ...[
          const SizedBox(height: 8),
          Text(
            _result!,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _nextQuestion,
            child: Text(
              _answered >= _sessionLength ? '결과 보기' : '다음 문제',
            ),
          ),
        ],
      ],
    );
  }
}

/// 정답 시 등장해 칭찬하는 캐릭터 팝업.
/// assets/characters/ 에 PNG(brawl1.png~brawl5.png)를 넣으면 캐릭터로 교체되고,
/// 파일이 없으면 이모지 폴백으로 표시된다.
class _PraiseDialog extends StatelessWidget {
  const _PraiseDialog({required this.seed});

  final int seed;

  static const List<String> _praises = <String>[
    '정답! 완전 레전드예요! 🏆',
    '나이스! 역전의 한 방!',
    '대박! 브롤러 등급 UP!',
    '퍼펙트! 트로피 획득! ⭐',
    '굿! 이대로만 가보자고!',
  ];

  // assets/characters/ 에 넣을 캐릭터 파일 이름(없으면 이모지 폴백)
  static const List<String> _characterAssets = <String>[
    'assets/characters/brawl1.png',
    'assets/characters/brawl2.png',
    'assets/characters/brawl3.png',
    'assets/characters/brawl4.png',
    'assets/characters/brawl5.png',
  ];

  static const List<String> _fallbackEmoji = <String>['🐻', '🦊', '⭐', '🔥', '🎯'];

  @override
  Widget build(BuildContext context) {
    final index = (seed.abs()) % _characterAssets.length;
    final praise = _praises[(seed.abs()) % _praises.length];

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 280,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 24, spreadRadius: 2),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 140,
                child: Image.asset(
                  _characterAssets[index],
                  fit: BoxFit.contain,
                  // PNG가 아직 없을 때 이모지로 대체
                  errorBuilder: (context, error, stack) => Center(
                    child: Text(
                      _fallbackEmoji[index % _fallbackEmoji.length],
                      style: const TextStyle(fontSize: 96),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                praise,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('계속하기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 10문제를 모두 푼 뒤 보여주는 학습 종료 화면.
class _QuizCompleteView extends StatelessWidget {
  const _QuizCompleteView({
    required this.correct,
    required this.total,
    required this.onRestart,
    required this.hasParentPhone,
    required this.onSend,
  });

  final int correct;
  final int total;
  final VoidCallback onRestart;
  final bool hasParentPhone;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final allPerfect = correct == total;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              allPerfect ? '🏆' : '🎉',
              style: const TextStyle(fontSize: 96),
            ),
            const SizedBox(height: 12),
            Text(
              '학습 완료!',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$total문제 중 $correct개 정답',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              allPerfect ? '완벽해요! 모두 맞혔어요!' : '수고했어요! 다시 도전해볼까요?',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRestart,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 도전'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onSend,
              icon: const Icon(Icons.send),
              label: const Text('엄마 아빠에게 결과 보내기'),
            ),
            if (!hasParentPhone) ...[
              const SizedBox(height: 8),
              Text(
                '설정에서 전화번호를 입력하면 문자로 보낼 수 있어요.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ApiKeyDialog extends StatefulWidget {
  const ApiKeyDialog({
    required this.initialKey,
    required this.initialPhone,
    required this.onSaved,
    required this.onSavedPhone,
    required this.onResetData,
    super.key,
  });

  final String initialKey;
  final String initialPhone;
  final ValueChanged<String> onSaved;
  final ValueChanged<String> onSavedPhone;
  final Future<bool> Function() onResetData;

  @override
  State<ApiKeyDialog> createState() => _ApiKeyDialogState();
}

class _ApiKeyDialogState extends State<ApiKeyDialog> {
  late final TextEditingController _controller;
  late final TextEditingController _phoneController;
  bool _obscure = true;
  bool _resetting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialKey);
    _phoneController = TextEditingController(text: widget.initialPhone);
  }

  @override
  void dispose() {
    _controller.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (confirmationContext) => AlertDialog(
        title: const Text('학습 데이터를 초기화할까요?'),
        content: const Text(
          '모든 단어, 예문, 날짜별 학습 데이터와 퀴즈 기록이 삭제됩니다. 되돌릴 수 없어요.\n\nAPI 키는 유지됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(confirmationContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(confirmationContext, true),
            child: const Text('초기화'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _resetting = true);
    final success = await widget.onResetData();
    if (!mounted) return;
    setState(() => _resetting = false);
    if (success) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('설정'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '사진 글자 인식에 사용할 OpenAI API 키를 입력하세요.\n'
            '키는 이 기기에만 저장됩니다.',
          ),
          const SizedBox(height: 12),
          TextField(
            enabled: !_resetting,
            controller: _controller,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: 'sk-...',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const Text(
            '엄마·아빠 전화번호',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('퀴즈를 마치면 이 번호로 결과를 문자로 보낼 수 있어요.'),
          const SizedBox(height: 8),
          TextField(
            enabled: !_resetting,
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: '010-1234-5678',
              prefixIcon: Icon(Icons.phone),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const Text('학습 데이터', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('단어와 퀴즈 기록을 모두 삭제합니다. API 키는 유지됩니다.'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _resetting ? null : _confirmReset,
            icon: const Icon(Icons.delete_outline),
            label: Text(_resetting ? '초기화 중…' : '학습 데이터 초기화'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _resetting ? null : () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
        FilledButton(
          onPressed: _resetting
              ? null
              : () {
                  widget.onSaved(_controller.text);
                  widget.onSavedPhone(_phoneController.text);
                  Navigator.of(context).pop();
                },
          child: const Text('저장'),
        ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
