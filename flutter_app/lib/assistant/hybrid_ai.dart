import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'assistant_intent.dart';

/// Result of one Firebase AI Logic hybrid call.
class HybridAnswer {
  const HybridAnswer(this.text, this.source);
  final String text;
  final AnswerSource source;
}

/// Dart side of the Kotlin bridge in `MainActivity.kt` (channel
/// `pma/hybrid_ai`). The Android Firebase AI Logic SDK runs Gemini Nano
/// on-device when available and falls back to cloud Gemini otherwise
/// (`InferenceMode.PREFER_ON_DEVICE`), and reports which one answered.
abstract class HybridAi {
  bool get available;

  /// 'available' | 'downloadable' | 'downloading' | 'unavailable' | 'unsupported'
  Future<String> status();

  /// Operator command -> strict JSON intent. Null when no model could answer.
  Future<HybridAnswer?> parseIntent(String text, {required DateTime now});

  /// Free text generation. [cloudOnly] skips the on-device model for long
  /// reports that exceed the on-device context.
  Future<HybridAnswer?> generate(String prompt, {bool cloudOnly = false});
}

class ChannelHybridAi implements HybridAi {
  ChannelHybridAi({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('pma/hybrid_ai');

  final MethodChannel _channel;

  @override
  bool get available =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<String> status() async {
    if (!available) return 'unsupported';
    try {
      return await _channel.invokeMethod<String>('status') ?? 'unavailable';
    } catch (_) {
      return 'unavailable';
    }
  }

  @override
  Future<HybridAnswer?> parseIntent(String text, {required DateTime now}) async {
    if (!available) return null;
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('parseIntent', {
        'text': text,
        'today': '${now.year}-${now.month}-${now.day} ${now.hour}:${now.minute}',
      });
      final json = r?['json'];
      if (json is! String || json.isEmpty) return null;
      return HybridAnswer(json, AnswerSource.fromChannel(r?['source'] as String?));
    } catch (e) {
      debugPrint('Hybrid intent failed: $e');
      return null;
    }
  }

  @override
  Future<HybridAnswer?> generate(String prompt, {bool cloudOnly = false}) async {
    if (!available) return null;
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('generate', {
        'prompt': prompt,
        'cloudOnly': cloudOnly,
      });
      final text = r?['text'];
      if (text is! String || text.isEmpty) return null;
      return HybridAnswer(text, AnswerSource.fromChannel(r?['source'] as String?));
    } catch (e) {
      debugPrint('Hybrid generate failed: $e');
      return null;
    }
  }
}
