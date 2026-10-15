import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const PengApp());
}

const _storageKey = 'peng_words_v1';
const _apiKeyStorageKey = 'peng_openai_key_v1';
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

class VocabWord {
  const VocabWord({
    required this.word,
    this.meaning = '',
    this.example = '',
    this.correct = 0,
    this.wrong = 0,
  });

  final String word;
  final String meaning;
  final String example;
  final int correct;
  final int wrong;

  VocabWord copyWith({
    String? meaning,
    String? example,
    int? correct,
    int? wrong,
  }) {
    return VocabWord(
      word: word,
      meaning: meaning ?? this.meaning,
      example: example ?? this.example,
      correct: correct ?? this.correct,
      wrong: wrong ?? this.wrong,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'word': word,
      'meaning': meaning,
      'example': example,
      'correct': correct,
      'wrong': wrong,
    };
  }

  factory VocabWord.fromJson(Map<String, Object?> json) {
    return VocabWord(
      word: json['word'] as String,
      meaning: json['meaning'] as String? ?? '',
      example: json['example'] as String? ?? '',
      correct: json['correct'] as int? ?? 0,
      wrong: json['wrong'] as int? ?? 0,
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
  final _picker = ImagePicker();
  final _tts = FlutterTts();
  final _textController = TextEditingController();

  List<VocabWord> _words = <VocabWord>[];
  bool _isScanning = false;
  int _selectedIndex = 0;
  String? _statusMessage;
  String _apiKey = '';

  @override
  void initState() {
    super.initState();
    _loadWords();
    _loadApiKey();
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.42);
  }

  @override
  void dispose() {
    _textController.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _loadWords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null) {
        return;
      }

      final decoded = jsonDecode(raw) as List<dynamic>;
      if (!mounted) {
        return;
      }
      setState(() {
        _words =
            decoded
                .whereType<Map<String, dynamic>>()
                .map(
                  (json) => VocabWord.fromJson(Map<String, Object?>.from(json)),
                )
                .toList()
              ..sort((a, b) => a.word.compareTo(b.word));
      });
    } catch (error) {
      _showStatus('저장된 단어를 불러오지 못했어요: $error');
    }
  }

  Future<void> _saveWords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_words.map((word) => word.toJson()).toList());
      await prefs.setString(_storageKey, encoded);
    } catch (error) {
      _showStatus('단어를 저장하지 못했어요: $error');
    }
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(_apiKeyStorageKey) ?? '';
    if (!mounted) {
      return;
    }
    setState(() => _apiKey = key);
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

    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;
    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      return '';
    }
    final message = (choices.first as Map<String, Object?>)['message']
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
      _mergeExtractedWords(text);
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
      builder: (_) => ApiKeyDialog(initialKey: _apiKey, onSaved: _saveApiKey),
    );
  }

  void _mergeExtractedWords(String text) {
    final current = {for (final item in _words) item.word: item};
    for (final word in extractWords(text)) {
      current.putIfAbsent(word, () => VocabWord(word: word));
    }

    setState(() {
      _words = current.values.toList()
        ..sort((a, b) => a.word.compareTo(b.word));
    });
    _saveWords();
  }

  Future<void> _speak(String text) async {
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (error) {
      _showStatus('발음을 재생하지 못했어요: $error');
    }
  }

  void _updateWord(VocabWord updated) {
    setState(() {
      _words = [
        for (final word in _words)
          if (word.word == updated.word) updated else word,
      ];
    });
    _saveWords();
  }

  void _deleteWord(VocabWord target) {
    setState(() {
      _words = _words.where((word) => word.word != target.word).toList();
    });
    _saveWords();
  }

  void _showStatus(String message) {
    if (!mounted) {
      return;
    }
    setState(() => _statusMessage = message);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      ScanPage(
        isScanning: _isScanning,
        statusMessage: _statusMessage,
        textController: _textController,
        onCamera: () => _pickAndScan(ImageSource.camera),
        onGallery: () => _pickAndScan(ImageSource.gallery),
        onUseText: () => _mergeExtractedWords(_textController.text),
      ),
      WordListPage(
        words: _words,
        onSpeak: _speak,
        onChanged: _updateWord,
        onDelete: _deleteWord,
      ),
      QuizPage(words: _words, onSpeak: _speak, onAnswered: _updateWord),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Peng'),
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
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
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
    super.key,
  });

  final bool isScanning;
  final String? statusMessage;
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
          icon: const Icon(Icons.auto_awesome),
          label: const Text('이 문장에서 단어 뽑기'),
        ),
      ],
    );
  }
}

class WordListPage extends StatelessWidget {
  const WordListPage({
    required this.words,
    required this.onSpeak,
    required this.onChanged,
    required this.onDelete,
    super.key,
  });

  final List<VocabWord> words;
  final ValueChanged<String> onSpeak;
  final ValueChanged<VocabWord> onChanged;
  final ValueChanged<VocabWord> onDelete;

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
      separatorBuilder: (_, __) => const SizedBox(height: 8),
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
            title: Text(
              item.word,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(item.meaning.isEmpty ? '뜻을 입력해 주세요' : item.meaning),
            leading: IconButton(
              tooltip: '발음 듣기',
              onPressed: () => onSpeak(item.word),
              icon: const Icon(Icons.volume_up),
            ),
            trailing: IconButton(
              tooltip: '삭제',
              onPressed: () => onDelete(item),
              icon: const Icon(Icons.delete_outline),
            ),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => WordEditorDialog(word: item, onSaved: onChanged),
            ),
          ),
        );
      },
    );
  }
}

class WordEditorDialog extends StatefulWidget {
  const WordEditorDialog({
    required this.word,
    required this.onSaved,
    super.key,
  });

  final VocabWord word;
  final ValueChanged<VocabWord> onSaved;

  @override
  State<WordEditorDialog> createState() => _WordEditorDialogState();
}

class _WordEditorDialogState extends State<WordEditorDialog> {
  late final TextEditingController _meaningController;
  late final TextEditingController _exampleController;

  @override
  void initState() {
    super.initState();
    _meaningController = TextEditingController(text: widget.word.meaning);
    _exampleController = TextEditingController(text: widget.word.example);
  }

  @override
  void dispose() {
    _meaningController.dispose();
    _exampleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.word.word),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _meaningController,
            decoration: const InputDecoration(labelText: '뜻'),
          ),
          TextField(
            controller: _exampleController,
            decoration: const InputDecoration(labelText: '예문'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
        FilledButton(
          onPressed: () {
            widget.onSaved(
              widget.word.copyWith(
                meaning: _meaningController.text.trim(),
                example: _exampleController.text.trim(),
              ),
            );
            Navigator.of(context).pop();
          },
          child: const Text('저장'),
        ),
      ],
    );
  }
}

class QuizPage extends StatefulWidget {
  const QuizPage({
    required this.words,
    required this.onSpeak,
    required this.onAnswered,
    super.key,
  });

  final List<VocabWord> words;
  final ValueChanged<String> onSpeak;
  final ValueChanged<VocabWord> onAnswered;

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  final _random = Random();
  VocabWord? _question;
  List<VocabWord> _choices = <VocabWord>[];
  String? _result;

  @override
  void didUpdateWidget(covariant QuizPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.words.length != widget.words.length) {
      _nextQuestion();
    }
  }

  void _nextQuestion() {
    final eligible = widget.words
        .where((word) => word.meaning.isNotEmpty)
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
    final question = eligible.first;
    final choices = <VocabWord>[
      question,
      ...eligible.where((word) => word.word != question.word).take(3),
    ]..shuffle(_random);

    setState(() {
      _question = question;
      _choices = choices;
      _result = null;
    });
  }

  void _answer(VocabWord choice) {
    final question = _question;
    if (question == null) {
      return;
    }

    final isCorrect = choice.word == question.word;
    widget.onAnswered(
      question.copyWith(
        correct: question.correct + (isCorrect ? 1 : 0),
        wrong: question.wrong + (isCorrect ? 0 : 1),
      ),
    );

    setState(() {
      _result = isCorrect ? '정답!' : '다시 볼 단어예요';
    });
  }

  @override
  Widget build(BuildContext context) {
    final question = _question;

    if (widget.words.where((word) => word.meaning.isNotEmpty).length < 4) {
      return const EmptyState(
        icon: Icons.quiz,
        title: '퀴즈 준비 중',
        message: '뜻이 입력된 단어가 4개 이상이면 퀴즈를 시작할 수 있어요.',
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
        Text(
          '뜻에 맞는 영어 단어는?',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
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
                Text(
                  question.meaning,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (question.example.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(question.example),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (final choice in _choices) ...[
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
                  onPressed: _result == null ? () => _answer(choice) : null,
                  child: Text(choice.word),
                ),
              ),
            ],
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
          FilledButton(onPressed: _nextQuestion, child: const Text('다음 문제')),
        ],
      ],
    );
  }
}

class ApiKeyDialog extends StatefulWidget {
  const ApiKeyDialog({
    required this.initialKey,
    required this.onSaved,
    super.key,
  });

  final String initialKey;
  final ValueChanged<String> onSaved;

  @override
  State<ApiKeyDialog> createState() => _ApiKeyDialogState();
}

class _ApiKeyDialogState extends State<ApiKeyDialog> {
  late final TextEditingController _controller;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialKey);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('OpenAI API 키'),
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
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
        FilledButton(
          onPressed: () {
            widget.onSaved(_controller.text);
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
