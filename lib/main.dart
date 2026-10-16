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
import 'book_splash.dart';
import 'character_puzzle.dart';
import 'ar_level.dart';

void main() {
  runApp(const PengApp());
}

const _storageKey = 'peng_words_v1';
const _environmentApiKey = String.fromEnvironment('OPENAI_API_KEY');
const _arLevelStorageKey = 'peng_ar_level_v1';
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
  const HomeScreen({super.key, this.imagePicker});

  final ImagePicker? imagePicker;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _database = LearningDatabase();
  bool _databaseReady = false;
  bool _showSplash = true;
  bool _isResettingData = false;
  late final _picker = widget.imagePicker ?? ImagePicker();
  final _tts = FlutterTts();
  final _textController = TextEditingController();

  List<VocabWord> _words = <VocabWord>[];
  bool _isScanning = false;
  String? _preparationMessage;
  bool _isLoadingWords = true;
  int _selectedIndex = 2;
  String? _selectedStudyDate;
  String? _statusMessage;
  final String _apiKey = _environmentApiKey.trim();
  String _parentPhone = '';
  ArLevelRange _arLevel = ArLevelRange.defaultValue;
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
    final splashDelay = Future<void>.delayed(
      const Duration(milliseconds: 1400),
    );
    try {
      await _loadSettings();
    } catch (_) {
      _showStatus('설정을 불러오지 못했어요.');
    }
    if (!mounted) return;
    await _loadWords();
    await splashDelay;
    if (!mounted) return;
    setState(() => _showSplash = false);
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

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString(_parentPhoneStorageKey) ?? '';
    final arLevel = ArLevelRange.decode(prefs.getString(_arLevelStorageKey));
    final completed =
        prefs.getStringList(_completedDatesStorageKey) ?? const [];
    if (!mounted) {
      return;
    }
    setState(() {
      _parentPhone = phone;
      _arLevel = arLevel;
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

  Future<void> _saveArLevel(ArLevelRange level) async {
    if (!level.isValid) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_arLevelStorageKey, level.encode());
    if (mounted) setState(() => _arLevel = level);
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
    final uri = Uri.parse('sms:$phone?body=${Uri.encodeComponent(body)}');
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
    if (_isScanning || _isLoadingWords || _isResettingData) return;

    setState(() {
      _isScanning = true;
      _statusMessage = null;
    });

    try {
      final image = await _picker.pickImage(
        source: source,
        imageQuality: 88,
        requestFullMetadata: false,
      );
      if (!mounted || image == null) {
        return;
      }
      if (_apiKey.isEmpty) {
        _showStatus('사진을 선택했지만 글자 인식이 아직 설정되지 않았어요.');
        return;
      }

      final text = await _recognizeTextWithOpenAI(File(image.path));
      if (text.isEmpty) {
        _showStatus('이미지에서 영어 글자를 찾지 못했어요.');
        return;
      }
      if (!mounted) return;
      _textController.text = text;
      await _mergeExtractedWords(text);
    } on PlatformException catch (error) {
      final message = switch (error.code) {
        'camera_access_denied' =>
          '카메라 권한이 꺼져 있어요. 기기 설정에서 Peng의 카메라 접근을 허용해 주세요.',
        'photo_access_denied' => '사진 접근이 꺼져 있어요. 기기 설정에서 Peng의 사진 접근을 허용해 주세요.',
        'camera_access_restricted' || 'photo_access_restricted' =>
          '이 기기에서 사진 접근이 제한되어 있어요. 스크린 타임이나 기기 관리 설정을 확인해 주세요.',
        'camera_unavailable' ||
        'no_available_camera' => '카메라를 사용할 수 없어요. 앨범에서 사진을 선택해 주세요.',
        'multiple_request' || 'already_active' => '이미 사진 선택 화면이 열려 있어요.',
        _ => '사진을 열지 못했어요. 다시 시도해 주세요.',
      };
      _showStatus(message);
    } on MissingPluginException {
      _showStatus('사진 기능을 불러오지 못했어요. 앱을 완전히 종료한 뒤 다시 실행해 주세요.');
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
      builder: (_) => SettingsDialog(
        initialPhone: _parentPhone,
        initialArLevel: _arLevel,
        onSavedArLevel: _saveArLevel,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('학습 데이터를 초기화했어요.')));
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
    setState(() {
      _isScanning = true;
      _statusMessage = null;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _preparationMessage = '단어를 분석하고 뜻과 예문을 만들고 있어요…');
    try {
      final generated = await VocabularyService().generate(
        text: text,
        apiKey: _apiKey,
        arLevel: _arLevel,
      );
      if (!mounted) return;
      if (generated.isEmpty) {
        _showStatus('${_arLevel.label} 수준에 맞는 단어를 찾지 못했어요. 다른 글이나 AR 수준을 선택해 주세요.');
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
                meaning: openQuiz || previous.meaning.isEmpty
                    ? word.meaning
                    : previous.meaning,
                example: openQuiz || previous.example.isEmpty
                    ? word.example
                    : previous.example,
              );
      }
      final reflectedCount = generated.length;
      setState(() {
        _words = current.values.toList()
          ..sort((a, b) => a.word.compareTo(b.word));
        _preparationMessage = '단어와 학습 날짜를 저장하고 있어요…';
      });
      final saved = await _saveWords();
      if (!mounted || !saved) return;
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
            '${_arLevel.label} 기준으로 $reflectedCount개 단어의 뜻과 예문을 준비했어요.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      final message = _apiKey.isEmpty
          ? '새 학습 자료를 준비할 수 없어요. 준비된 퀴즈는 바로 풀 수 있어요.'
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
    if (_showSplash) return const BookSplash();
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
        onUseText: () =>
            _mergeExtractedWords(_textController.text),
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
  late CharacterRegion _puzzleCharacter;
  int _puzzleCharacterIndex = -1;
  final _revealedPieces = <int>{};
  late List<int> _revealOrder;
  int? _newlyRevealedPiece;
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
    _resetPuzzle();
    _nextQuestion();
  }

  void _resetPuzzle() {
    final count = characterRegions.length;
    _puzzleCharacterIndex = _puzzleCharacterIndex < 0
        ? _random.nextInt(count)
        : (_puzzleCharacterIndex + 1 + _random.nextInt(count - 1)) % count;
    _puzzleCharacter = characterRegions[_puzzleCharacterIndex];
    _revealOrder = List.generate(CharacterPuzzle.pieceCount, (index) => index)
      ..shuffle(_random);
    _revealedPieces.clear();
    _newlyRevealedPiece = null;
  }

  void _restartSession() {
    setState(() {
      _answered = 0;
      _correctCount = 0;
      _finished = false;
      _askedWords.clear();
      _resetPuzzle();
    });
    _nextQuestion();
  }

  @override
  void didUpdateWidget(covariant QuizPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_finished || _isAnswering) return;
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
    if (_finished || _isAnswering) return;
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
    if (question == null ||
        _result != null ||
        _isAnswering ||
        _finished ||
        _answered >= _sessionLength) {
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
        if (isCorrect) {
          _newlyRevealedPiece = _revealOrder[_correctCount];
          _revealedPieces.add(_newlyRevealedPiece!);
          _correctCount += 1;
        }
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
            child: _PraiseDialog(
              seed: _answered,
              character: _puzzleCharacter,
              revealedPieces: Set.unmodifiable(_revealedPieces),
              newlyRevealedPiece: _newlyRevealedPiece,
            ),
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
        character: _puzzleCharacter,
        revealedPieces: Set.unmodifiable(_revealedPieces),
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
              '${_answered + (_result == null ? 1 : 0)} / $_sessionLength',
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
        const SizedBox(height: 16),
        Row(
          children: [
            CharacterPuzzle(
              character: _puzzleCharacter,
              revealedPieces: Set.unmodifiable(_revealedPieces),
              size: 96,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '비밀 캐릭터를 찾아요!',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text('${_revealedPieces.length} / 10 조각 공개'),
                  const SizedBox(height: 4),
                  const Text('정답마다 한 조각씩 열려요.'),
                ],
              ),
            ),
          ],
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
            child: Text(_answered >= _sessionLength ? '결과 보기' : '다음 문제'),
          ),
        ],
      ],
    );
  }
}

/// Correct answers reveal one more tile of the session's character.
class _PraiseDialog extends StatelessWidget {
  const _PraiseDialog({
    required this.seed,
    required this.character,
    required this.revealedPieces,
    required this.newlyRevealedPiece,
  });

  final int seed;
  final CharacterRegion character;
  final Set<int> revealedPieces;
  final int? newlyRevealedPiece;

  static const List<String> _praises = <String>[
    '정답! 완전 레전드예요! 🏆',
    '나이스! 역전의 한 방!',
    '대박! 브롤러 등급 UP!',
    '퍼펙트! 트로피 획득! ⭐',
    '굿! 이대로만 가보자고!',
  ];

  @override
  Widget build(BuildContext context) {
    final praise = _praises[(seed.abs()) % _praises.length];

    return Dialog(
      constraints: const BoxConstraints(maxWidth: 320),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CharacterPuzzle(
              character: character,
              revealedPieces: revealedPieces,
              newlyRevealedPiece: newlyRevealedPiece,
            ),
            const SizedBox(height: 12),
            Text(
              revealedPieces.length == 10
                  ? '${character.name} 완성!'
                  : '${revealedPieces.length} / 10 조각 공개!',
            ),
            const SizedBox(height: 16),
            Text(
              praise,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('계속하기'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 10문제를 모두 푼 뒤 보여주는 학습 종료 화면.
class _QuizCompleteView extends StatelessWidget {
  const _QuizCompleteView({
    required this.character,
    required this.revealedPieces,
    required this.correct,
    required this.total,
    required this.onRestart,
    required this.hasParentPhone,
    required this.onSend,
  });

  final CharacterRegion character;
  final Set<int> revealedPieces;
  final int correct;
  final int total;
  final VoidCallback onRestart;
  final bool hasParentPhone;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final allPerfect = correct == total;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CharacterPuzzle(
              character: character,
              revealedPieces: revealedPieces,
              size: 160,
            ),
            const SizedBox(height: 8),
            Text(
              revealedPieces.length == 10
                  ? '${character.name} 완성!'
                  : '${revealedPieces.length} / 10 조각을 찾았어요!',
            ),
            const SizedBox(height: 12),
            Text(
              '학습 완료!',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
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

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    required this.initialPhone,
    this.initialArLevel = ArLevelRange.defaultValue,
    this.onSavedArLevel,
    required this.onSavedPhone,
    required this.onResetData,
    super.key,
  });

  final String initialPhone;
  final ArLevelRange initialArLevel;
  final ValueChanged<ArLevelRange>? onSavedArLevel;
  final ValueChanged<String> onSavedPhone;
  final Future<bool> Function() onResetData;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _phoneController;
  bool _resetting = false;
  late ArLevelRange _arLevel;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(text: widget.initialPhone);
    _arLevel = widget.initialArLevel;
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (confirmationContext) => AlertDialog(
        title: const Text('학습 데이터를 초기화할까요?'),
        content: const Text('모든 단어, 예문, 날짜별 학습 데이터와 퀴즈 기록이 삭제됩니다. 되돌릴 수 없어요.'),
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
          const Text('AR 목표 수준', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(_arLevel.label, key: const ValueKey('ar-level-label')),
          RangeSlider(
            values: RangeValues(_arLevel.minimum, _arLevel.maximum),
            min: ArLevelRange.lowest,
            max: ArLevelRange.highest,
            divisions: 23,
            labels: RangeLabels(
              _arLevel.minimum.toStringAsFixed(1),
              _arLevel.maximum.toStringAsFixed(1),
            ),
            onChanged: _resetting ? null : (values) {
              if (values.start >= values.end) return;
              setState(() => _arLevel = ArLevelRange(values.start, values.end));
            },
          ),
          const Text('새로 추출하는 단어와 예문의 난이도에 적용돼요.'),
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
          const Text('단어와 퀴즈 기록을 모두 삭제합니다.'),
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
                  widget.onSavedPhone(_phoneController.text);
                  widget.onSavedArLevel?.call(_arLevel);
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
