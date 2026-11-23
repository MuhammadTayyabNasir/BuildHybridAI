import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../assistant/assistant_service.dart';
import '../../../core/constants/sections.dart';
import '../../../services/local_storage_service.dart';

/// Voice assistant settings: fast mode (anyone) and the expected reading
/// schedule used for "did I miss an entry?" (admins only).
class AssistantSettingsCard extends StatefulWidget {
  const AssistantSettingsCard({super.key, required this.isAdmin});
  final bool isAdmin;

  @override
  State<AssistantSettingsCard> createState() => _AssistantSettingsCardState();
}

class _AssistantSettingsCardState extends State<AssistantSettingsCard> {
  late final LocalStorageService _local = context.read<LocalStorageService>();
  late bool _fast = _local.getMeta(AssistantService.fastModeKey) == '1';
  late ThSchedule _schedule =
      ThSchedule.fromJson(_local.getMeta(AssistantService.scheduleKey));

  Future<void> _setFast(bool v) async {
    await _local.setMeta(AssistantService.fastModeKey, v ? '1' : '0');
    setState(() => _fast = v);
  }

  Future<void> _setSchedule(ThSchedule s) async {
    await _local.setMeta(AssistantService.scheduleKey, s.toJson());
    setState(() => _schedule = s);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fast mode'),
              subtitle: const Text(
                'Save normal readings without asking. Red or out-of-range values, '
                'settings changes, deletes and unclear commands are still read back. '
                'Also by voice: "ab se confirm ki zaroorat nahi".',
              ),
              value: _fast,
              onChanged: _setFast,
            ),
            const Divider(),
            Text('Expected temperature & humidity readings',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              widget.isAdmin
                  ? 'One reading per selected shift for each selected section. Used to answer "koi entry miss to nahi hui?".'
                  : 'Set by an admin.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final s in Sections.all)
                  FilterChip(
                    label: Text(s.name),
                    selected: _schedule.sectionIds.contains(s.id),
                    onSelected: !widget.isAdmin
                        ? null
                        : (on) => _setSchedule(ThSchedule(
                              sectionIds: on
                                  ? [..._schedule.sectionIds, s.id]
                                  : (_schedule.sectionIds.toList()..remove(s.id)),
                              shifts: _schedule.shifts,
                            )),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final (id, label) in const [('morning', 'Morning shift'), ('night', 'Night shift')])
                  FilterChip(
                    label: Text(label),
                    selected: _schedule.shifts.contains(id),
                    onSelected: !widget.isAdmin
                        ? null
                        : (on) => _setSchedule(ThSchedule(
                              sectionIds: _schedule.sectionIds,
                              shifts: on
                                  ? [..._schedule.shifts, id]
                                  : (_schedule.shifts.toList()..remove(id)),
                            )),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
