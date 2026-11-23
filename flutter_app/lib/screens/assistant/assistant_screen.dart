import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../assistant/app_assistant_store.dart';
import '../../assistant/assistant_intent.dart';
import '../../assistant/assistant_service.dart';
import '../../assistant/hybrid_ai.dart';
import '../../assistant/voice_io.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/sections.dart';
import '../../providers/auth_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/local_storage_service.dart';
import '../../services/th_threshold_service.dart';
import '../../ui/pma_ui.dart';
import '../analytics/advanced_analytics_screen.dart';
import '../sections/section_home_screen.dart';
import '../sections/temp_humidity/temp_humidity_screen.dart';
import '../settings/settings_screen.dart';

class _Turn {
  _Turn.user(this.text)
      : fromUser = true,
        reply = null;
  _Turn.bot(AssistantReply this.reply)
      : fromUser = false,
        text = '';
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
  bool _busy = false;
  String _heard = '';
  String _modelStatus = '…';

  @override
  void initState() {
    super.initState();
    _ai = widget.ai ?? ChannelHybridAi();
    _voice = widget.voice ?? VoiceIo();
    final user = context.read<AuthProvider>().user;
    final conn = context.read<ConnectivityProvider>();
    _service = AssistantService(
      ai: _ai,
      store: AppAssistantStore(
        local: context.read<LocalStorageService>(),
        firestore: context.read<FirestoreService>(),
        thresholds: context.read<ThThresholdService>(),
        isOnline: () => conn.isOnline,
        userId: user?.id ?? '',
        userName: user?.username ?? '',
      ),
    );
    _turns.add(_Turn.bot(const AssistantReply(
      en: 'Assalam o alaikum! Say a reading like "Peri Peri humidity 45", or ask "aaj meri koi entry miss to nahi hui?"',
      ur: 'السلام علیکم! ریڈنگ بولیں جیسے "پیری پیری ہیومیڈیٹی 45"، یا پوچھیں "آج میری کوئی انٹری مس تو نہیں ہوئی؟"',
      source: AnswerSource.rules,
    )));
    _ai.status().then((s) {
      if (mounted) setState(() => _modelStatus = s);
    });
  }

  @override
  void dispose() {
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
    await _voice.say(reply.text(_urdu), urdu: _urdu);
    final nav = reply.navigate;
    if (nav != null && mounted) _navigate(nav);
  }

  void _navigate(NavTarget nav) {
    final section = nav.sectionId == null ? null : Sections.byId(nav.sectionId!);
    final Widget? page = switch (nav.screen) {
      'temp_humidity' when section != null => TempHumidityScreen(section: section),
      'entries' when section != null => SectionHomeScreen(section: section),
      'settings' => const SettingsScreen(),
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
    if (_listening) {
      await _voice.stopListening();
      setState(() => _listening = false);
      return;
    }
    setState(() {
      _listening = true;
      _heard = '';
    });
    final ok = await _voice.listen(
      urdu: _urdu,
      onWords: (words, done) {
        if (!mounted) return;
        setState(() => _heard = words);
        if (done) {
          setState(() => _listening = false);
          _send(words);
        }
      },
      onError: (e) {
        if (mounted) setState(() => _listening = false);
      },
      onDone: () {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!ok && mounted) {
      setState(() => _listening = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Speech recognition is not available. Type instead.'),
      ));
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
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
          _LangSwitch(
            urdu: _urdu,
            onChanged: (v) => setState(() => _urdu = v),
          ),
        ],
      ),
      body: Column(
        children: [
          _StatusStrip(
            online: online,
            modelStatus: _modelStatus,
            fastMode: _service.fastMode,
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
                _heard.isEmpty ? (_urdu ? 'سن رہا ہوں…' : 'Listening…') : _heard,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
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
  });
  final bool online;
  final String modelStatus;
  final bool fastMode;

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
          _Chip(icon: online ? Icons.cloud_done : Icons.cloud_off, label: online ? 'Online' : 'Offline'),
          _Chip(icon: Icons.memory, label: nano),
          _Chip(
            icon: fastMode ? Icons.bolt : Icons.verified_user,
            label: fastMode ? 'Fast mode' : 'Confirm mode',
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
          Text(source.label,
              style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
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
                  const Icon(Icons.check_circle, size: 16, color: AppColors.green),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Directionality(
              textDirection: urdu ? TextDirection.rtl : TextDirection.ltr,
              child: Text(reply.text(urdu), style: const TextStyle(fontSize: 15, height: 1.4)),
            ),
            if (reply.statuses.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: reply.statuses.entries
                    .map((e) => Chip(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: _statusColor(e.value).withValues(alpha: 0.15),
                          side: BorderSide(color: _statusColor(e.value)),
                          label: Text('${e.key}: ${e.value}',
                              style: TextStyle(fontSize: 12, color: _statusColor(e.value))),
                        ))
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
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
                child: Icon(listening ? Icons.stop : Icons.mic, color: Colors.white),
              ),
            ],
          ),
        ),
      );
}
