import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';

import '../assistant/assistant_intent.dart';
import '../assistant/hybrid_ai.dart';
import 'extracted_form.dart';

/// Cloud model used by the Dart side (same as the Kotlin bridge).
const pmaCloudModel = 'gemini-3.8-flash';

/// Reads scanned pages / photos with cloud Gemini (vision), through Firebase
/// AI Logic so App Check protects the call. Works on Android, iOS and web.
class CloudFormReader {
  CloudFormReader({GenerativeModel? model})
      : _model = model ??
            FirebaseAI.googleAI().generativeModel(
              model: pmaCloudModel,
              generationConfig: GenerationConfig(
                responseMimeType: 'application/json',
                temperature: 0,
              ),
            );

  final GenerativeModel _model;

  Future<String> read(Uint8List bytes, String mimeType) async {
    final res = await _model.generateContent([
      Content.multi([TextPart(formExtractionInstructions), InlineDataPart(mimeType, bytes)]),
    ]);
    final text = res.text;
    if (text == null || text.trim().isEmpty) throw StateError('empty reply');
    return text;
  }
}

/// Structures OCR text from the phone's camera with the hybrid model:
/// Gemini Nano on-device when available (fully offline with on-device OCR),
/// cloud Gemini otherwise.
class OcrTextStructurer {
  const OcrTextStructurer(this.ai);
  final HybridAi ai;

  Future<({ExtractedPage? page, AnswerSource source})> structure(String ocrText) async {
    final answer = await ai.generate(
      '$formExtractionInstructions\n'
      'The page was read by OCR; columns may be out of order and a ditto mark may appear as '
      '" or 11. OCR text:\n$ocrText',
    );
    if (answer == null) return (page: null, source: AnswerSource.rules);
    final page = ExtractedPage.parseModel(answer.text, 1);
    if (page != null) DittoFill.apply(page.rows);
    return (page: page, source: answer.source);
  }
}
