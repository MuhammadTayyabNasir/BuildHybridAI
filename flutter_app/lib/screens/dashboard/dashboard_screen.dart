import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/sections.dart';
import '../../core/utils/platform_info.dart';
import '../../core/utils/responsive.dart';
import '../../providers/auth_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/machines_provider.dart';
import '../../providers/products_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/offline_banner.dart';
import '../analytics/advanced_analytics_screen.dart';
import '../sections/section_home_screen.dart';
import '../admin/user_management_screen.dart';
import '../admin/product_management_screen.dart';
import '../admin/machine_management_screen.dart';
import '../admin/bulk_import_screen.dart';
import '../../services/report_service.dart';
import '../settings/settings_screen.dart';
import '../../widgets/sync_status_badge.dart';
import '../../widgets/download_report_dialog.dart';
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkSeed();
      if (!mounted) return;
      final outcome = await context
          .read<ReportService>()
          .checkAndAutoDownload();
      if (!mounted) return;
      if (outcome.saved.isNotEmpty) _showBackupNotification(outcome.saved);
      if (outcome.pendingEntries != null) {
        await _promptPendingBackup(outcome.pendingEntries!);
      }
    });
  }

  /// Shown when the app is opened after a long absence: ask before generating
  /// a big consolidated backup, then download it for the user if they confirm.
  Future<void> _promptPendingBackup(PendingBackup p) async {
    final df = DateFormat('dd MMM yyyy');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.history, color: AppColors.primary),
            SizedBox(width: 10),
            Text('Backup pending'),
          ],
        ),
        content: Text(
          'Welcome back! Entries from ${df.format(p.from)} to ${df.format(p.to)} '
          '(${p.days} days) haven\'t been saved to an Excel backup yet.\n\n'
          'Your data is safe — it\'s all stored and synced. Download the backup file now?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Download'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final result = await context.read<ReportService>().downloadPendingEntries(
        p,
      );
      if (mounted) _showBackupNotification([result]);
    }
  }

  void _showBackupNotification(List<AutoBackupResult> backups) {
    final names = backups.map((b) => '${b.type} — ${b.fileName}').join('\n');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.green,
        duration: const Duration(seconds: 7),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.cloud_done_outlined,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    backups.length == 1
                        ? 'Auto-backup saved'
                        : '${backups.length} auto-backups saved',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(names, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  Future<void> _checkSeed() async {
    if (!context.mounted) return;
    final products = context.read<ProductsProvider>();
    // Load machines + products at startup so the section cards show their
    // counts immediately (local-first). Both loadAll()s read SQLite first,
    // then refresh from Firestore in the background.
    context.read<MachinesProvider>().loadAll();
    await products.loadAll();
    if (!mounted) return;
    bool isEmpty = true;
    for (final s in Sections.ids) {
      if (products.forSection(s).isNotEmpty) {
        isEmpty = false;
        break;
      }
    }
    // Seed defaults only on Windows (REST). On mobile the gRPC listener backfills
    // existing products/machines, so seeding here would both hit REST and risk
    // duplicating data before the first snapshot arrives.
    if (isEmpty && !PlatformInfo.isMobile) {
      // 1. Grab your services/providers BEFORE the async gap
      final firestoreService = context.read<FirestoreService>();
      final machinesProvider = context.read<MachinesProvider>();

      // 2. Perform the async operation
      await firestoreService.seedInitialData();

      // 3. Guard the async gap using the State's native mounted check
      if (!mounted) return;

      // 4. Safe to execute everything else
      await products.loadAll();
      await machinesProvider.loadAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildMainLayout(context);
  }

  Widget _buildMainLayout(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final conn = context.watch<ConnectivityProvider>();
    final isTablet = R.isTablet(context);
    final hPad = R.hPad(context);
    final cols = R.sectionCols(context);
    final spacing = R.gridSpacing(context);
    final aspect = R.sectionAspect(context);

    return Scaffold(
      appBar: _buildAppBar(context, auth, conn),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(hPad, 20, hPad, 8),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome, ${auth.user?.username ?? 'QC'}',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: isTablet ? 22 : 20,
                              ),
                        ),
                        Text(
                          'Daily Process Monitoring',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: isTablet ? 15 : 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: hPad),
                  sliver: SliverGrid(
                    delegate: SliverChildListDelegate([
                      ...Sections.all.map(
                        (s) => _SectionCard(
                          section: s,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SectionHomeScreen(section: s),
                            ),
                          ),
                        ),
                      ),
                      _AnalyticsCard(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdvancedAnalyticsScreen(),
                          ),
                        ),
                      ),
                    ]),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: spacing,
                      crossAxisSpacing: spacing,
                      childAspectRatio: aspect,
                    ),
                  ),
                ),
                const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared AppBar ──────────────────────────────────────────

  AppBar _buildAppBar(
    BuildContext context,
    AuthProvider auth,
    ConnectivityProvider conn,
  ) {
    return AppBar(
      titleSpacing: 8,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/icon/icon.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Flexible(
            child: Text('PMA', overflow: TextOverflow.ellipsis),
          ),
          if (auth.isOfflineMode)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(left: 6),
              decoration: const BoxDecoration(
                color: Colors.orange,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
      actions: [
        if (!conn.isOnline)
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: Icon(Icons.cloud_off, color: Colors.orangeAccent, size: 20),
          )
        else
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: SyncStatusBadge(),
          ),
        IconButton(
          icon: const Icon(Icons.download, color: Colors.white),
          tooltip: 'Download Daily Report',
          onPressed: () => _showReportDialog(context),
        ),
        IconButton(
          icon: const Icon(Icons.settings, color: Colors.white),
          tooltip: 'Settings',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.admin_panel_settings, color: Colors.white),
          onSelected: (val) => _onAdminMenu(context, val),
          itemBuilder: (_) => [
            if (auth.isAdmin)
              const PopupMenuItem(value: 'users', child: Text('Manage Users')),
            const PopupMenuItem(
              value: 'products',
              child: Text('Manage Products'),
            ),
            const PopupMenuItem(
              value: 'machines',
              child: Text('Manage Machines'),
            ),
            if (auth.isAdmin)
              const PopupMenuItem(
                value: 'bulkImport',
                child: Text('Bulk Import'),
              ),
          ],
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          onSelected: (val) {
            if (val == 'logout') context.read<AuthProvider>().logout();
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'profile',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    auth.user?.username ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    auth.user?.role ?? '',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'logout', child: Text('Sign Out')),
          ],
        ),
      ],
    );
  }

  void _onAdminMenu(BuildContext context, String val) {
    switch (val) {
      case 'users':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UserManagementScreen()),
        );
        break;
      case 'products':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProductManagementScreen()),
        );
        break;
      case 'machines':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MachineManagementScreen()),
        );
        break;
      case 'bulkImport':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BulkImportScreen()),
        );
        break;
    }
  }

  void _showReportDialog(BuildContext context) {
    showDialog(context: context, builder: (_) => const DownloadReportDialog());
  }
}

// ── Section Card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final SectionInfo section;
  final VoidCallback onTap;

  const _SectionCard({required this.section, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.sectionColor(section.id);
    final machineCount = context
        .watch<MachinesProvider>()
        .forSection(section.id)
        .length;
    return GestureDetector(
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                section.imagePath,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    Container(color: color.withValues(alpha: 0.1)),
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, color.withValues(alpha: 0.88)],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    section.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                    ),
                  ),
                  Text(
                    machineCount > 0 ? '$machineCount machines' : 'Loading…',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Analytics Card ────────────────────────────────────────────────────────────

class _AnalyticsCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AnalyticsCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.hardEdge,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [const Color(0xFF1A237E), const Color(0xFF283593)]
                  : [const Color(0xFF3949AB), const Color(0xFF1A237E)],
            ),
          ),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.analytics, size: 40, color: Colors.white70),
                SizedBox(height: 10),
                Text(
                  'Analytics',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Charts & Reports',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
