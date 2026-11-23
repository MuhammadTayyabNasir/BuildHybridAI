import 'assistant_intent.dart';

/// Deterministic fallback used when neither Gemini Nano nor the cloud model
/// can answer (offline phone without Nano). Understands English, Roman Urdu and
/// common Urdu-script words, including Urdu number words ("paintalis" = 45).
class RulesParser {
  const RulesParser();

  AssistantIntent parse(String input) {
    final text = normalize(input);
    final section = AssistantIntent.normalizeSection(_findSection(text));
    final shift = _has(text, const ['subah', 'morning', 'din ', 'صبح'])
        ? 'morning'
        : _has(text, const ['raat', 'night', 'shaam', 'evening', 'رات', 'شام'])
            ? 'night'
            : null;

    if (_has(text, _openWords)) {
      return AssistantIntent(
        type: IntentType.openScreen,
        source: AnswerSource.rules,
        section: section,
        screen: _screen(text),
        confidence: 0.9,
      );
    }
    if (_has(text, _missingWords)) {
      return AssistantIntent(
        type: IntentType.findMissingEntries,
        source: AnswerSource.rules,
        section: section,
        period: _period(text),
        confidence: 0.9,
      );
    }
    final reading = readingValues(text);
    if (reading.temperature != null || reading.humidity != null) {
      return AssistantIntent(
        type: IntentType.addThReading,
        source: AnswerSource.rules,
        section: section,
        temperature: reading.temperature,
        humidity: reading.humidity,
        shift: shift,
        confidence: reading.guessed ? 0.6 : 0.9,
      );
    }
    if (_has(text, _summaryWords)) {
      return AssistantIntent(
        type: IntentType.dailySummary,
        source: AnswerSource.rules,
        section: section,
        period: _period(text),
        confidence: 0.9,
      );
    }
    if (_has(text, _countWords)) {
      return AssistantIntent(
        type: IntentType.countEntries,
        source: AnswerSource.rules,
        section: section,
        period: _period(text),
        confidence: 0.9,
      );
    }
    if (_has(text, const ['weight', 'wazan', 'gram', 'packing entry', 'وزن'])) {
      return AssistantIntent(
        type: IntentType.addPackingEntry,
        source: AnswerSource.rules,
        section: section,
        weight: firstNumber(text),
        confidence: 0.6,
      );
    }
    return const AssistantIntent(
      type: IntentType.unknown,
      source: AnswerSource.rules,
      confidence: 0,
    );
  }

  // ---------------------------------------------------------------- replies

  /// Classifies a reply to a read-back: yes, no, or "no, make it 48".
  ConfirmReply confirmReply(String input) {
    final text = normalize(input);
    final value = firstNumber(text);
    final no = _hasWord(text, _noWords);
    if (no && value != null) {
      final reading = readingValues(text);
      return ConfirmReply(
        ConfirmKind.correct,
        value: value,
        temperature: reading.temperature,
        humidity: reading.humidity,
      );
    }
    if (no) return const ConfirmReply(ConfirmKind.no);
    if (_hasWord(text, _yesWords)) return const ConfirmReply(ConfirmKind.yes);
    if (value != null) {
      final reading = readingValues(text);
      return ConfirmReply(
        ConfirmKind.correct,
        value: value,
        temperature: reading.temperature,
        humidity: reading.humidity,
      );
    }
    return const ConfirmReply(ConfirmKind.unclear);
  }

  /// "ab se confirm ki zaroorat nahi" -> true (fast mode on),
  /// "confirm kiya karo" / "confirmation on" -> false, otherwise null.
  bool? fastModeCommand(String input) {
    final t = normalize(input);
    final mentionsConfirm =
        _has(t, const ['confirm', 'tasdeeq', 'poocho', 'pucho', 'تصدیق']);
    if (!mentionsConfirm && !_has(t, const ['fast mode', 'fast'])) return null;
    if (_has(t, const ['zaroorat nahi', 'zarurat nahi', 'mat poocho',
        'mat pucho', 'no need', 'fast mode on', 'band karo', 'off', 'ضرورت نہیں'])) {
      return true;
    }
    if (_has(t, const ['fast mode off', 'confirm karo', 'confirm kiya karo',
        'poocha karo', 'pucha karo', 'confirmation on', 'tasdeeq karo'])) {
      return false;
    }
    return null;
  }

  bool isBatchStart(String input) => _has(normalize(input), const [
        'batch', 'bulk', 'ek saath', 'aik saath', 'sab ek sath', 'بیچ',
      ]) &&
      !isBatchEnd(input);

  bool isBatchEnd(String input) => _hasWord(normalize(input), const [
        'bas', 'done', 'khatam', 'finish', 'finished', 'ho gaya', 'ho gya',
        'mukammal', 'بس', 'ختم',
      ]);

  /// "number 3 humidity 48", "3 number 48", "number 3 hatao".
  ItemCommand? itemCommand(String input) {
    final t = normalize(input);
    final m = RegExp(r'(?:number|nambar|item|نمبر)\s*(\d+)').firstMatch(t) ??
        RegExp(r'(\d+)\s*(?:number|nambar|نمبر)').firstMatch(t);
    if (m == null) return null;
    final item = int.parse(m[1]!);
    final rest = t.replaceRange(m.start, m.end, ' ');
    final remove = _has(rest, const ['hatao', 'hata do', 'remove', 'delete',
      'nikalo', 'nikal do', 'cancel', 'ہٹاؤ', 'نکالو']);
    final r = readingValues(rest);
    return ItemCommand(
      item: item,
      remove: remove,
      temperature: r.temperature,
      humidity: r.humidity,
      value: firstNumber(rest),
    );
  }

  bool isUndo(String input) => _has(normalize(input),
      const ['undo', 'wapas lo', 'wapis lo', 'last entry delete', 'pichli entry hata', 'واپس']);

  // ---------------------------------------------------------------- numbers

  /// Lower-cases, converts Urdu digits and number words to digits.
  static String normalize(String input) {
    var t = ' ${input.toLowerCase()} ';
    const urduDigits = '۰۱۲۳۴۵۶۷۸۹';
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    for (var i = 0; i < 10; i++) {
      t = t.replaceAll(urduDigits[i], '$i').replaceAll(arabicDigits[i], '$i');
    }
    t = t.replaceAll(RegExp(r'[,?!؟،۔]'), ' ').replaceAll('%', ' percent ');
    // English compounds: "forty five" -> 45
    t = t.replaceAllMapped(
      RegExp(r'\b(twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)[\s-]+(one|two|three|four|five|six|seven|eight|nine)\b'),
      (m) => ' ${_englishTens[m[1]]! + _englishUnits[m[2]]!} ',
    );
    final words = t.split(RegExp(r'\s+'));
    final out = <String>[];
    for (final w in words) {
      final n = _numberWords[w];
      out.add(n == null ? w : '$n');
    }
    t = ' ${out.join(' ')} ';
    // "45 point 5" / "45 ashariya 5"
    t = t.replaceAllMapped(
      RegExp(r'(\d+)\s+(point|ashariya|اعشاریہ)\s+(\d+)'),
      (m) => '${m[1]}.${m[3]}',
    );
    return t;
  }

  static double? firstNumber(String normalized) {
    final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(normalized);
    return m == null ? null : double.tryParse(m[1]!);
  }

  /// Pulls temperature / humidity values from a normalized sentence.
  static ({double? temperature, double? humidity, bool guessed}) readingValues(
      String t) {
    double? temp;
    double? hum;
    const num = r'(\d+(?:\.\d+)?)';
    final tempKey = r'(temp\w*|tapman|darja\w*|degree\w*|ٹمپریچر|درجہ)';
    final humKey = r'(humid\w*|nami|nmi|moisture|ہیومیڈیٹی|نمی)';
    final tAfter = RegExp('$tempKey\\D{0,24}?$num').firstMatch(t);
    final hAfter = RegExp('$humKey\\D{0,24}?$num').firstMatch(t);
    final tBefore = RegExp('$num\\s*(degree\\w*|c\\b|celsius|°)').firstMatch(t);
    final hBefore = RegExp('$num\\s*(percent|fisad|فیصد)').firstMatch(t);
    if (tBefore != null) temp = double.parse(tBefore[1]!);
    if (hBefore != null) hum = double.parse(hBefore[1]!);
    if (tAfter != null) temp ??= double.parse(tAfter[2]!);
    if (hAfter != null) hum ??= double.parse(hAfter[2]!);
    // "humidity 30 aur temperature 25": the lazy match above can grab the
    // same number for both keys; keep the closest one to each keyword.
    if (temp != null && hum != null && temp == hum && tAfter != null &&
        hAfter != null) {
      final all = RegExp(num).allMatches(t).toList();
      if (all.length >= 2) {
        final hFirst = hAfter.start < tAfter.start;
        hum = double.parse(all[hFirst ? 0 : 1][1]!);
        temp = double.parse(all[hFirst ? 1 : 0][1]!);
      }
    }
    var guessed = false;
    final hasTempKey = RegExp(tempKey).hasMatch(t);
    final hasHumKey = RegExp(humKey).hasMatch(t);
    if (temp == null && hum == null && (hasTempKey || hasHumKey)) {
      final v = firstNumber(t);
      if (v != null) {
        guessed = true;
        if (hasHumKey) {
          hum = v;
        } else {
          temp = v;
        }
      }
    }
    return (temperature: temp, humidity: hum, guessed: guessed);
  }

  // ---------------------------------------------------------------- helpers

  static bool _has(String t, List<String> keys) => keys.any(t.contains);

  static bool _hasWord(String t, List<String> words) {
    final tokens = t.split(RegExp(r'\s+')).toSet();
    return words.any((w) => w.contains(' ') ? t.contains(w) : tokens.contains(w));
  }

  static String? _findSection(String t) {
    for (final k in const ['peri', 'پیری', 'chip', 'چپس', 'nimko', 'namko',
        'نمکو', 'wafer', 'ویفر', 'choc', 'چاکلیٹ']) {
      if (t.contains(k)) return k;
    }
    return null;
  }

  static String _period(String t) {
    if (_has(t, const ['kal', 'yesterday', 'کل'])) return 'yesterday';
    if (_has(t, const ['hafte', 'week', 'haftay', 'ہفتے'])) return 'week';
    return 'today';
  }

  static String _screen(String t) {
    if (_has(t, const ['setting', 'سیٹنگ'])) return 'settings';
    if (_has(t, const ['analytic', 'report', 'graph', 'chart', 'رپورٹ'])) {
      return 'analytics';
    }
    if (_has(t, const ['temp', 'humid', 'nami', 'tapman', 'نمی', 'ٹمپریچر'])) {
      return 'temp_humidity';
    }
    if (_has(t, const ['dashboard', 'home', 'ڈیش'])) return 'dashboard';
    return 'entries';
  }

  static const _openWords = ['kholo', 'khol do', 'kholen', 'open', 'dikhao',
    'dikha do', 'show me', 'le chalo', 'کھولو', 'کھول', 'دکھاؤ'];
  static const _missingWords = ['miss', 'reh gayi', 'reh gaye', 'rah gayi',
    'rah gaye', 'reh gai', 'baqi', 'baaki', 'baki', 'chhoot', 'chhut', 'choot',
    'skipped', 'pending', 'رہ گئی', 'رہ گئے', 'مس', 'باقی'];
  static const _summaryWords = ['report kya', 'report batao', 'ki report',
    'ka report', 'summary', 'khulasa', 'kaisa raha', 'kaisi rahi', 'haal',
    'خلاصہ', 'رپورٹ'];
  static const _countWords = ['kitni', 'kitne', 'how many', 'count', 'ginti',
    'total', 'کتنی', 'کتنے'];
  static const _yesWords = ['haan', 'han', 'haa', 'ha', 'ji', 'jee', 'ok',
    'okay', 'theek', 'thik', 'theek hai', 'thik hai', 'sahi', 'save', 'confirm',
    'yes', 'yeah', 'kar do', 'ہاں', 'جی', 'ٹھیک', 'درست'];
  static const _noWords = ['nahi', 'nahin', 'nai', 'na', 'no', 'cancel', 'mat',
    'galat', 'نہیں', 'غلط'];

  static const _englishTens = {'twenty': 20, 'thirty': 30, 'forty': 40,
    'fifty': 50, 'sixty': 60, 'seventy': 70, 'eighty': 80, 'ninety': 90};
  static const _englishUnits = {'one': 1, 'two': 2, 'three': 3, 'four': 4,
    'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9};

  static const Map<String, int> _numberWords = {
    // English
    'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6,
    'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11, 'twelve': 12,
    'thirteen': 13, 'fourteen': 14, 'fifteen': 15, 'sixteen': 16,
    'seventeen': 17, 'eighteen': 18, 'nineteen': 19, 'twenty': 20,
    'thirty': 30, 'forty': 40, 'fifty': 50, 'sixty': 60, 'seventy': 70,
    'eighty': 80, 'ninety': 90, 'hundred': 100,
    // Roman Urdu
    'sifar': 0, 'aik': 1, 'ek': 1, 'teen': 3, 'tin': 3, 'char': 4,
    'chaar': 4, 'panch': 5, 'paanch': 5, 'chay': 6, 'chhe': 6, 'chhay': 6,
    'che': 6, 'saat': 7, 'aath': 8, 'aatth': 8, 'nau': 9, 'das': 10,
    'dus': 10, 'gyarah': 11, 'gyara': 11, 'barah': 12,
    'terah': 13, 'chaudah': 14, 'chauda': 14, 'chodah': 14,
    'pandrah': 15, 'pandra': 15, 'solah': 16, 'sola': 16, 'satrah': 17,
    'satra': 17, 'atharah': 18, 'athara': 18, 'unnees': 19, 'unees': 19,
    'unnis': 19, 'bees': 20, 'bis': 20, 'ikkees': 21, 'ikees': 21, 'ikkis': 21,
    'bais': 22, 'baees': 22, 'teis': 23, 'taees': 23, 'tees': 30,
    'chaubees': 24, 'chobees': 24, 'chobis': 24, 'pachees': 25,
    'pachchees': 25, 'pachis': 25, 'chabbees': 26, 'chabees': 26,
    'chabbis': 26, 'sattais': 27, 'sataees': 27, 'athais': 28,
    'athaees': 28, 'untees': 29, 'unatees': 29, 'untis': 29, 'tis': 30,
    'ikattees': 31, 'iktees': 31, 'ikattis': 31, 'battees': 32, 'batees': 32,
    'battis': 32, 'taintees': 33, 'tetees': 33, 'taintis': 33,
    'chauntees': 34, 'chontees': 34, 'chauntis': 34, 'paintees': 35,
    'pentees': 35, 'paintis': 35, 'chhattees': 36, 'chattees': 36,
    'chattis': 36, 'saintees': 37, 'sentees': 37, 'saintis': 37,
    'artees': 38, 'adtees': 38, 'artis': 38, 'untalees': 39, 'untalis': 39,
    'chalees': 40, 'chalis': 40, 'chaalis': 40, 'iktalees': 41,
    'iktalis': 41, 'bayalees': 42, 'byalis': 42, 'bayalis': 42,
    'taintalees': 43, 'tentalis': 43, 'taintalis': 43, 'chawalees': 44,
    'chawalis': 44, 'chavalis': 44, 'paintalees': 45, 'paintalis': 45,
    'pentalis': 45, 'paintaalis': 45, 'chhiyalees': 46, 'chiyalis': 46,
    'chhiyalis': 46, 'saintalees': 47, 'saintalis': 47, 'sentalis': 47,
    'artalees': 48, 'artalis': 48, 'adtalis': 48, 'unchaas': 49,
    'unchas': 49, 'pachaas': 50, 'pachas': 50, 'ikyavan': 51, 'ikawan': 51,
    'bavan': 52, 'bawan': 52, 'tirpan': 53, 'tirepan': 53, 'chavan': 54,
    'chawan': 54, 'pachpan': 55, 'chhappan': 56, 'chappan': 56,
    'sattavan': 57, 'satawan': 57, 'athavan': 58, 'athawan': 58,
    'unsath': 59, 'saath': 60, 'iksath': 61, 'basath': 62,
    'tirsath': 63, 'chausath': 64, 'painsath': 65, 'chhiyasath': 66,
    'sarsath': 67, 'arsath': 68, 'unhattar': 69, 'sattar': 70,
    'ikhattar': 71, 'bahattar': 72, 'tihattar': 73, 'chauhattar': 74,
    'pachhattar': 75, 'chhihattar': 76, 'sathattar': 77, 'athattar': 78,
    'unasi': 79, 'assi': 80, 'ikyasi': 81, 'bayasi': 82, 'tirasi': 83,
    'chaurasi': 84, 'pachasi': 85, 'chhiyasi': 86, 'sattasi': 87,
    'athasi': 88, 'navasi': 89, 'nabbe': 90, 'nawway': 90, 'ikyanve': 91,
    'banve': 92, 'tiranve': 93, 'chauranve': 94, 'pachanve': 95,
    'chhiyanve': 96, 'sattanve': 97, 'athanve': 98, 'ninyanve': 99,
    'sau': 100,
    // Urdu script (most common readings)
    'ایک': 1, 'تین': 3, 'چار': 4, 'پانچ': 5, 'چھ': 6, 'سات': 7,
    'آٹھ': 8, 'دس': 10, 'پندرہ': 15, 'بیس': 20, 'اکیس': 21,
    'بائیس': 22, 'تئیس': 23, 'چوبیس': 24, 'پچیس': 25, 'چھبیس': 26,
    'ستائیس': 27, 'اٹھائیس': 28, 'انتیس': 29, 'تیس': 30, 'اکتیس': 31,
    'بتیس': 32, 'تینتیس': 33, 'چونتیس': 34, 'پینتیس': 35, 'چھتیس': 36,
    'سینتیس': 37, 'اڑتیس': 38, 'انتالیس': 39, 'چالیس': 40, 'اکتالیس': 41,
    'بیالیس': 42, 'تینتالیس': 43, 'چوالیس': 44, 'پینتالیس': 45,
    'چھیالیس': 46, 'سینتالیس': 47, 'اڑتالیس': 48, 'انچاس': 49, 'پچاس': 50,
    'پچپن': 55, 'ساٹھ': 60, 'ستر': 70, 'اسی': 80, 'نوے': 90, 'سو': 100,
  };
}

enum ConfirmKind { yes, no, correct, unclear }

class ConfirmReply {
  const ConfirmReply(this.kind, {this.value, this.temperature, this.humidity});
  final ConfirmKind kind;
  final double? value;
  final double? temperature;
  final double? humidity;
}

class ItemCommand {
  const ItemCommand({
    required this.item,
    required this.remove,
    this.temperature,
    this.humidity,
    this.value,
  });
  final int item;
  final bool remove;
  final double? temperature;
  final double? humidity;
  final double? value;
}
