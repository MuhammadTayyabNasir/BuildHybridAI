import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../analytics/pma_metrics.dart';
import '../../automations/automation_rule.dart';
import '../../automations/automation_service.dart';
import '../../automations/rule_suggester.dart';
import '../../core/constants/sections.dart';
import '../../providers/auth_provider.dart';
import '../../services/local_storage_service.dart';
import '../../services/th_threshold_service.dart';
import '../../ui/pma_ui.dart';
import '../../assistant/hybrid_ai_factory.dart';

/// List, edit, pause and approve automations; see recent alerts.
class AutomationsScreen extends StatefulWidget {
  const AutomationsScreen({super.key});

  /// Pushed routes sit above [AutomationHost], so carry its service along.
  static Widget withService(BuildContext context) => ChangeNotifierProvider.value(
        value: context.read<AutomationService>(),
        child: const AutomationsScreen(),
      );

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => withService(context)));

  @override
  State<AutomationsScreen> createState() => _AutomationsScreenState();
}

class _AutomationsScreenState extends State<AutomationsScreen> {
  bool _suggesting = false;

  Future<void> _suggest() async {
    final svc = context.read<AutomationService>();
    final local = context.read<LocalStorageService>();
    final metrics = PmaMetrics(
      entries: local.getEntries(),
      reports: local.getTempHumidityReports(),
      threshold: context.read<ThThresholdService>().forSection,
    );
    setState(() => _suggesting = true);
    final res = await svc.suggest(RuleSuggester(createHybridAi()), metrics);
    if (!mounted) return;
    setState(() => _suggesting = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res.added == 0
          ? 'No new suggestions (${res.source.label}).'
          : '${res.added} suggestion${res.added == 1 ? '' : 's'} from ${res.source.label} — review below.'),
    ));
  }

  Future<void> _edit([AutomationRule? rule]) async {
    final result = await showModalBottomSheet<AutomationRule>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Pma.radius))),
      builder: (_) => _RuleEditor(rule: rule),
    );
    if (result == null || !mounted) return;
    final err = await context.read<AutomationService>().upsert(result);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Not saved: $err')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<AutomationService>();
    final admin = context.watch<AuthProvider>().isAdmin;
    final rules = svc.rules;
    final active = rules.where((r) => r.enabled).length;

    return Scaffold(
      backgroundColor: Pma.canvas,
      floatingActionButton: admin
          ? FloatingActionButton.extended(
              backgroundColor: Pma.ink,
              foregroundColor: Colors.white,
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('New rule'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          GradientHero(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const BackButton(color: Colors.white),
                    const Expanded(
                      child: Text('Automations',
                          style: TextStyle(
                              color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                    ),
                    if (admin)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Pma.ink,
                          foregroundColor: Colors.white,
                          shape: const StadiumBorder(),
                        ),
                        onPressed: _suggesting ? null : _suggest,
                        icon: _suggesting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.auto_awesome, size: 18),
                        label: const Text('Suggest'),
                      ),
                  ]),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Row(children: [
                      Expanded(child: KpiTile(onDark: true, value: '$active', caption: 'Active rules')),
                      Expanded(
                          child: KpiTile(
                              onDark: true,
                              value: '${rules.length - active}',
                              caption: 'Paused')),
                      Expanded(
                          child: KpiTile(
                              onDark: true,
                              value: '${svc.pendingAlerts}',
                              caption: 'Alerts queued')),
                    ]),
                  ),
                ],
              ),
            ),
          ),
          if (svc.suggestions.isNotEmpty) ...[
            const _Title('Suggested by AI — needs approval'),
            for (final s in svc.suggestions)
              _SuggestionCard(
                rule: s,
                admin: admin,
                onApprove: () => svc.approve(s.id),
                onDismiss: () => svc.dismiss(s.id),
              ),
          ],
          const _Title('Rules'),
          if (rules.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text('No rules yet.'),
            ),
          for (final r in rules)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: PmaCard(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                onTap: admin ? () => _edit(r) : null,
                child: Row(children: [
                  _KindIcon(r.kind),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.describeEn(),
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: r.enabled ? Pma.ink : Pma.inkSoft)),
                        const SizedBox(height: 4),
                        Wrap(spacing: 6, children: [
                          if (r.notifyManager)
                            const TrendPill(label: 'Push to manager', color: Pma.ember),
                          if (r.origin == 'ai') const TrendPill(label: 'AI-suggested', color: Pma.inkSoft),
                          if (!r.enabled) const TrendPill(label: 'Paused', color: Pma.warn),
                        ]),
                      ],
                    ),
                  ),
                  Switch(
                    value: r.enabled,
                    onChanged: admin ? (v) => svc.setEnabled(r.id, v) : null,
                  ),
                  if (admin)
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Delete rule?'),
                            content: Text(r.describeEn()),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                            ],
                          ),
                        );
                        if (ok == true) await svc.remove(r.id);
                      },
                    ),
                ]),
              ),
            ),
          _Title('Recent alerts',
              trailing: svc.inbox.isEmpty
                  ? null
                  : TextButton(onPressed: svc.clearInbox, child: const Text('Clear'))),
          if (svc.inbox.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text('Nothing has fired yet.'),
            ),
          for (final e in svc.inbox)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: PmaCard(
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(
                    e.severity == 'critical'
                        ? Icons.error
                        : e.severity == 'warning'
                            ? Icons.warning_amber_rounded
                            : Icons.notifications_active,
                    color: e.severity == 'critical'
                        ? Pma.bad
                        : e.severity == 'warning'
                            ? Pma.warn
                            : Pma.flame,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.en, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(e.ur, textDirection: TextDirection.rtl),
                      const SizedBox(height: 4),
                      Text(DateFormat('d MMM, HH:mm').format(e.at),
                          style: const TextStyle(color: Pma.inkSoft, fontSize: 12)),
                    ]),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 12, 10),
        child: Row(children: [
          Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Pma.ink))),
          ?trailing,
        ]),
      );
}

class _KindIcon extends StatelessWidget {
  const _KindIcon(this.kind);
  final RuleKind kind;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: 20,
        backgroundColor: Pma.flame.withValues(alpha: 0.12),
        child: Icon(
          switch (kind) {
            RuleKind.reminder => Icons.alarm,
            RuleKind.shiftEndCheck => Icons.fact_check_outlined,
            RuleKind.conditionAlert => Icons.thermostat,
          },
          color: Pma.ember,
        ),
      );
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.rule,
    required this.admin,
    required this.onApprove,
    required this.onDismiss,
  });
  final AutomationRule rule;
  final bool admin;
  final VoidCallback onApprove;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: PmaCard(
          color: const Color(0xFFFFF4EC),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.auto_awesome, color: Pma.ember, size: 18),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(rule.describeEn(), style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
            if (rule.reason.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(rule.reason, style: const TextStyle(color: Pma.inkSoft)),
            ],
            const SizedBox(height: 8),
            if (admin)
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Pma.ink, shape: const StadiumBorder()),
                  onPressed: onApprove,
                  child: const Text('Approve'),
                ),
              ])
            else
              const Text('Waiting for an admin to approve.', style: TextStyle(color: Pma.inkSoft)),
          ]),
        ),
      );
}

class _RuleEditor extends StatefulWidget {
  const _RuleEditor({this.rule});
  final AutomationRule? rule;

  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  late RuleKind _kind = widget.rule?.kind ?? RuleKind.conditionAlert;
  late String? _section = widget.rule?.sectionId;
  late String _metric = widget.rule?.metric ?? 'humidity';
  late String _op = widget.rule?.op ?? 'gt';
  late String _shift = widget.rule?.shift ?? 'morning';
  late bool _notify = widget.rule?.notifyManager ?? true;
  late final _value = TextEditingController(
      text: widget.rule?.value == null ? '' : widget.rule!.value!.toString());
  late final _time = TextEditingController(text: widget.rule?.time ?? '09:00');
  late final _msgEn = TextEditingController(text: widget.rule?.messageEn ?? '');
  late final _msgUr = TextEditingController(text: widget.rule?.messageUr ?? '');
  String? _error;

  @override
  void dispose() {
    for (final c in [_value, _time, _msgEn, _msgUr]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final rule = AutomationRule(
      id: widget.rule?.id ?? const Uuid().v4(),
      kind: _kind,
      enabled: widget.rule?.enabled ?? true,
      origin: widget.rule?.origin ?? 'admin',
      approved: true,
      sectionId: _section,
      metric: _kind == RuleKind.conditionAlert ? _metric : null,
      op: _kind == RuleKind.conditionAlert ? _op : null,
      value: _kind == RuleKind.conditionAlert && _op != 'red' ? double.tryParse(_value.text.trim()) : null,
      time: _kind == RuleKind.conditionAlert ? null : _time.text.trim(),
      shift: _kind == RuleKind.shiftEndCheck ? _shift : null,
      messageEn: _kind == RuleKind.reminder ? _msgEn.text.trim() : '',
      messageUr: _kind == RuleKind.reminder ? _msgUr.text.trim() : '',
      notifyManager: _notify,
      reason: widget.rule?.reason ?? '',
    );
    final err = rule.validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.pop(context, rule);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.rule == null ? 'New automation' : 'Edit automation',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            SegmentedButton<RuleKind>(
              segments: const [
                ButtonSegment(value: RuleKind.conditionAlert, label: Text('Alert'), icon: Icon(Icons.thermostat)),
                ButtonSegment(value: RuleKind.shiftEndCheck, label: Text('Shift end'), icon: Icon(Icons.fact_check_outlined)),
                ButtonSegment(value: RuleKind.reminder, label: Text('Reminder'), icon: Icon(Icons.alarm)),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _section,
              decoration: const InputDecoration(labelText: 'Section'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All sections')),
                for (final s in Sections.all) DropdownMenuItem(value: s.id, child: Text(s.name)),
              ],
              onChanged: (v) => setState(() => _section = v),
            ),
            if (_kind == RuleKind.conditionAlert) ...[
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _metric,
                    decoration: const InputDecoration(labelText: 'Reading'),
                    items: const [
                      DropdownMenuItem(value: 'humidity', child: Text('Humidity')),
                      DropdownMenuItem(value: 'temperature', child: Text('Temperature')),
                    ],
                    onChanged: (v) => setState(() => _metric = v ?? 'humidity'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _op,
                    decoration: const InputDecoration(labelText: 'When'),
                    items: const [
                      DropdownMenuItem(value: 'gt', child: Text('Above')),
                      DropdownMenuItem(value: 'lt', child: Text('Below')),
                      DropdownMenuItem(value: 'red', child: Text('Red limit')),
                    ],
                    onChanged: (v) => setState(() => _op = v ?? 'gt'),
                  ),
                ),
              ]),
              if (_op != 'red')
                TextField(
                  controller: _value,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Limit (${_metric == 'humidity' ? '%' : '°C'})'),
                ),
            ] else ...[
              TextField(
                controller: _time,
                decoration: const InputDecoration(labelText: 'Time (HH:mm, 24h)'),
              ),
              if (_kind == RuleKind.shiftEndCheck)
                DropdownButtonFormField<String>(
                  initialValue: _shift,
                  decoration: const InputDecoration(labelText: 'Shift to check'),
                  items: const [
                    DropdownMenuItem(value: 'morning', child: Text('Morning shift')),
                    DropdownMenuItem(value: 'night', child: Text('Night shift')),
                  ],
                  onChanged: (v) => setState(() => _shift = v ?? 'morning'),
                ),
              if (_kind == RuleKind.reminder) ...[
                TextField(controller: _msgEn, decoration: const InputDecoration(labelText: 'Message (English)')),
                TextField(
                  controller: _msgUr,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(labelText: 'Message (Urdu)'),
                ),
              ],
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Push to manager phone'),
              value: _notify,
              onChanged: (v) => setState(() => _notify = v),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: const TextStyle(color: Pma.bad)),
              ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Pma.ink,
                minimumSize: const Size.fromHeight(48),
                shape: const StadiumBorder(),
              ),
              onPressed: _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
