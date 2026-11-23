import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';

class StatusChip extends StatelessWidget {
  final String status;
  final String? label;
  final bool small;

  const StatusChip({
    super.key,
    required this.status,
    this.label,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = AppColors.statusColor(status);
    final bg = AppColors.statusBg(status, isDark);
    final text = label ?? _statusLabel();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 8 : 12,
        vertical: small ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: small ? 6 : 8,
            height: small ? 6 : 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: small ? 4 : 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: small ? 11 : 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel() {
    switch (status.toLowerCase()) {
      case 'green':
        return 'OK';
      case 'yellow':
        return 'Warning';
      case 'red':
        return 'Alert';
      case 'okay':
        return 'OK';
      case 'not_okay':
        return 'Not OK';
      case 'na':
        return 'N/A';
      default:
        return status;
    }
  }
}
