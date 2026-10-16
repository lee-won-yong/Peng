import 'dart:convert';

/// A generation target, not an official ATOS score for individual words.
class ArLevelRange {
  const ArLevelRange(this.minimum, this.maximum);

  static const defaultValue = ArLevelRange(3, 5);
  static const lowest = 0.5;
  static const highest = 12.0;
  final double minimum;
  final double maximum;

  bool get isValid =>
      minimum.isFinite &&
      maximum.isFinite &&
      minimum >= lowest &&
      maximum <= highest &&
      minimum < maximum;

  String get label =>
      'AR ${minimum.toStringAsFixed(1)}–${maximum.toStringAsFixed(1)}';

  String encode() => jsonEncode({'minimum': minimum, 'maximum': maximum});

  static ArLevelRange decode(String? value) {
    try {
      final json = jsonDecode(value ?? '') as Map<String, dynamic>;
      final range = ArLevelRange(
        (json['minimum'] as num).toDouble(),
        (json['maximum'] as num).toDouble(),
      );
      return range.isValid ? range : defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  String get generationGuidance {
    if (maximum <= 2) {
      return 'Select useful concrete vocabulary beyond function words. '
          'Write clear examples of about 5–9 words using simple clauses.';
    }
    if (maximum <= 3) {
      return 'Select descriptive words, useful action verbs, and accessible '
          'Tier 2 vocabulary beyond the earliest beginner words. Write examples '
          'of about 8–12 words with varied tenses and simple conjunctions.';
    }
    if (maximum <= 5) {
      return 'Prioritize Tier 2 vocabulary, precise verbs, abstract nouns, '
          'descriptive adjectives, and useful academic words from the source. '
          'Avoid filling the list with very basic words such as book, good, '
          'big, and happy when stronger candidates exist. Write examples of '
          'about 10–16 words with context clues, cause and effect, varied tenses, '
          'and appropriate subordinate clauses.';
    }
    if (maximum <= 7) {
      return 'Prioritize challenging Tier 2 and relevant Tier 3 academic '
          'vocabulary, nuanced meanings, inference, and domain-specific concepts. '
          'Write examples of about 12–22 words using context clues, varied '
          'sentence structures, and appropriate abstract ideas.';
    }
    return 'Prioritize advanced academic and literary vocabulary, nuanced '
        'verbs, abstract concepts, and domain-specific terms actually present '
        'in the source. Write examples of about 16–26 words using natural '
        'complex syntax and context that clarifies the precise meaning.';
  }
}
