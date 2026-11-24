import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../analytics/pma_metrics.dart';
import '../../assistant/app_assistant_store.dart';
import '../../assistant/assistant_service.dart';
import '../../core/constants/sections.dart';
import '../../providers/auth_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/entries_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/local_storage_service.dart';
import '../../services/th_threshold_service.dart';
import '../../automations/automation_service.dart';
import '../extraction/extraction_screen.dart';
import '../automations/automations_screen.dart';
import '../../ui/pma_ui.dart';
import '../sections/section_home_screen.dart';
import '../sections/temp_humidity/temp_humidity_screen.dart';
import '../../assistant/hybrid_ai_factory.dart';

/// Operator home: today's numbers in a warm gradient hero, what is still
/// missing this shift, each section's latest reading, and 7-day trends.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, required this.onAsk});

  /// Opens the assistant tab.
  final VoidCallback onAsk;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  int _tick = 0;

  Future<void> _refresh() async => setState(() => _tick++);

  @override
  Widget build(BuildContext context) {
    context.watch<EntriesProvider>(); // rebuild when entries change
    final local = context.read<LocalStorageService>();
    final thresholds = context.read<ThThresholdService>();
    final user = context.watch<AuthProvider>().user;
    final online = context.watch<ConnectivityProvider>().isOnline;

    final metrics = PmaMetrics(
      entries: local.getEntries(),
      reports: local.getTempHumidityReports(),
      threshold: thresholds.forSection,
    );
    final missing = AssistantService(
      ai: createHybridAi(),
      isOnline: () async => online,
      store: AppAssistantStore(
        local: local,
        firestore: context.read<FirestoreService>(),
        thresholds: thresholds,
        isOnline: () => online,
        userId: user?.id ?? '',
        userName: user?.username ?? '',
      ),
    ).missingReadings(DateTime.now());

    final readings7 = metrics.readingsPerDay(7);
    final entries7 = metrics.entriesPerDay(7);
    final labels7 = [
      for (final d in metrics.lastDays(7)) const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][d.weekday - 1],
    ];
    final readingTrend = PmaMetrics.trend(readings7);
    final entryTrend = PmaMetrics.trend(entries7);
    final hour = DateTime.now().hour;
    final greet = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';

    return Scaffold(
      key: ValueKey(_tick),
      backgroundColor: Pma.canvas,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            GradientHero(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.white.withValues(alpha: 0.25),
                          child: Text(
                            (user?.username.isNotEmpty ?? false)
                                ? user!.username[0].toUpperCase()
                                : 'P',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('$greet,',
                                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
                              Text(user?.username ?? 'Operator',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                        TrendPill(
                          label: online ? 'Online' : 'Offline',
                          onDark: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: KpiTile(
                            onDark: true,
                            caption: 'Readings today',
                            value: '${readings7.last.toInt()}',
                            pill: readingTrend == null
                                ? null
                                : TrendPill(
                                    label: '${readingTrend.abs().toStringAsFixed(0)}%',
                                    up: readingTrend >= 0,
                                    onDark: true,
                                  ),
                          ),
                        ),
                        Expanded(
                          child: KpiTile(
                            onDark: true,
                            caption: 'Packing checks',
                            value: '${entries7.last.toInt()}',
                            pill: entryTrend == null
                                ? null
                                : TrendPill(
                                    label: '${entryTrend.abs().toStringAsFixed(0)}%',
                                    up: entryTrend >= 0,
                                    onDark: true,
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    GlassCard(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                      child: Row(
                        children: [
                          Icon(
                            missing.isEmpty ? Icons.verified : Icons.pending_actions,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              missing.isEmpty
                                  ? 'All scheduled readings are in for this shift.'
                                  : '${missing.length} scheduled ${missing.length == 1 ? 'reading is' : 'readings are'} still missing',
                              style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                          ),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Pma.ink,
                              foregroundColor: Colors.white,
                              shape: const StadiumBorder(),
                            ),
                            onPressed: widget.onAsk,
                            icon: const Icon(Icons.mic, size: 18),
                            label: const Text('Ask'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (missing.isNotEmpty)
              _SectionTitle('Still to record',
                  trailing: TrendPill(label: '${missing.length} open', color: Pma.bad)),
            if (missing.isNotEmpty)
              SizedBox(
                height: 74,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal,
                  itemCount: missing.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final m = missing[i];
                    final s = Sections.byId(m.sectionId);
                    return PmaCard(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      onTap: () => _open(context, TempHumidityScreen(section: s)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                            '${m.shift == 'morning' ? 'Morning' : 'Night'} · ${m.missing == 'both' ? 'temp + humidity' : m.missing}',
                            style: const TextStyle(fontSize: 12, color: Pma.inkSoft),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const _SectionTitle('Automations'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Builder(builder: (context) {
                final auto = context.watch<AutomationService>();
                final last = auto.inbox.isEmpty ? null : auto.inbox.first;
                final active = auto.rules.where((r) => r.enabled).length;
                return PmaCard(
                  onTap: () => AutomationsScreen.open(context),
                  child: Row(children: [
                    CircleAvatar(
                      backgroundColor: Pma.flame.withValues(alpha: 0.12),
                      child: const Icon(Icons.bolt_rounded, color: Pma.ember),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('$active active rules'
                            '${auto.suggestions.isEmpty ? '' : ' · ${auto.suggestions.length} AI suggestions'}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(last?.en ?? 'Shift-end checks and red alerts run automatically.',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: Pma.inkSoft)),
                      ]),
                    ),
                    const Icon(Icons.chevron_right),
                  ]),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: PmaCard(
                onTap: () => _open(context, const ExtractionScreen()),
                child: const Row(children: [
                  CircleAvatar(
                    backgroundColor: Color(0x1FFF6A3D),
                    child: Icon(Icons.document_scanner_outlined, color: Pma.ember),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Scan paper forms', style: TextStyle(fontWeight: FontWeight.w700)),
                      Text('Photo or bulk PDF → reviewed packing entries',
                          style: TextStyle(fontSize: 12, color: Pma.inkSoft)),
                    ]),
                  ),
                  Icon(Icons.chevron_right),
                ]),
              ),
            ),
            const _SectionTitle('Sections'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth > 700 ? 3 : 2;
                  final w = (c.maxWidth - (cols - 1) * 12) / cols;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final s in Sections.all)
                        SizedBox(
                          width: w,
                          child: _SectionTile(
                            section: s,
                            reading: metrics.latest(s.id),
                            onTap: () => _open(context, SectionHomeScreen(section: s)),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const _SectionTitle('Readings this week'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: PmaCard(
                child: AreaTrendChart(values: readings7, labels: labels7, unit: ' readings'),
              ),
            ),
            const _SectionTitle('Packing checks this week'),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: PmaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KpiTile(
                      caption: 'Passed all checks (7 days)',
                      value: '${metrics.passRate().toStringAsFixed(0)}%',
                      icon: Icons.verified_outlined,
                    ),
                    const SizedBox(height: 12),
                    RoundedBarChart(values: entries7, labels: labels7, unit: ' checks'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700, color: Pma.ink)),
            ),
            ?trailing,
          ],
        ),
      );
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({required this.section, required this.reading, required this.onTap});
  final SectionInfo section;
  final SectionReading reading;
  final VoidCallback onTap;

  String _v(double? v, String unit) =>
      v == null ? '—' : '${v.toStringAsFixed(v % 1 == 0 ? 0 : 1)}$unit';

  @override
  Widget build(BuildContext context) {
    return PmaCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(section.imagePath, width: 36, height: 36, fit: BoxFit.cover),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(section.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: reading.status == 'none' ? Pma.inkSoft.withValues(alpha: 0.3) : Pma.status(reading.status),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  icon: Icons.thermostat,
                  value: _v(reading.temperature, '°'),
                  color: Pma.status(reading.tempStatus ?? ''),
                ),
              ),
              Expanded(
                child: _Metric(
                  icon: Icons.water_drop_outlined,
                  value: _v(reading.humidity, '%'),
                  color: Pma.status(reading.humStatus ?? ''),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.value, required this.color});
  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          // Narrow phones (360 dp) give each metric ~58 dp; shrink instead
          // of overflowing.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      );
}
