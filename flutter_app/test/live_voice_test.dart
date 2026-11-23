import 'dart:async';
import 'package:bill_saathi/ui/voice_bar.dart';
import 'package:flutter_test/flutter_test.dart';

class BrowserAudio extends Fake implements VoiceAudio {
  late void Function(String, bool) result;
  final playback = Completer<void>();
  int starts = 0, stops = 0;
  @override
  Future<bool> start(
    bool urdu,
    void Function(String, bool) words,
    void Function(String) status,
    void Function(String) error,
  ) async {
    result = words;
    starts++;
    return true;
  }

  @override
  Future<void> say(String text, bool urdu) => playback.future;
  @override
  Future<void> stopMic() async {
    stops++;
  }

  @override
  Future<void> silence() async {}
}

void main() {
  testWidgets('partial-only speech submits once, replies, then listens again', (
    tester,
  ) async {
    final audio = BrowserAudio();
    final session = LiveVoice(audio: audio);
    final requests = <String>[];
    session.destinations.add((text, urdu) {
      requests.add(text);
      return 'Opened donations.';
    });
    await session.listen();
    final old = audio.result;
    old('چندہ', false);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(requests, ['چندہ']);
    expect(audio.stops, 1);
    expect(session.reply, 'Opened donations.');
    expect(session.turn, Turn.speaking);
    old('چندہ', true);
    expect(requests.length, 1);
    audio.playback.complete();
    await tester.pump();
    expect(audio.starts, 2);
    await tester.pump(const Duration(seconds: 13));
    expect(session.turn, Turn.idle);
    expect(session.notice, contains('No speech'));
    session.dispose();
  });
  testWidgets('ending during playback prevents mic restart', (tester) async {
    final audio = BrowserAudio();
    final session = LiveVoice(audio: audio);
    session.destinations.add((_, _) => 'Done');
    await session.listen();
    audio.result('cards', true);
    await tester.pump();
    await session.end();
    audio.playback.complete();
    await tester.pump();
    expect(session.turn, Turn.idle);
    expect(audio.starts, 1);
    session.dispose();
  });
}
