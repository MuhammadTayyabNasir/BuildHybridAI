import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import 'assistant_intent.dart';
import 'hybrid_ai.dart';

/// Cloud model used from Dart (same as the Kotlin bridge).
const pmaCloudModelName = 'gemini-3.8-flash';

/// Same instructions as `intentPrompt` in MainActivity.kt, for platforms that
/// call Firebase AI Logic from Dart (web, iOS).
String intentPrompt(String text, String today) => '''
You read short commands from a snack factory floor operator. They speak
English, Urdu, or Roman Urdu (Urdu in Latin letters). Extract the intent
and slots as JSON. Do not invent values that were not said.
Intents:
- count_entries: how many entries were made (e.g. "aaj main ne kitni entries ki")
- find_missing_entries: which scheduled readings are missing (e.g. "koi entry miss to nahi hui")
- add_th_reading: record temperature and/or humidity for a section
  (e.g. "Peri Peri section ki humidity 45 dal do")
- add_packing_entry: record a packing check (product, weight)
- open_screen: open a sheet or screen (e.g. "Peri Peri ki sheet kholo")
- daily_summary: a short report of today (e.g. "aaj ki report kya hai")
- unknown: anything else
Sections: chips, peri_peri (Peri Peri), nimko, wafer, chocolate.
Screens: dashboard, temp_humidity, entries, analytics, settings, automations.
Urdu number words count, e.g. "paintalis" = 45, "pachees" = 25.
Today is $today.
Operator said: "$text"''';

/// JSON Schema of the intent object (Chrome Prompt API responseConstraint).
const intentJsonSchema = {
  'type': 'object',
  'properties': {
    'intent': {
      'type': 'string',
      'enum': [
        'count_entries',
        'find_missing_entries',
        'add_th_reading',
        'add_packing_entry',
        'open_screen',
        'daily_summary',
        'unknown',
      ],
    },
    'section': {'type': 'string'},
    'temperature': {'type': ['number', 'null']},
    'humidity': {'type': ['number', 'null']},
    'shift': {'type': 'string'},
    'screen': {'type': 'string'},
    'period': {'type': 'string'},
    'product': {'type': 'string'},
    'weight': {'type': ['number', 'null']},
    'confidence': {'type': 'number'},
  },
  'required': ['intent', 'confidence'],
};

String todayLabel(DateTime now) => '${now.year}-${now.month}-${now.day} ${now.hour}:${now.minute}';

/// Cloud-only Gemini through the Dart Firebase AI Logic SDK. Used by itself
/// on iOS (until Apple Foundation Models are bridged) and as the fallback
/// behind Chrome's built-in model on web.
class CloudHybridAi implements HybridAi {
  CloudHybridAi({GenerativeModel? json, GenerativeModel? text})
      : _json = json,
        _text = text;

  GenerativeModel? _json;
  GenerativeModel? _text;

  GenerativeModel get _jsonModel => _json ??= FirebaseAI.googleAI().generativeModel(
        model: pmaCloudModelName,
        generationConfig: GenerationConfig(responseMimeType: 'application/json', temperature: 0),
      );

  GenerativeModel get _textModel =>
      _text ??= FirebaseAI.googleAI().generativeModel(model: pmaCloudModelName);

  @override
  bool get available => true;

  @override
  Future<String> status() async => 'cloud';

  @override
  Future<HybridAnswer?> parseIntent(String text, {required DateTime now}) async {
    try {
      final r = await _jsonModel.generateContent([Content.text(intentPrompt(text, todayLabel(now)))]);
      final t = r.text;
      return t == null || t.isEmpty ? null : HybridAnswer(t, AnswerSource.cloud);
    } catch (e) {
      debugPrint('Cloud intent failed: $e');
      return null;
    }
  }

  @override
  Future<HybridAnswer?> generate(String prompt, {bool cloudOnly = false}) async {
    try {
      final r = await _textModel.generateContent([Content.text(prompt)]);
      final t = r.text;
      return t == null || t.isEmpty ? null : HybridAnswer(t, AnswerSource.cloud);
    } catch (e) {
      debugPrint('Cloud generate failed: $e');
      return null;
    }
  }
}
