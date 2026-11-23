import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../core/utils/date_utils.dart';
import '../providers/connectivity_provider.dart';
import '../services/local_storage_service.dart';

class OfflineBanner extends StatelessWidget {
  final String? section;
  const OfflineBanner({super.key, this.section});

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectivityProvider>();
    if (conn.isOnline) return const SizedBox.shrink();

    final local = context.read<LocalStorageService>();
    final lastSync = section != null
        ? local.getLastSync(section!)
        : local.getLastSyncAll();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.yellow.withValues(alpha: 0.15),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, color: AppColors.yellow, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              lastSync != null
                  ? 'Offline — showing data from ${AppDateUtils.timeAgo(lastSync)}. Changes will sync when online.'
                  : 'Offline — showing locally stored data. Changes will sync when online.',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.yellow,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
