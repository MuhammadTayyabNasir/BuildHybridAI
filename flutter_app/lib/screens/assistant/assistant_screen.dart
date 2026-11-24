import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../assistant/app_assistant_store.dart';
import '../../assistant/assistant_intent.dart';
import '../../assistant/assistant_service.dart';
import '../../assistant/hybrid_ai.dart';
import '../../assistant/voice_io.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/sections.dart';
import '../../assistant/live/live_assistant.dart';
import '../../ui/dabba_mascot.dart';
import '../../providers/auth_provider.dart';
import '../../providers/entries_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/local_storage_service.dart';
import '../../services/th_threshold_service.dart';
import '../../ui/pma_ui.dart';
import '../analytics/advanced_analytics_screen.dart';
import '../sections/section_home_screen.dart';
import '../sections/temp_humidity/temp_humidity_screen.dart';
import '../automations/automations_screen.dart';
import '../extraction/extraction_screen.dart';
import '../settings/settings_screen.dart';
import '../../assistant/hybrid_ai_factory.dart';

class _Turn {
  _Turn.user(this.text) : fromUser = true, reply = null;
  _Turn.bot(AssistantReply this.reply) : fromUser = false, text = '';
  final bool fromUser;
  final String text;
  final AssistantReply? reply;
}

/// Voice + text assistant for floor operators.
///
/// Speak or type in Urdu, Roman Urdu or English. Gemini (on-device Nano when
/// available, cloud otherwise, rules when offline without Nano) turns the
/// words into a structured intent; the app validates and executes it. Readings
/// are read back and saved only after "haan / okay / theek hai".
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, this.ai, this.voice});

  final HybridAi? ai;
  final VoiceIo? voice;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  late final AssistantService _service;
  late final HybridAi _ai;
  late final VoiceIo _voice;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _turns = <_Turn>[];
  bool _urdu = true;
  bool _listening = false;

  /// Live conversation: after each spoken reply the microphone opens again,
  /// like a phone call, until the operator goes quiet or taps stop.
  bool _live = false;
  int _silentTurns = 0;

  /// Gemini Live voice session (online only).
  late final LiveAssistant _gemini;
  bool _busy = false;
  String _heard = '';
  String _modelStatus = '…';

  @override
  void initState() {
    super.initState();
    _ai = widget.ai ?? createHybridAi();
    _voice = widget.voice ?? VoiceIo();
    final user = context.read<AuthProvider>().user;
    final conn = context.read<ConnectivityProvider>();
    _service = AssistantService(
      ai: _ai,
      isOnline: () async => conn.isOnline,
      store: AppAssistantStore(
        local: context.read<LocalStorageService>(),
        firestore: context.read<FirestoreService>(),
        thresholds: context.read<ThThresholdService>(),
        isOnline: () => conn.isOnline,
        userId: user?.id ?? '',
        userName: user?.username ?? '',
        entries: context.read<EntriesProvider>(),
      ),
    );
    _turns.add(
      _Turn.bot(
        const AssistantReply(
          en: 'Assalam o alaikum! Say a reading like "Peri Peri humidity 45", or ask "aaj meri koi entry miss to nahi hui?"',
          ur: 'السلام علیکم! ریڈنگ بولیں جیسے "پیری پیری ہیومیڈیٹی 45"، یا پوچھیں "آج میری کوئی انٹری مس تو نہیں ہوئی؟"',
          source: AnswerSource.rules,
        ),
      ),
    );
    _gemini = LiveAssistant(
      service: _service,
      onNavigate: (t) {
        if (mounted) _navigate(t);
      },
      onReply: (r) {
        if (!mounted) return;
        setState(() => _turns.add(_Turn.bot(r)));
        _scrollDown();
      },
    )..addListener(_onLiveChanged);
    _voice.warmUp().then((_) {
      if (!mounted || _voice.urduVoice || kIsWeb) return;
      final local = context.read<LocalStorageService>();
      if (local.getMeta('pma_urdu_voice_tip') == '1') return;
      local.setMeta('pma_urdu_voice_tip', '1');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 8),
          content: Text(
            'This phone has no Urdu voice, so replies are spoken in English. '
            'To hear Urdu: Settings › Text-to-speech › Google › Install voice data › Urdu.',
          ),
        ),
      );
    });
    _ai.status().then((s) {
      if (mounted) setState(() => _modelStatus = s);
    });
  }

  void _onLiveChanged() {
    if (!mounted) return;
    setState(() {});
    final err = _gemini.state == LiveState.error ? _gemini.error : null;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      _gemini.error = null;
    }
  }

  Future<void> _toggleGemini() async {
    if (_gemini.active) {
      await _gemini.stop();
      return;
    }
    if (_busy) return;
    _live = false;
    await _voice.stopListening();
    await _voice.stopSpeaking();
    if (mounted) setState(() => _listening = false);
    await _gemini.start();
  }

  @override
  void dispose() {
    _gemini.removeListener(_onLiveChanged);
    _gemini.dispose();
    _voice.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty || _busy) return;
    _input.clear();
    setState(() {
      _turns.add(_Turn.user(t));
      _busy = true;
      _heard = '';
    });
    _scrollDown();
    final reply = await _service.handle(t);
    await _show(reply);
  }

  Future<void> _show(AssistantReply reply) async {
    if (!mounted) return;
    setState(() {
      _turns.add(_Turn.bot(reply));
      _busy = false;
    });
    _scrollDown();
    final nav = reply.navigate;
    if (nav != null && mounted) {
      // Leaving the screen ends the conversation; say the reply briefly.
      _live = false;
      _voice.say(_spoken(reply), urdu: _speakUrdu);
      _navigate(nav);
      return;
    }
    await _voice.say(_spoken(reply), urdu: _speakUrdu);
    if (_live && mounted) _listenOnce();
  }

  /// Urdu is spoken only when the phone has an Urdu voice; otherwise the
  /// English line is spoken and the Urdu one stays on screen.
  bool get _speakUrdu => _urdu && _voice.urduVoice;

  String _spoken(AssistantReply r) => r.text(_speakUrdu);

  void _navigate(NavTarget nav) {
    final section = nav.sectionId == null
        ? null
        : Sections.byId(nav.sectionId!);
    final Widget? page = switch (nav.screen) {
      'temp_humidity' when section != null => TempHumidityScreen(
        section: section,
      ),
      'entries' when section != null => SectionHomeScreen(section: section),
      'settings' => const SettingsScreen(),
      'extraction' => const ExtractionScreen(),
      'automations' => AutomationsScreen.withService(context),
      'analytics' => const AdvancedAnalyticsScreen(),
      _ => null,
    };
    if (nav.screen == 'dashboard') {
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    if (page != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    }
  }

  Future<void> _toggleMic() async {
    if (_live || _listening) {
      _live = false;
      await _voice.stopListening();
      await _voice.stopSpeaking();
      if (mounted) setState(() => _listening = false);
      return;
    }
    _live = true;
    _silentTurns = 0;
    await _listenOnce();
  }

  Future<void> _listenOnce() async {
    if (!mounted || _busy) return;
    setState(() {
      _listening = true;
      _heard = '';
    });
    var sent = false;
    final ok = await _voice.listen(
      urdu: _urdu,
      onWords: (words, done) {
        if (!mounted) return;
        setState(() => _heard = words);
        if (done && !sent) {
          sent = true;
          setState(() => _listening = false);
          if (words.trim().isEmpty) {
            _endIfSilent();
          } else {
            _silentTurns = 0;
            _send(words);
          }
        }
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _listening = false);
        // "no match" / timeout just means the operator said nothing.
        if (!sent) _endIfSilent();
      },
      onDone: () {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!ok && mounted) {
      _live = false;
      setState(() => _listening = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Speech recognition is not available. Type instead.'),
        ),
      );
    }
  }

  /// One quiet turn re-opens the mic; two in a row end the conversation.
  void _endIfSilent() {
    _silentTurns++;
    if (_live && _silentTurns < 2) {
      _listenOnce();
    } else {
      _live = false;
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Dabba mirrors what the assistant is doing.
  DabbaMood _mood(bool online) {
    if (_gemini.active) {
      return switch (_gemini.state) {
        LiveState.connecting => DabbaMood.thinking,
        LiveState.speaking => DabbaMood.speaking,
        _ => DabbaMood.listening,
      };
    }
    if (_busy) return DabbaMood.thinking;
    if (_listening) return DabbaMood.listening;
    final last = _turns.isEmpty ? null : _turns.last.reply;
    if (last != null && last.statuses.values.contains('red')) {
      return DabbaMood.worried;
    }
    if (last != null && last.saved) return DabbaMood.happy;
    return DabbaMood.idle;
  }

  String _moodLine(bool online) {
    final u = _urdu;
    return switch (_mood(online)) {
      DabbaMood.thinking => u ? 'سوچ رہا ہوں…' : 'Thinking…',
      DabbaMood.listening => u ? 'میں سن رہا ہوں' : "I'm listening",
      DabbaMood.speaking =>
        u ? 'بول رہا ہوں — بیچ میں بول سکتے ہیں' : 'Talking — interrupt me anytime',
      DabbaMood.worried =>
        u ? 'یہ ویلیو سرخ حد سے اوپر ہے' : 'That value is over the red limit',
      DabbaMood.happy => u ? 'محفوظ ہو گیا!' : 'Saved!',
      _ => online
          ? (u ? 'میں ڈبہ ہوں۔ Live دبائیں اور بات کریں' : "I'm Dabba. Tap Live and just talk")
          : (u ? 'آف لائن بھی کام کرتا ہوں' : 'I work offline too'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final online = context.watch<ConnectivityProvider>().isOnline;
    final pending = _service.pending;
    return Scaffold(
      backgroundColor: Pma.canvas,
      appBar: AppBar(
        title: const Text('PMA Assistant'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: Pma.heroGradient),
        ),
        actions: [
          _LiveButton(
            active: _gemini.active,
            // Not while a typed/spoken request is still being handled: both
            // paths share one assistant and its pending question.
            enabled: online && !_busy,
            onTap: _toggleGemini,
          ),
          _LangSwitch(urdu: _urdu, onChanged: (v) => setState(() => _urdu = v)),
        ],
      ),
      body: Column(
        children: [
          _DabbaHeader(mood: _mood(online), line: _moodLine(online)),
          _StatusStrip(
            online: online,
            modelStatus: _modelStatus,
            fastMode: _service.fastMode,
            batchCount: _service.batch?.length,
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              itemCount: _turns.length,
              itemBuilder: (_, i) {
                final turn = _turns[i];
                if (turn.fromUser) return _UserBubble(turn.text);
                return _BotBubble(reply: turn.reply!, urdu: _urdu);
              },
            ),
          ),
          if (pending != null && pending.kind != PendingKind.needSection)
            _ConfirmBar(
              urdu: _urdu,
              busy: _busy,
              onYes: () async {
                setState(() => _busy = true);
                await _show(await _service.confirmPending());
              },
              onNo: () => _show(_service.cancelPending()),
            ),
          if (_listening || _heard.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _heard.isEmpty
                    ? (_urdu ? 'سن رہا ہوں…' : 'Listening…')
                    : _heard,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          if (_gemini.active)
            _LivePanel(live: _gemini, urdu: _urdu, onStop: _gemini.stop)
          else
            _InputBar(
              controller: _input,
              listening: _listening,
              busy: _busy,
              urdu: _urdu,
              onMic: _toggleMic,
              onSend: () => _send(_input.text),
            ),
        ],
      ),
    );
  }
}

class _LangSwitch extends StatelessWidget {
  const _LangSwitch({required this.urdu, required this.onChanged});
  final bool urdu;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SegmentedButton<bool>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: const [
          ButtonSegment(value: true, label: Text('اردو')),
          ButtonSegment(value: false, label: Text('EN')),
        ],
        selected: {urdu},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    required this.online,
    required this.modelStatus,
    required this.fastMode,
    this.batchCount,
  });
  final bool online;
  final String modelStatus;
  final bool fastMode;
  final int? batchCount;

  @override
  Widget build(BuildContext context) {
    final nano = switch (modelStatus) {
      'available' => 'Gemini Nano ready',
      'downloading' || 'downloadable' => 'Gemini Nano downloading',
      'unsupported' => 'On-device AI: Android only',
      '…' => 'Checking on-device AI…',
      _ => 'No on-device model',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.primary.withValues(alpha: 0.08),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          _Chip(
            icon: online ? Icons.cloud_done : Icons.cloud_off,
            label: online ? 'Online' : 'Offline',
          ),
          _Chip(icon: Icons.memory, label: nano),
          _Chip(
            icon: fastMode ? Icons.bolt : Icons.verified_user,
            label: fastMode ? 'Fast mode' : 'Confirm mode',
          ),
          if (batchCount != null)
            _Chip(
              icon: Icons.playlist_add,
              label: 'Batch: $batchCount/${AssistantService.maxBatch}',
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: AppColors.primaryDark),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
}

class SourceBadge extends StatelessWidget {
  const SourceBadge(this.source, {super.key});
  final AnswerSource source;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (source) {
      AnswerSource.onDevice => (AppColors.green, Icons.phone_android),
      AnswerSource.cloud => (AppColors.wafer, Icons.cloud),
      AnswerSource.rules => (AppColors.textSecondary, Icons.rule),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            source.label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: Container(
      margin: const EdgeInsets.only(bottom: 10, left: 48),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: Pma.heroGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white)),
    ),
  );
}

class _BotBubble extends StatelessWidget {
  const _BotBubble({required this.reply, required this.urdu});
  final AssistantReply reply;
  final bool urdu;

  Color _statusColor(String s) => switch (s) {
    'green' => AppColors.green,
    'yellow' => AppColors.yellow,
    _ => AppColors.red,
  };

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, right: 32),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: dark ? AppColors.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(Pma.radius),
          border: reply.pending != null
              ? Border.all(color: AppColors.primary, width: 1.5)
              : null,
          boxShadow: const [BoxShadow(color: AppColors.shadow, blurRadius: 8)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SourceBadge(reply.source),
                if (reply.saved) ...[
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.check_circle,
                    size: 16,
                    color: AppColors.green,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Directionality(
              textDirection: urdu ? TextDirection.rtl : TextDirection.ltr,
              child: Text(
                reply.text(urdu),
                style: const TextStyle(fontSize: 15, height: 1.4),
              ),
            ),
            if (reply.statuses.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: reply.statuses.entries
                    .map(
                      (e) => Chip(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: _statusColor(
                          e.value,
                        ).withValues(alpha: 0.15),
                        side: BorderSide(color: _statusColor(e.value)),
                        label: Text(
                          '${e.key}: ${e.value}',
                          style: TextStyle(
                            fontSize: 12,
                            color: _statusColor(e.value),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConfirmBar extends StatelessWidget {
  const _ConfirmBar({
    required this.urdu,
    required this.busy,
    required this.onYes,
    required this.onNo,
  });
  final bool urdu;
  final bool busy;
  final VoidCallback onYes;
  final VoidCallback onNo;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: busy ? null : onNo,
            icon: const Icon(Icons.close),
            label: Text(urdu ? 'نہیں' : 'No'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: busy ? null : onYes,
            icon: const Icon(Icons.check),
            label: Text(urdu ? 'ہاں، محفوظ کریں' : 'Yes, save'),
          ),
        ),
      ],
    ),
  );
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.listening,
    required this.busy,
    required this.urdu,
    required this.onMic,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool listening;
  final bool busy;
  final bool urdu;
  final VoidCallback onMic;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: urdu ? 'لکھیں یا بولیں…' : 'Type or speak…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: busy ? null : onSend,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FloatingActionButton(
            heroTag: 'pma-mic',
            onPressed: busy ? null : onMic,
            backgroundColor: listening ? AppColors.red : Pma.ink,
            shape: const CircleBorder(),
            child: Icon(
              listening ? Icons.stop : Icons.mic,
              color: Colors.white,
            ),
          ),
        ],
      ),
    ),
  );
}

/// App-bar switch for Gemini Live. Needs internet; offline the regular
/// on-device / rules assistant keeps working.
class _LiveButton extends StatelessWidget {
  const _LiveButton({
    required this.active,
    required this.enabled,
    required this.onTap,
  });
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Tooltip(
      message: enabled
          ? 'Gemini Live: talk freely in Urdu or English'
          : 'Gemini Live needs internet. The offline assistant still works.',
      child: Material(
        color: active ? Colors.white : Colors.white.withValues(alpha: 0.18),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: enabled || active ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.graphic_eq,
                  size: 18,
                  color: active
                      ? Pma.ink
                      : (enabled ? Colors.white : Colors.white54),
                ),
                const SizedBox(width: 6),
                Text(
                  'Live',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: active
                        ? Pma.ink
                        : (enabled ? Colors.white : Colors.white54),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Shown instead of the input bar while Gemini Live runs: what the phone is
/// doing, the running transcript, and a stop button.
class _LivePanel extends StatelessWidget {
  const _LivePanel({
    required this.live,
    required this.urdu,
    required this.onStop,
  });
  final LiveAssistant live;
  final bool urdu;
  final VoidCallback onStop;

  String get _label => switch (live.state) {
    LiveState.connecting => urdu ? 'جڑ رہا ہے…' : 'Connecting…',
    LiveState.speaking =>
      urdu
          ? 'بول رہا ہے… (بیچ میں بول سکتے ہیں)'
          : 'Speaking… (you can interrupt)',
    _ => urdu ? 'سن رہا ہوں… بولیں' : 'Listening… just talk',
  };

  @override
  Widget build(BuildContext context) {
    final recent = live.lines.length > 4
        ? live.lines.sublist(live.lines.length - 4)
        : live.lines;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(
          gradient: Pma.heroGradient,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final l in recent)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${l.fromUser ? '🗣 ' : '✦ '}${l.text}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: l.fromUser ? Colors.white70 : Colors.white,
                    fontWeight: l.fromUser ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
              ),
            Row(
              children: [
                Dabba(
                  size: 44,
                  mood: switch (live.state) {
                    LiveState.speaking => DabbaMood.speaking,
                    LiveState.connecting => DabbaMood.thinking,
                    _ => DabbaMood.listening,
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Text(
                  'Gemini Live',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(width: 8),
                FloatingActionButton.small(
                  heroTag: 'pma-live-stop',
                  onPressed: onStop,
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.stop, color: AppColors.red),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


/// Dabba and one line about what it is doing, above the conversation.
class _DabbaHeader extends StatelessWidget {
  const _DabbaHeader({required this.mood, required this.line});
  final DabbaMood mood;
  final String line;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 16, 2),
        child: Row(
          children: [
            Dabba(mood: mood, size: 64),
            const SizedBox(width: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  line,
                  key: ValueKey(line),
                  style: const TextStyle(
                    color: Pma.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}
