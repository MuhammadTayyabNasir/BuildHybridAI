import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceAudio {
  int _capture = 0;
  int _playback = 0;
  final _mic = SpeechToText();
  late final _tts = FlutterTts();
  Future<bool> start(
    bool urdu,
    void Function(String, bool) words,
    void Function(String) status,
    void Function(String) error,
  ) async {
    final capture = ++_capture;
    if (!await _mic.initialize(
      onStatus: status,
      onError: (e) => error(e.errorMsg),
    )) {
      return false;
    }
    if (capture != _capture) return false;
    await _mic.listen(
      listenOptions: SpeechListenOptions(
        localeId: urdu ? 'ur-PK' : 'en-US',
        partialResults: true,
        cancelOnError: true,
      ),
      onResult: (r) => words(r.recognizedWords, r.finalResult),
    );
    return true;
  }

  Future<void> stopMic() {
    ++_capture;
    return _mic.cancel();
  }

  Future<void> silence() async {
    ++_playback;
    await _tts.stop();
  }

  Future<void> say(String reply, bool urdu) async {
    final playback = ++_playback;
    if (await _tts.awaitSpeakCompletion(true) != 1) {
      throw StateError("Speech output unavailable");
    }
    await _tts.setLanguage(urdu ? 'ur-PK' : 'en-US');
    if (playback != _playback) return;
    if (await _tts.speak(reply) == 0) throw StateError('Voice unavailable');
  }
}

enum Turn { idle, listening, processing, speaking }

class LiveVoice extends ChangeNotifier {
  LiveVoice({VoiceAudio? audio}) : audio = audio ?? VoiceAudio();
  final VoiceAudio audio;
  final destinations = <String? Function(String, bool)>[];
  Turn turn = Turn.idle;
  bool urdu = false;
  String heard = '', reply = '', notice = '';
  Timer? limit, pause;
  int generation = 0;
  bool closed = false;
  String tr(String en, String ur) => urdu ? ur : en;
  bool valid(int id) => !closed && id == generation;
  void timers() {
    limit?.cancel();
    pause?.cancel();
  }

  Future<void> quiet(Future<void> Function() operation) async {
    try {
      await operation().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> end([String reason = '']) async {
    final id = ++generation;
    timers();
    turn = Turn.processing;
    notice = reason;
    notifyListeners();
    await Future.wait([quiet(audio.stopMic), quiet(audio.silence)]);
    if (valid(id)) {
      turn = Turn.idle;
      notifyListeners();
    }
  }

  Future<void> listen() async {
    final id = ++generation;
    timers();
    turn = Turn.listening;
    heard = '';
    notice = '';
    notifyListeners();
    limit = Timer(const Duration(seconds: 12), () => finish(id));
    try {
      final started = await audio.start(
        urdu,
        (text, finalResult) {
          if (!valid(id) || turn != Turn.listening || text.trim().isEmpty) {
            return;
          }
          heard = text.trim();
          notifyListeners();
          pause?.cancel();
          if (finalResult) {
            finish(id);
          } else {
            pause = Timer(const Duration(milliseconds: 1400), () => finish(id));
          }
        },
        status,
        error,
      );
      // Permission prompts can outlive a cancelled turn.
      if (!valid(id) && turn == Turn.idle) {
        await quiet(audio.stopMic);
        return;
      }
      if (valid(id) && turn == Turn.listening && !started) error('unavailable');
    } catch (_) {
      if (valid(id) && turn == Turn.listening) error('unavailable');
    }
  }

  void status(String value) {
    if (closed ||
        turn != Turn.listening ||
        !(value == 'done' || value == 'notListening')) {
      return;
    }
    final id = generation;
    pause?.cancel();
    pause = Timer(const Duration(milliseconds: 450), () => finish(id));
  }

  void error(String value) {
    if (closed || turn != Turn.listening) return;
    if (heard.isNotEmpty) {
      finish(generation);
      return;
    }
    end(
      tr(
        'Voice input stopped ($value). Check Chrome microphone access or type your request.',
        'آواز دستیاب نہیں۔ مائیکروفون چیک کریں یا لکھ کر پوچھیں۔',
      ),
    );
  }

  Future<void> finish(int id) async {
    if (!valid(id) || turn != Turn.listening) return;
    timers();
    turn = Turn.processing;
    notifyListeners();
    await quiet(audio.stopMic);
    if (!valid(id)) return;
    if (heard.isEmpty) {
      turn = Turn.idle;
      notice = tr(
        'No speech heard. Tap to retry or type your request.',
        'آواز نہیں آئی۔ دوبارہ بولیں یا لکھیں۔',
      );
      notifyListeners();
      return;
    }
    String? result;
    for (final route in destinations.reversed.toList()) {
      result = route(heard, urdu);
      if (result != null) break;
    }
    if (result == null) {
      await end();
      return;
    }
    reply = result;
    turn = Turn.speaking;
    notifyListeners();
    try {
      await audio.say(result, urdu).timeout(const Duration(seconds: 12));
    } catch (_) {
      if (valid(id)) {
        await end(
          tr(
            'Audio unavailable. Your reply is shown above.',
            'آواز دستیاب نہیں۔ جواب اوپر موجود ہے۔',
          ),
        );
      }
      return;
    }
    if (valid(id)) await listen();
  }

  @override
  void dispose() {
    closed = true;
    ++generation;
    timers();
    if (turn != Turn.idle) {
      quiet(audio.stopMic);
      quiet(audio.silence);
    }
    super.dispose();
  }
}

class VoiceBar extends StatefulWidget {
  const VoiceBar({super.key, required this.live, required this.onRequest});
  final LiveVoice live;
  final String Function(String, bool) onRequest;
  @override
  State<VoiceBar> createState() => _VoiceBarState();
}

class _VoiceBarState extends State<VoiceBar> {
  String? dispatch(String text, bool urdu) =>
      mounted && ModalRoute.of(context)?.isCurrent == true
      ? widget.onRequest(text, urdu)
      : null;
  @override
  void initState() {
    super.initState();
    widget.live.destinations.add(dispatch);
  }

  @override
  void dispose() {
    widget.live.destinations.remove(dispatch);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.live,
    builder: (context, _) {
      final v = widget.live;
      final listening = v.turn == Turn.listening;
      final speaking = v.turn == Turn.speaking;
      return Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (v.heard.isNotEmpty)
                Text(v.heard, maxLines: 2, overflow: TextOverflow.ellipsis),
              if (v.reply.isNotEmpty)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    v.reply,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<bool>(
                    value: v.urdu,
                    items: const [
                      DropdownMenuItem(value: false, child: Text('English')),
                      DropdownMenuItem(value: true, child: Text('اردو')),
                    ],
                    onChanged: v.turn == Turn.idle
                        ? (value) => setState(() => v.urdu = value!)
                        : null,
                  ),
                  FilledButton.icon(
                    icon: Icon(
                      listening
                          ? Icons.graphic_eq
                          : speaking
                          ? Icons.volume_up
                          : Icons.mic,
                    ),
                    label: Text(
                      listening
                          ? v.tr('Finish turn', 'بات مکمل')
                          : speaking
                          ? v.tr('Interrupt', 'درمیان میں بولیں')
                          : v.turn == Turn.processing
                          ? v.tr('One moment…', 'ایک لمحہ…')
                          : v.tr('Talk live', 'بات کریں'),
                    ),
                    onPressed: v.turn == Turn.processing
                        ? null
                        : () async {
                            if (listening) {
                              await v.finish(v.generation);
                            } else if (speaking) {
                              await v.end();
                              if (mounted && v.turn == Turn.idle) {
                                await v.listen();
                              }
                            } else {
                              await v.listen();
                            }
                          },
                  ),
                  if (v.turn != Turn.idle)
                    IconButton(
                      tooltip: v.tr('End conversation', 'گفتگو ختم کریں'),
                      icon: const Icon(Icons.call_end),
                      onPressed: () => v.end(),
                    ),
                ],
              ),
              Text(
                v.notice.isNotEmpty
                    ? v.notice
                    : v.turn == Turn.idle
                    ? v.tr(
                        'Speak a service name. Your speech provider may process audio.',
                        'صرف سروس کا نام بولیں۔ آواز آپ کے اسپیچ فراہم کنندہ تک جا سکتی ہے۔',
                      )
                    : listening
                    ? v.tr(
                        'Listening… pause when finished.',
                        'سن رہا ہوں… بات ختم کرکے رکیں۔',
                      )
                    : speaking
                    ? v.tr('Buddy is speaking', 'ساتھی بول رہا ہے')
                    : v.tr('Preparing reply…', 'جواب تیار ہو رہا ہے…'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    },
  );
}
