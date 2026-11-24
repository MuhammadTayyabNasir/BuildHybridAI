import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';

import 'assistant_intent.dart';
import 'cloud_hybrid_ai.dart';
import 'hybrid_ai.dart';

HybridAi createPlatformHybridAi() => ChromeHybridAi(cloud: CloudHybridAi());

/// Web hybrid inference: Chrome's built-in Gemini Nano (Prompt API,
/// `LanguageModel`) answers on-device when the browser has it; otherwise, or
/// when it fails, cloud Gemini through Firebase AI Logic answers.
class ChromeHybridAi implements HybridAi {
  ChromeHybridAi({required this.cloud});

  final HybridAi cloud;
  JSObject? _session;

  JSObject? get _api =>
      globalContext.has('LanguageModel') ? globalContext['LanguageModel'] as JSObject : null;

  @override
  bool get available => true;

  @override
  Future<String> status() async {
    final api = _api;
    if (api == null) return 'unsupported';
    try {
      final s = await api.callMethod<JSPromise<JSString>>('availability'.toJS).toDart;
      return s.toDart; // available | downloadable | downloading | unavailable
    } catch (_) {
      return 'unavailable';
    }
  }

  Future<JSObject?> _ensureSession() async {
    if (_session != null) return _session;
    final api = _api;
    if (api == null) return null;
    final st = await status();
    // 'downloadable' starts the download on create(); answer from cloud
    // meanwhile, so only use the model once it is ready.
    if (st != 'available') {
      if (st == 'downloadable') {
        api.callMethod<JSPromise<JSObject>>('create'.toJS).toDart.ignore();
      }
      return null;
    }
    try {
      _session = await api.callMethod<JSPromise<JSObject>>('create'.toJS).toDart;
    } catch (e) {
      debugPrint('Chrome built-in model unavailable: $e');
    }
    return _session;
  }

  Future<String?> _prompt(String text, {Map<String, Object?>? schema}) async {
    final session = await _ensureSession();
    if (session == null) return null;
    try {
      // Each call gets a fresh clone so turns do not leak into each other.
      final s = await session.callMethod<JSPromise<JSObject>>('clone'.toJS).toDart;
      final opts = schema == null ? null : {'responseConstraint': schema}.jsify();
      final r = await s
          .callMethod<JSPromise<JSString>>('prompt'.toJS, text.toJS, opts)
          .toDart;
      s.callMethod<JSAny?>('destroy'.toJS);
      return r.toDart;
    } catch (e) {
      debugPrint('Chrome built-in prompt failed: $e');
      return null;
    }
  }

  @override
  Future<HybridAnswer?> parseIntent(String text, {required DateTime now}) async {
    final local = await _prompt(intentPrompt(text, todayLabel(now)), schema: intentJsonSchema);
    if (local != null && _looksLikeJson(local)) return HybridAnswer(local, AnswerSource.onDevice);
    return cloud.parseIntent(text, now: now);
  }

  @override
  Future<HybridAnswer?> generate(String prompt, {bool cloudOnly = false}) async {
    if (!cloudOnly) {
      final local = await _prompt(prompt);
      if (local != null && local.trim().isNotEmpty) return HybridAnswer(local, AnswerSource.onDevice);
    }
    return cloud.generate(prompt, cloudOnly: cloudOnly);
  }

  static bool _looksLikeJson(String s) {
    try {
      return jsonDecode(s) is Map;
    } catch (_) {
      return false;
    }
  }
}
