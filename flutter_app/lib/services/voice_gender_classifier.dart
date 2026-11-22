import '../models/thermostat_state.dart';

enum VoiceGenderHint {
  female,
  male,
  neutral,
}

class VoiceOptionInfo {
  final String name;
  final String locale;
  final String voiceUri;
  final VoiceGenderHint gender;

  const VoiceOptionInfo({
    required this.name,
    required this.locale,
    this.voiceUri = '',
    required this.gender,
  });

  String labelTr() {
    switch (gender) {
      case VoiceGenderHint.female:
        return '$name (Kadın)';
      case VoiceGenderHint.male:
        return '$name (Erkek)';
      case VoiceGenderHint.neutral:
        return name;
    }
  }
}

class VoicePickOutcome {
  final int index;
  final bool matchedExpectedGender;

  const VoicePickOutcome({
    required this.index,
    required this.matchedExpectedGender,
  });
}

class VoiceGenderClassifier {
  VoiceGenderClassifier._();

  static const _femaleSubstrings = [
    'emel',
    'seda',
    'yagmur',
    'yelda',
    'filiz',
    'defne',
    'ayla',
    'zeynep',
    'ipek',
    'esra',
    'google turkce',
    '#trf',
    '#female',
    '-efu-',
    '-cfs-',
    '-mfm-',
    '-osn-',
    'tff',
    'sfg',
    'zira',
    'jenny',
    'aria',
    'samantha',
    'google us english',
    'google uk english female',
  ];

  static const _maleSubstrings = [
    'ahmet',
    'tolga',
    'mehmet',
    'cem',
    'murat',
    'kerem',
    '#trm',
    '#male',
    '-ama-',
    '-tmc-',
    '-tma-',
    'david',
    'mark',
    'daniel',
    'google uk english male',
  ];

  static final _femaleWordTokens = [
    RegExp(r'\bfemale\b'),
    RegExp(r'\bwoman\b'),
    RegExp(r'\bkadin\b'),
    RegExp(r'\bbayan\b'),
    RegExp(r'\btrf\b'),
  ];

  static final _maleWordTokens = [
    RegExp(r'\bmale\b'),
    RegExp(r'\bman\b'),
    RegExp(r'\berkek\b'),
    RegExp(r'\bcan\b'),
    RegExp(r'\bguy\b'),
    RegExp(r'\btrm\b'),
  ];

  static String normalize(String raw) => raw
      .replaceAll('İ', 'i')
      .replaceAll('I', 'i')
      .toLowerCase()
      .replaceAll('\u0307', '')
      .replaceAll('ü', 'u')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c')
      .replaceAll('ş', 's')
      .replaceAll('ğ', 'g')
      .replaceAll('ı', 'i');

  static VoiceGenderHint classify(String name, {String voiceUri = ''}) {
    final norm = normalize('$name $voiceUri');
    if (norm.trim().isEmpty) return VoiceGenderHint.neutral;

    final isFemale =
        _femaleSubstrings.any(norm.contains) || _femaleWordTokens.any((re) => re.hasMatch(norm));
    final isMale =
        _maleSubstrings.any(norm.contains) || _maleWordTokens.any((re) => re.hasMatch(norm));

    if (isFemale && !isMale) return VoiceGenderHint.female;
    if (isMale && !isFemale) return VoiceGenderHint.male;
    return VoiceGenderHint.neutral;
  }

  static VoicePickOutcome? pickBestIndex(
    List<VoiceOptionInfo> allVoices, {
    required LangCode lang,
    required bool female,
    String? preferredVoiceName,
  }) {
    if (allVoices.isEmpty) return null;

    final prefix = lang == LangCode.tr ? 'tr' : 'en';
    final langIndices = <int>[
      for (int i = 0; i < allVoices.length; i++)
        if (allVoices[i].locale.toLowerCase().startsWith(prefix)) i,
    ];
    final pool = langIndices.isNotEmpty
        ? langIndices
        : [for (int i = 0; i < allVoices.length; i++) i];

    final targetGender = female ? VoiceGenderHint.female : VoiceGenderHint.male;

    if (preferredVoiceName != null && preferredVoiceName.trim().isNotEmpty) {
      final want = normalize(preferredVoiceName.trim());
      for (final idx in pool) {
        final v = allVoices[idx];
        final normName = normalize(v.name);
        if (normName == want || normName.contains(want)) {
          return VoicePickOutcome(
            index: idx,
            matchedExpectedGender: v.gender == targetGender || v.gender == VoiceGenderHint.neutral,
          );
        }
      }
    }

    // 1. Exact target gender match
    for (final idx in pool) {
      if (allVoices[idx].gender == targetGender) {
        return VoicePickOutcome(index: idx, matchedExpectedGender: true);
      }
    }

    // 2. Neutral / unknown gender (never opposite gender)
    for (final idx in pool) {
      if (allVoices[idx].gender == VoiceGenderHint.neutral) {
        return VoicePickOutcome(index: idx, matchedExpectedGender: true);
      }
    }

    // 3. Last resort: fallback to first language voice (mismatch reported via matchedExpectedGender=false)
    return VoicePickOutcome(index: pool.first, matchedExpectedGender: false);
  }
}
