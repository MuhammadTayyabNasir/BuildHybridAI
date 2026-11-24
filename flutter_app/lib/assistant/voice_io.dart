import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Microphone (speech_to_text) and speaker (flutter_tts) for the assistant.
///
/// Built for a back-and-forth conversation: the microphone waits several
/// seconds of silence before it decides the operator has finished, and
/// [say] returns only when speaking ends so the screen can listen again.
///
/// Urdu needs an Urdu text-to-speech voice. Many phones ship a vendor TTS
/// engine without one, so Google's engine is preferred when installed;
/// [urduVoice] tells the screen whether the phone can actually speak Urdu.
class VoiceIo {
  final _mic = SpeechToText();
  final _tts = FlutterTts();
  bool _micReady = false;
  bool _ttsReady = false;
  bool _urduVoice = false;

  /// Whether an Urdu voice is installed. Without one Urdu replies are shown
  /// on screen but not spoken (an English voice reads Urdu script as nothing).
  bool get urduVoice => _urduVoice;

  Future<void> _initTts() async {
    if (_ttsReady) return;
    _ttsReady = true;
    try {
      await _tts.awaitSpeakCompletion(true);
      if (defaultTargetPlatform == TargetPlatform.android) {
        final engines = await _tts.getEngines;
        if (engines is List && engines.contains('com.google.android.tts')) {
          await _tts.setEngine('com.google.android.tts');
        }
      }
      final ok = await _tts.isLanguageAvailable('ur-PK');
      _urduVoice = ok == true || ok == 1;
    } catch (_) {
      _urduVoice = false;
    }
  }

  Future<void> warmUp() => _initTts();

  Future<bool> listen({
    required bool urdu,
    required void Function(String words, bool done) onWords,
    required void Function(String error) onError,
    void Function()? onDone,
  }) async {
    if (!_micReady) {
      _micReady = await _mic.initialize(
        onError: (e) => onError(e.errorMsg),
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') onDone?.call();
        },
      );
    }
    if (!_micReady) return false;
    await _tts.stop();
    await _mic.listen(
      listenOptions: SpeechListenOptions(
        localeId: urdu ? 'ur-PK' : 'en-US',
        partialResults: true,
        cancelOnError: true,
        // Operators pause to read a gauge mid-sentence; 2 s cut them off.
        pauseFor: const Duration(seconds: 4),
        listenFor: const Duration(seconds: 60),
        listenMode: ListenMode.dictation,
      ),
      onResult: (r) => onWords(r.recognizedWords, r.finalResult),
    );
    return true;
  }

  Future<void> stopListening() => _mic.stop();

  Future<void> stopSpeaking() => _tts.stop();

  /// Speaks [text] and completes when speaking ends. Returns false when the
  /// phone has no voice for the language and nothing was said.
  Future<bool> say(String text, {required bool urdu}) async {
    await _initTts();
    if (urdu && !_urduVoice) return false;
    try {
      await _tts.stop();
      await _tts.setLanguage(urdu ? 'ur-PK' : 'en-US');
      await _tts.setSpeechRate(0.55);
      await _tts.speak(text);
      return true;
    } catch (_) {
      // Voice output is optional; the reply is always on screen.
      return false;
    }
  }

  Future<void> dispose() async {
    await _mic.cancel();
    await _tts.stop();
  }
}
