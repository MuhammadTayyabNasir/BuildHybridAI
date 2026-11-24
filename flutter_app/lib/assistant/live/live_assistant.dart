import 'dart:async';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import '../assistant_service.dart';
import 'live_audio.dart';

/// Live model; override with --dart-define=PMA_LIVE_MODEL=... when Google
/// renames it.
const pmaLiveModel = String.fromEnvironment(
  'PMA_LIVE_MODEL',
  defaultValue: 'gemini-2.5-flash-native-audio-preview-09-2025',
);

/// One line in the live transcript.
class LiveLine {
  LiveLine(this.text, {required this.fromUser});
  String text;
  final bool fromUser;
  bool finished = false;
}

enum LiveState { idle, connecting, listening, speaking, error }

/// Gemini Live (Firebase AI Logic) as a voice front end for PMA.
///
/// Gemini hears the operator (Urdu, Roman Urdu or English), talks back in a
/// natural voice and can be interrupted mid-sentence. It never touches data
/// itself: every request is passed to the `pma` tool, which is the same
/// [AssistantService] the text assistant uses. So validation, the
/// green/yellow/red limits, the read-back and the "haan before saving" rule
/// are unchanged, and the model can only say "saved" when the tool says so.
class LiveAssistant extends ChangeNotifier {
  LiveAssistant({
    required this.service,
    this.onNavigate,
    this.onReply,
    LiveAudio? audio,
  }) : _audio = audio ?? LiveAudio();

  final AssistantService service;

  /// Called when the assistant opens a screen (the session ends first).
  final void Function(NavTarget target)? onNavigate;

  /// Each tool reply, so the screen can show its status chips.
  final void Function(AssistantReply reply)? onReply;

  final LiveAudio _audio;
  LiveSession? _session;
  StreamSubscription<LiveServerResponse>? _sub;

  /// Bumped on every start/stop; async work from an older session checks it
  /// and backs out, so a late connect or timer cannot revive a stopped one.
  int _generation = 0;
  bool _disposed = false;
  Timer? _navTimer;

  /// Counts the operator's spoken turns. A question the app asked (pending)
  /// may only be answered after the operator has spoken again, so the model
  /// cannot ask and answer "haan" for them in one turn.
  int _operatorTurns = 0;
  int? _pendingAtTurn;

  LiveState state = LiveState.idle;
  String? error;
  final lines = <LiveLine>[];
  LiveLine? _userLine;
  LiveLine? _modelLine;

  bool get active => state != LiveState.idle && state != LiveState.error;

  static const _instructions = '''
You are PMA, the voice assistant of a snack factory's Packing & Monitoring App.
You talk with floor operators and supervisors who speak Urdu, Roman Urdu or
English. Always answer in the language they used; when they speak Urdu, reply
in natural, simple spoken Urdu. Keep every reply to one or two short sentences.

You do not know the factory's data yourself. For EVERY request about readings,
packing checks, entries, counts, missed entries, reports, settings, opening a
screen, fast mode, batch mode, undo, or any yes/no answer to a question the app
asked, call the tool "pma" with the operator's request as a short command in
English or Roman Urdu, keeping every number exactly as said. Examples:
"peri peri humidity 45", "chips machine 3 masala weight 50 51 49 50 leakage
theek printing theek", "how many entries today", "aaj koi entry miss to nahi
hui", "aaj ki report", "open automations", "haan", "nahi", "undo".

Then tell the operator what the tool replied, in their language, without
adding facts. Never say something was saved unless the tool result has
saved=true. If the tool asks a question (pending=true), ask it and wait. Do not
invent numbers, products or machines. Small talk and greetings need no tool.''';

  Future<void> start() async {
    if (active || _disposed) return;
    final gen = ++_generation;
    bool stale() => _disposed || gen != _generation;
    _set(LiveState.connecting);
    error = null;
    try {
      final allowed = await _audio.hasMicPermission();
      if (stale()) return;
      if (!allowed) {
        throw StateError('Microphone permission is needed for live voice.');
      }
      final model = FirebaseAI.googleAI().liveGenerativeModel(
        model: pmaLiveModel,
        systemInstruction: Content.system(_instructions),
        liveGenerationConfig: LiveGenerationConfig(
          responseModalities: [ResponseModalities.audio],
          speechConfig: SpeechConfig(voiceName: 'Kore'),
          inputAudioTranscription: AudioTranscriptionConfig(),
          outputAudioTranscription: AudioTranscriptionConfig(),
        ),
        tools: [
          Tool.functionDeclarations([
            FunctionDeclaration(
              'pma',
              'Runs one operator request in the PMA app and returns its reply. '
                  'Use it for all factory data, entries, reports, navigation and yes/no answers.',
              parameters: {
                'command': Schema.string(
                  description:
                      'The request as a short English or Roman Urdu command, numbers exactly as said.',
                ),
              },
            ),
          ]),
        ],
      );
      final session = await model.connect().timeout(const Duration(seconds: 15));
      if (stale()) {
        // Stopped while connecting: close the late connection, do not use it.
        unawaited(session.close().catchError((_) {}));
        return;
      }
      _session = session;
      _operatorTurns = 0;
      _pendingAtTurn = null;
      _sub = session.receive().listen(
            (r) => _onMessage(r).catchError(
              (Object e) => _failIf(gen, 'Live voice stopped: $e'),
            ),
            onError: (Object e) => _failIf(gen, 'Live connection error: $e'),
            onDone: () {
              if (gen == _generation && active) _fail('The live connection closed.');
            },
          );
      await _audio.startMic(
        (chunk) => _session?.sendAudioRealtime(InlineDataPart(LiveAudio.inputMime, chunk)),
        onError: (e) => _failIf(gen, 'Microphone stopped: $e'),
      );
      if (stale()) {
        await _teardown();
        return;
      }
      _set(LiveState.listening);
    } catch (e) {
      if (stale()) return;
      await _teardown();
      _fail(e is StateError ? e.message : 'Could not start live voice: $e');
    }
  }

  Future<void> stop() async {
    _generation++;
    await _teardown();
    if (!_disposed) _set(LiveState.idle);
  }

  void _failIf(int gen, String message) {
    if (gen == _generation && !_disposed) _fail(message);
  }

  Future<void> _teardown() async {
    _navTimer?.cancel();
    _navTimer = null;
    final session = _session;
    _session = null;
    await _sub?.cancel();
    _sub = null;
    await _audio.dispose();
    if (session != null) {
      try {
        await session.close();
      } catch (_) {}
    }
    _userLine = null;
    _modelLine = null;
  }

  void _fail(String message) {
    debugPrint('PMA live: $message');
    _generation++;
    error = message;
    unawaited(_teardown());
    _set(LiveState.error);
  }

  void _set(LiveState s) {
    if (_disposed) return;
    state = s;
    notifyListeners();
  }

  Future<void> _onMessage(LiveServerResponse response) async {
    final m = response.message;
    if (m is LiveServerContent) {
      if (m.interrupted == true) {
        // The operator spoke over the model: drop the rest of its sentence.
        await _audio.stopPlayback();
        _modelLine?.finished = true;
        _modelLine = null;
        _set(LiveState.listening);
      }
      for (final part in m.modelTurn?.parts ?? const <Part>[]) {
        if (part is InlineDataPart && part.mimeType.startsWith('audio')) {
          if (state != LiveState.speaking) _set(LiveState.speaking);
          await _audio.play(part.bytes);
        }
      }
      if ((m.inputTranscription?.text ?? '').trim().isNotEmpty && _userLine == null) {
        _operatorTurns++;
      }
      _userLine = _append(_userLine, m.inputTranscription, fromUser: true);
      _modelLine = _append(_modelLine, m.outputTranscription, fromUser: false);
      if (m.turnComplete == true) {
        _userLine?.finished = true;
        _modelLine?.finished = true;
        _userLine = null;
        _modelLine = null;
        _set(LiveState.listening);
      }
    } else if (m is LiveServerToolCall) {
      await _onToolCall(m);
    } else if (m is GoingAwayNotice) {
      // Sessions are time-limited; the operator can tap to start again.
      _fail('The live session timed out. Tap to talk again.');
    }
  }

  LiveLine? _append(LiveLine? line, Transcription? t, {required bool fromUser}) {
    final text = t?.text;
    if (text == null || text.isEmpty) return line;
    var l = line;
    if (l == null) {
      l = LiveLine(text, fromUser: fromUser);
      lines.add(l);
    } else {
      l.text += text;
    }
    if (t?.finished == true) {
      l.finished = true;
      l = null;
    }
    if (!_disposed) notifyListeners();
    return l;
  }

  Future<void> _onToolCall(LiveServerToolCall call) async {
    final responses = <FunctionResponse>[];
    NavTarget? navigate;
    for (final fc in call.functionCalls ?? const <FunctionCall>[]) {
      if (fc.name != 'pma') {
        responses.add(FunctionResponse(fc.name, {'error': 'unknown tool'}, id: fc.id));
        continue;
      }
      final command = '${fc.args['command'] ?? ''}'.trim();
      if (service.pending != null && _pendingAtTurn == _operatorTurns) {
        // The app's question has not been answered by the operator yet.
        responses.add(FunctionResponse(
          fc.name,
          {
            'error': 'The app asked the operator a question. Ask it, then wait '
                'for the operator to answer out loud before calling pma again.',
          },
          id: fc.id,
        ));
        continue;
      }
      final reply = await service.handle(command);
      _pendingAtTurn = reply.pending != null ? _operatorTurns : null;
      onReply?.call(reply);
      navigate ??= reply.navigate;
      responses.add(FunctionResponse(
        fc.name,
        {
          'reply_english': reply.en,
          'reply_urdu': reply.ur,
          'saved': reply.saved,
          'pending': reply.pending != null,
          if (reply.statuses.isNotEmpty) 'statuses': reply.statuses,
        },
        id: fc.id,
      ));
    }
    await _session?.sendToolResponse(responses);
    if (navigate != null) {
      // Let the model say where it is going, then leave this screen.
      final target = navigate;
      final gen = _generation;
      _navTimer?.cancel();
      _navTimer = Timer(const Duration(seconds: 3), () async {
        if (gen != _generation || _disposed) return;
        await stop();
        onNavigate?.call(target);
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_teardown());
    super.dispose();
  }
}
