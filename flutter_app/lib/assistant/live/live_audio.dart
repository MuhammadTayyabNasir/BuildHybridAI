import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:record/record.dart';

/// Raw audio for Gemini Live: 16 kHz mono PCM from the microphone, 24 kHz
/// mono PCM played back as it streams in.
///
/// The microphone uses Android's voice-communication source, which applies
/// echo cancellation, so the phone's own speaker does not interrupt the model.
class LiveAudio {
  static const inputRate = 16000;
  static const outputRate = 24000;
  static const inputMime = 'audio/pcm;rate=$inputRate';

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _micSub;
  AudioSource? _stream;
  SoundHandle? _handle;

  Future<bool> hasMicPermission() async {
    final r = AudioRecorder();
    try {
      return await r.hasPermission();
    } finally {
      await r.dispose();
    }
  }

  Future<void> startMic(
    void Function(Uint8List chunk) onChunk, {
    void Function(Object error)? onError,
  }) async {
    await stopMic();
    final recorder = AudioRecorder();
    _recorder = recorder;
    final stream = await recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: inputRate,
      numChannels: 1,
      echoCancel: true,
      noiseSuppress: true,
      androidConfig: AndroidRecordConfig(
        audioSource: AndroidAudioSource.voiceCommunication,
      ),
    ));
    _micSub = stream.listen((d) {
      if (d.isNotEmpty) onChunk(d);
    }, onError: (Object e) {
      debugPrint('Live mic error: $e');
      onError?.call(e);
    });
  }

  Future<void> stopMic() async {
    await _micSub?.cancel();
    _micSub = null;
    final r = _recorder;
    _recorder = null;
    if (r != null) {
      try {
        await r.stop();
      } catch (_) {}
      await r.dispose();
    }
  }

  /// Bumped by [stopPlayback]; a chunk whose player set-up started before a
  /// stop is dropped instead of opening a new stream after it.
  int _playGen = 0;

  Future<bool> _ensurePlayer(int gen) async {
    if (!SoLoud.instance.isInitialized) {
      await SoLoud.instance.init(sampleRate: outputRate, channels: Channels.mono);
    }
    if (gen != _playGen) return false;
    if (_stream != null) return true;
    _stream = SoLoud.instance.setBufferStream(
      bufferingType: BufferingType.released,
      bufferingTimeNeeds: 0,
      sampleRate: outputRate,
      channels: Channels.mono,
      format: BufferType.s16le,
    );
    _handle = SoLoud.instance.play(_stream!);
    return true;
  }

  /// Queues one streamed chunk of the model's voice.
  Future<void> play(Uint8List pcm) async {
    if (!await _ensurePlayer(_playGen)) return;
    final s = _stream;
    if (s != null) SoLoud.instance.addAudioDataStream(s, pcm);
  }

  /// Drops whatever is still queued, e.g. when the operator talks over the
  /// model (barge-in) or the session ends.
  Future<void> stopPlayback() async {
    _playGen++;
    final s = _stream;
    final h = _handle;
    _stream = null;
    _handle = null;
    if (s == null) return;
    try {
      SoLoud.instance.setDataIsEnded(s);
      if (h != null && SoLoud.instance.getIsValidVoiceHandle(h)) {
        await SoLoud.instance.stop(h);
      }
      await SoLoud.instance.disposeSource(s);
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stopMic();
    await stopPlayback();
  }
}
