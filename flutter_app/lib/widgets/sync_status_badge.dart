import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/utils/responsive.dart';
import '../providers/connectivity_provider.dart';
import '../providers/entries_provider.dart';

class SyncStatusBadge extends StatelessWidget {
  const SyncStatusBadge({super.key});

  @override
  Widget build(BuildContext context) {
    context.watch<ConnectivityProvider>();
    final ep = context.watch<EntriesProvider>();
    final syncing = context.read<ConnectivityProvider>().syncing;
    final pending = ep.pendingCount;

    if (syncing) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
      );
    }

    if (pending == 0) {
      return const Icon(Icons.cloud_done, color: Colors.greenAccent, size: 20);
    }

    return GestureDetector(
      onTap: () => _showPendingDialog(context, ep),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.cloud_upload, color: Colors.orangeAccent, size: 20),
          Positioned(
            right: -6,
            top: -6,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.orange,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
              child: Text(
                pending > 99 ? '99+' : '$pending',
                style: const TextStyle(
                    color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPendingDialog(BuildContext context, EntriesProvider ep) {
    final pending = ep.localStorageService.getUnsyncedEntries()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.cloud_upload, color: Colors.orange),
            const SizedBox(width: 8),
            Text('Pending Upload (${pending.length})'),
          ],
        ),
        content: SizedBox(
          width: R.dialogWidth(context),
          child: pending.isEmpty
              ? const Text('All entries are synced.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: pending.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final e = pending[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.cloud_upload_outlined,
                          color: Colors.orange, size: 18),
                      title: Text(
                        e.productName,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      subtitle: Text(
                        'Machine ${e.machineNumber} · ${e.section.replaceAll('_', ' ')} · '
                        '${DateFormat('dd/MM HH:mm').format(e.createdAt)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('PENDING',
                            style: TextStyle(
                                fontSize: 9,
                                color: Colors.orange,
                                fontWeight: FontWeight.bold)),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.sync, size: 16),
            label: const Text('Sync Now'),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<ConnectivityProvider>().triggerSync();
            },
          ),
        ],
      ),
    );
  }
}
