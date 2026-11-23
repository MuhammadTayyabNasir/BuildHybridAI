import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceBar extends StatefulWidget {
  const VoiceBar({super.key, required this.urdu, required this.onRequest});
  final bool urdu;
  final String Function(String, bool) onRequest;
  @override
  State<VoiceBar> createState() => _VoiceBarState();
}

class _VoiceBarState extends State<VoiceBar> {
  final speech = SpeechToText();
  late bool urdu = widget.urdu;
  bool active = false;
  int session = 0;
  String message = '';
  static _VoiceBarState? listener;
  static void speechEnded(bool error) {
    final current = listener;
    if (current == null || !current.mounted || !current.active) return;
    final message = error
        ? (current.urdu
              ? "مائیکروفون چیک کریں یا لکھ کر پوچھیں۔"
              : "Check microphone access or type your request.")
        : (current.urdu ? "دوبارہ بولیں" : "Tap to speak again");
    current.update(message, listening: false);
  }

  static final speaker = FlutterTts();

  void update(String value, {bool? listening}) {
    if (mounted) {
      setState(() {
        message = value;
        active = listening ?? active;
      });
    }
  }

  Future<void> listen() async {
    if (active) {
      ++session;
      update('', listening: false);
      await speech.cancel();
      return;
    }
    final id = ++session;
    update(urdu ? 'سن رہا ہوں…' : 'Listening…', listening: true);
    try {
      try {
        await speaker.stop();
      } catch (_) {}
      listener = this;
      final ok = await speech.initialize(
        onError: (_) => speechEnded(true),
        onStatus: (status) {
          if (status == "done") speechEnded(false);
        },
      );
      if (!mounted || id != session) return;
      if (!ok) {
        update(
          urdu
              ? 'مائیکروفون دستیاب نہیں ہے۔'
              : 'Microphone unavailable. You can type your request.',
          listening: false,
        );
        return;
      }
      await speech.listen(
        listenOptions: SpeechListenOptions(
          localeId: urdu ? 'ur-PK' : 'en-US',
          cancelOnError: true,
        ),
        onResult: (result) async {
          if (!mounted ||
              id != session ||
              ModalRoute.of(context)?.isCurrent != true) {
            return;
          }
          final words = result.recognizedWords.trim();
          if (words.isEmpty) return;
          update(words);
          if (!result.finalResult) return;
          ++session;
          update(words, listening: false);
          final language = urdu ? 'ur-PK' : 'en-US';
          final response = widget.onRequest(words, urdu);
          try {
            await speaker.setLanguage(language);
            await speaker.speak(response);
          } catch (_) {}
        },
      );
    } catch (_) {
      if (mounted && id == session) {
        update(
          urdu
              ? 'آواز دستیاب نہیں۔ لکھ کر پوچھیں۔'
              : 'Voice unavailable. Type your request.',
          listening: false,
        );
      }
    }
  }

  @override
  void dispose() {
    ++session;
    if (listener == this) {
      listener = null;
      if (active) speech.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<bool>(
                value: urdu,
                items: const [
                  DropdownMenuItem(value: false, child: Text('English')),
                  DropdownMenuItem(value: true, child: Text('اردو')),
                ],
                onChanged: active ? null : (v) => setState(() => urdu = v!),
              ),
              FilledButton.icon(
                onPressed: listen,
                icon: Icon(active ? Icons.stop : Icons.mic),
                label: Text(
                  active
                      ? (urdu ? 'روکیں' : 'Cancel listening')
                      : (urdu ? 'ساتھی سے بات کریں' : 'Speak to Buddy'),
                ),
              ),
            ],
          ),
          Text(
            urdu
                ? 'صرف سروس کا نام بولیں۔ نجی تفصیل لکھیں۔'
                : 'Speak a service name. Type private details; your speech provider may process audio.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (message.isNotEmpty)
            Semantics(liveRegion: true, child: Text(message)),
        ],
      ),
    ),
  );
}
