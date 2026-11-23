import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Microphone (speech_to_text) and speaker (flutter_tts) for the assistant.
/// Urdu uses the ur-PK locale; English uses en-US.
class VoiceIo {
  final _mic = SpeechToText();
  final _tts = FlutterTts();
  bool _ready = false;

  Future<bool> listen({
    required bool urdu,
    required void Function(String words, bool done) onWords,
    required void Function(String error) onError,
    void Function()? onDone,
  }) async {
    if (!_ready) {
      _ready = await _mic.initialize(
        onError: (e) => onError(e.errorMsg),
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') onDone?.call();
        },
      );
    }
    if (!_ready) return false;
    await _tts.stop();
    await _mic.listen(
      listenOptions: SpeechListenOptions(
        localeId: urdu ? 'ur-PK' : 'en-US',
        partialResults: true,
        cancelOnError: true,
        pauseFor: const Duration(seconds: 2),
        listenFor: const Duration(seconds: 20),
      ),
      onResult: (r) => onWords(r.recognizedWords, r.finalResult),
    );
    return true;
  }

  Future<void> stopListening() => _mic.stop();

  Future<void> say(String text, {required bool urdu}) async {
    try {
      await _tts.stop();
      await _tts.setLanguage(urdu ? 'ur-PK' : 'en-US');
      await _tts.setSpeechRate(0.48);
      await _tts.speak(text);
    } catch (_) {
      // Voice output is optional; the reply is always on screen.
    }
  }

  Future<void> dispose() async {
    await _mic.cancel();
    await _tts.stop();
  }
}
