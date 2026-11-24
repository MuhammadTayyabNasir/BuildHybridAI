import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/sections.dart';
import '../../models/custom_column_model.dart';
import '../../models/th_threshold_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/entries_provider.dart';
import '../../services/local_storage_service.dart';
import '../../services/report_service.dart';
import '../../services/test_data_service.dart';
import '../../services/th_threshold_service.dart';
import 'widgets/assistant_settings_card.dart';
import 'widgets/settings_section_header.dart';
import 'widgets/day_dropdown.dart';
import 'widgets/report_card.dart';
import 'widgets/custom_column_dialog.dart';
import 'widgets/th_threshold_tile.dart';
import '../../../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _inputMode = 'auto';
  int _excelRows = 8;
  int _thExcelRows = 8;
  int _thRepromptGap = 0;

  bool _entriesAuto = false;
  int _entriesDay = 0;

  bool _analysisAuto = false;
  int _analysisDay = DateTime.monday;
  int _analysisWeeks = 4;

  String _savePath = '';
  bool _whatsappShare = false;
  final _whatsappCtrl = TextEditingController();

  List<CustomColumn> _customColumns = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _whatsappCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    if (prefs.containsKey('excel_input_mode') &&
        !prefs.containsKey('input_mode')) {
      final old = prefs.getBool('excel_input_mode') ?? false;
      await prefs.setString('input_mode', old ? 'excel' : 'auto');
      await prefs.remove('excel_input_mode');
    }

    setState(() {
      _inputMode = prefs.getString('input_mode') ?? 'auto';
      _excelRows = prefs.getInt('excel_rows') ?? 8;
      _thExcelRows = prefs.getInt('th_excel_rows') ?? 8;
      _thRepromptGap = prefs.getInt('th_reprompt_gap_minutes') ?? 0;
      _entriesAuto = prefs.getBool(kReportEntriesAuto) ?? false;
      _entriesDay = prefs.getInt(kReportEntriesDay) ?? 0;
      _analysisAuto = prefs.getBool(kReportAnalysisAuto) ?? false;
      _analysisDay = prefs.getInt(kReportAnalysisDay) ?? DateTime.monday;
      _analysisWeeks = prefs.getInt(kReportAnalysisWeeks) ?? 4;
      _savePath = prefs.getString(kReportSavePath) ?? '';
      _whatsappShare = prefs.getBool(kWhatsappShare) ?? false;
    });

    _whatsappCtrl.text = prefs.getString(kWhatsappRecipient) ?? '';
    final cols = await CustomColumnsService.load();
    if (mounted) {
      setState(() {
        _customColumns = cols;
        _loading = false;
      });
    }
  }

  Future<void> _setInputMode(String v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('input_mode', v);
    setState(() => _inputMode = v);
  }

  Future<void> _setPref<T>(String key, T value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) await prefs.setBool(key, value);
    if (value is int) await prefs.setInt(key, value);
    if (value is String) await prefs.setString(key, value);
    if (value is double) await prefs.setDouble(key, value);
  }

  Future<void> _manualSync() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Syncing…'), duration: Duration(seconds: 1)),
    );
    final result = await context.read<EntriesProvider>().manualSync();
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Synced — ${result.uploaded} uploaded, ${result.downloaded} downloaded',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = context.read<LocalStorageService>();
    final cp = context.watch<ConnectivityProvider>();
    final authExpiry = local.getAuthCacheExpiry();
    final pending = local.getUnsyncedEntries().length;
    final isAdmin = context.read<AuthProvider>().isAdmin;
    final isViewer = context.read<AuthProvider>().isViewer;

    if (isViewer) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const Center(
          child: Text(
            'Access Denied. Admins only.',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SettingsSectionHeader(title: 'Voice Assistant'),
                AssistantSettingsCard(isAdmin: isAdmin),
                const SizedBox(height: 20),
                const SettingsSectionHeader(title: 'Entry Input Mode'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Choose how to enter packing data:',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 14),
                        SegmentedButton<String>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: 'form',
                              label: Text('Form'),
                              icon: Icon(Icons.list_alt),
                            ),
                            ButtonSegment(
                              value: 'auto',
                              label: Text('Auto'),
                              icon: Icon(Icons.devices),
                            ),
                            ButtonSegment(
                              value: 'excel',
                              label: Text('Excel'),
                              icon: Icon(Icons.table_chart),
                            ),
                          ],
                          selected: {_inputMode},
                          onSelectionChanged: (v) => _setInputMode(v.first),
                        ),
                        const SizedBox(height: 14),
                        _modeDescription(context),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const SettingsSectionHeader(title: 'Default Excel Rows'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Number of pre-filled rows when opening Excel entry screens:',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Icon(Icons.assignment_outlined, size: 18),
                            const SizedBox(width: 8),
                            const Text(
                              'Packing Report',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '$_excelRows rows',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _excelRows.toDouble(),
                          min: 4,
                          max: 30,
                          divisions: 26,
                          label: '$_excelRows',
                          onChanged: (v) =>
                              setState(() => _excelRows = v.round()),
                          onChangeEnd: (v) => _setPref('excel_rows', v.round()),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.thermostat_outlined, size: 18),
                            const SizedBox(width: 8),
                            const Text(
                              'Temp & Humidity',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '$_thExcelRows rows',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _thExcelRows.toDouble(),
                          min: 4,
                          max: 30,
                          divisions: 26,
                          label: '$_thExcelRows',
                          onChanged: (v) =>
                              setState(() => _thExcelRows = v.round()),
                          onChangeEnd: (v) =>
                              _setPref('th_excel_rows', v.round()),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text(
                              '4 rows',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                            Text(
                              '30 rows',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const SettingsSectionHeader(title: 'Temp & Humidity Prompt'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'When you open a section it asks for Temp & Humidity '
                          'first. A QC visits ~4×/day — choose how soon it may '
                          're-ask after a reading was just logged:',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final m in const [0, 30, 60, 90, 120])
                              ChoiceChip(
                                label: Text(
                                  m == 0 ? 'Ask every time' : '$m min',
                                ),
                                selected: _thRepromptGap == m,
                                onSelected: (_) {
                                  setState(() => _thRepromptGap = m);
                                  _setPref('th_reprompt_gap_minutes', m);
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _thRepromptGap == 0
                              ? 'Prompts on every section open (recommended for 4×/day visits).'
                              : 'Won\'t re-ask if a reading was logged in the last $_thRepromptGap minutes.',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const SettingsSectionHeader(
                  title: 'Temp & Humidity Thresholds',
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAdmin
                              ? 'Green = safe · Yellow = green +1 to +2 · Red = above that. '
                                    'Set the green ceiling per section — the yellow band is always +2.'
                              : 'Green = safe · Yellow = warning · Red = alert. '
                                    'Only an admin can change these values.',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ValueListenableBuilder<Map<String, ThThreshold>>(
                          valueListenable: context
                              .watch<ThThresholdService>()
                              .current,
                          builder: (context, map, _) {
                            return Column(
                              children: [
                                for (final sec in Sections.all)
                                  ThThresholdTile(
                                    section: sec,
                                    threshold:
                                        map[sec.id] ??
                                        ThThreshold.defaults(sec.id),
                                    editable: isAdmin,
                                    onChanged: (updated) =>
                                        context.read<ThThresholdService>().save(
                                          updated,
                                          updatedBy:
                                              context
                                                  .read<AuthProvider>()
                                                  .user
                                                  ?.username ??
                                              'admin',
                                        ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                if(isAdmin)
                  const SizedBox(height: 20),
                // Look for the "QC Shift Auto-Logout" Card and replace it with this:
                if(isAdmin)
                const SettingsSectionHeader(title: 'QC Shift Auto-Logout'),
                if(isAdmin)
                  Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Consumer<SettingsService>(
                      builder: (context, settingsService, _) {
                        final shiftSettings = settingsService.shiftSettings;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'QC Operators will be automatically logged out exactly at these times. '
                              'Admins and Viewers are not affected. Changes here apply to ALL devices instantly.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(
                                      Icons.wb_sunny_outlined,
                                      size: 18,
                                    ),
                                    label: Text(
                                      'Morning: ${shiftSettings.morningEnd.format(context)}',
                                    ),
                                    onPressed: () async {
                                      final picked = await showTimePicker(
                                        context: context,
                                        initialTime: shiftSettings.morningEnd,
                                      );
                                      if (picked != null) {
                                        settingsService.updateShiftTimes(
                                          picked,
                                          shiftSettings.nightEnd,
                                        );
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(
                                      Icons.nightlight_outlined,
                                      size: 18,
                                    ),
                                    label: Text(
                                      'Night: ${shiftSettings.nightEnd.format(context)}',
                                    ),
                                    onPressed: () async {
                                      final picked = await showTimePicker(
                                        context: context,
                                        initialTime: shiftSettings.nightEnd,
                                      );
                                      if (picked != null) {
                                        settingsService.updateShiftTimes(
                                          shiftSettings.morningEnd,
                                          picked,
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const SettingsSectionHeader(title: 'Real-time Sync'),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.bolt, color: Colors.green),
                    title: const Text('Real-time sync is active'),
                    subtitle: const Text(
                      'Changes upload instantly and arrive live — no interval needed.',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: cp.syncing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton.icon(
                            icon: const Icon(Icons.sync, size: 16),
                            label: const Text('Sync Now'),
                            onPressed: cp.isOnline ? _manualSync : null,
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                const SettingsSectionHeader(title: 'Sync Status'),
                Card(
                  child: ListTile(
                    leading: Icon(
                      pending == 0 ? Icons.cloud_done : Icons.cloud_upload,
                      color: pending == 0 ? Colors.green : Colors.orange,
                    ),
                    title: Text(
                      pending == 0
                          ? 'All entries synced'
                          : '$pending entries pending upload',
                    ),
                    subtitle: pending > 0
                        ? const Text(
                            'Upload automatically when online, or tap Sync Now above.',
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 20),
                const SettingsSectionHeader(title: 'Offline Session'),
                Card(
                  child: ListTile(
                    leading: Icon(
                      authExpiry != null && authExpiry.isAfter(DateTime.now())
                          ? Icons.lock_open
                          : Icons.lock_outline,
                      color:
                          authExpiry != null &&
                              authExpiry.isAfter(DateTime.now())
                          ? Colors.green
                          : Colors.grey,
                    ),
                    title: const Text('Offline login session'),
                    subtitle: authExpiry == null
                        ? const Text(
                            'No session cached. Log in while online to enable.',
                          )
                        : authExpiry.isAfter(DateTime.now())
                        ? Text(
                            'Valid until ${_fmtDate(authExpiry)}',
                            style: const TextStyle(color: Colors.green),
                          )
                        : const Text(
                            'Session expired. Please log in online to refresh.',
                            style: TextStyle(color: Colors.red),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                const SettingsSectionHeader(title: 'Reports'),
                ReportCard(
                  icon: Icons.table_rows_outlined,
                  title: 'Entries Log',
                  subtitle:
                      'One row per packing entry. Color-coded by QC status.',
                  enabled: _entriesAuto,
                  onToggle: (v) {
                    setState(() => _entriesAuto = v);
                    _setPref(kReportEntriesAuto, v);
                  },
                  child: _entriesAuto
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 12),
                            const Text(
                              'Auto-run schedule:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            DayDropdown(
                              value: _entriesDay,
                              includeEveryDay: true,
                              onChanged: (v) {
                                setState(() => _entriesDay = v);
                                _setPref(kReportEntriesDay, v);
                              },
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _entriesDay == 0
                                  ? 'Downloads yesterday\'s entries every day when app opens.'
                                  : 'Downloads yesterday\'s entries every ${_dayName(_entriesDay)} when app opens.',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        )
                      : null,
                ),
                const SizedBox(height: 12),
                ReportCard(
                  icon: Icons.analytics_outlined,
                  title: 'QC Analysis',
                  subtitle: 'Pass rates per machine & metric. Weekly trends.',
                  enabled: _analysisAuto,
                  onToggle: (v) {
                    setState(() => _analysisAuto = v);
                    _setPref(kReportAnalysisAuto, v);
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_analysisAuto) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Auto-run on:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        DayDropdown(
                          value: _analysisDay,
                          includeEveryDay: false,
                          onChanged: (v) {
                            setState(() => _analysisDay = v);
                            _setPref(kReportAnalysisDay, v);
                          },
                        ),
                        const SizedBox(height: 8),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.date_range_outlined, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'Include last $_analysisWeeks week${_analysisWeeks == 1 ? '' : 's'}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _analysisWeeks.toDouble(),
                        min: 1,
                        max: 8,
                        divisions: 7,
                        label: '$_analysisWeeks wk',
                        onChanged: (v) =>
                            setState(() => _analysisWeeks = v.round()),
                        onChangeEnd: (v) =>
                            _setPref(kReportAnalysisWeeks, v.round()),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text(
                            '1 week',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          Text(
                            '8 weeks',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                      if (_analysisAuto) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Downloads every ${_dayName(_analysisDay)} — covers last $_analysisWeeks week${_analysisWeeks == 1 ? '' : 's'}.',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // RESTORED SECTIONS BELOW
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.folder_outlined, size: 20),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Download Folder',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        FutureBuilder<String>(
                          future: _savePath.isEmpty
                              ? _defaultFolderLabel()
                              : Future.value(_savePath),
                          builder: (context, snap) {
                            final label =
                                snap.data ??
                                (_savePath.isEmpty
                                    ? 'Default (app folder)'
                                    : _savePath);
                            return Text(
                              label,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                                fontFamily: 'monospace',
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              icon: const Icon(Icons.folder_open, size: 16),
                              label: const Text('Change Folder'),
                              onPressed: _changeDownloadFolder,
                            ),
                            if (_savePath.isNotEmpty)
                              TextButton(
                                onPressed: _resetDownloadFolder,
                                child: const Text('Reset to default'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Reports are saved here. Choose once — used for all future downloads.',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const SettingsSectionHeader(title: 'WhatsApp Sharing'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Offer WhatsApp share after export',
                          ),
                          subtitle: const Text(
                            'Adds a Share button so you can send the Excel via WhatsApp.',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: _whatsappShare,
                          onChanged: (v) {
                            setState(() => _whatsappShare = v);
                            _setPref(kWhatsappShare, v);
                          },
                        ),
                        if (_whatsappShare) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: _whatsappCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Default recipient (contact or group)',
                              hintText: 'e.g. Production Group',
                              isDense: true,
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            onChanged: (v) =>
                                _setPref(kWhatsappRecipient, v.trim()),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            "WhatsApp can't auto-pick the recipient for a file — it opens "
                            "with the Excel attached and you tap this contact. The name is "
                            "just a reminder.",
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const SettingsSectionHeader(
                  title: 'Custom Enteries ',
                ),
                Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_customColumns.isEmpty)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Text(
                            'No custom columns yet. Add extra columns to track '
                            'additional data in the bulk-entry sheet.',
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        )
                      else
                        ReorderableListView(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          onReorder: (oldIdx, newIdx) {
                            setState(() {
                              if (newIdx > oldIdx) newIdx--;
                              final col = _customColumns.removeAt(oldIdx);
                              _customColumns.insert(newIdx, col);
                            });
                            CustomColumnsService.save(_customColumns);
                          },
                          children: [
                            for (final col in _customColumns)
                              ListTile(
                                key: ValueKey(col.id),
                                dense: true,
                                leading: const Icon(
                                  Icons.drag_handle,
                                  size: 20,
                                  color: Colors.grey,
                                ),
                                title: Text(
                                  col.heading,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  col.typeLabel +
                                      (col.type == CustomColumnType.options &&
                                              col.options.isNotEmpty
                                          ? ' · ${col.options.join(", ")}'
                                          : ''),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                      ),
                                      tooltip: 'Edit',
                                      onPressed: () => _editColumn(col),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 18,
                                        color: Colors.red,
                                      ),
                                      tooltip: 'Delete',
                                      onPressed: () => _deleteColumn(col),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      const Divider(height: 1),
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.add_circle_outline, size: 20),
                        title: const Text('Add Column'),
                        onTap: _addColumn,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Download Now',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(
                                  Icons.table_rows_outlined,
                                  size: 16,
                                ),
                                label: const Text('Entries'),
                                onPressed: () => _quickDownload('entries'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(
                                  Icons.analytics_outlined,
                                  size: 16,
                                ),
                                label: const Text('Analysis'),
                                onPressed: () => _quickDownload('analysis'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Entries = yesterday. Analysis = last N weeks (setting above).',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isAdmin) ...[
                  const SizedBox(height: 20),
                  const SettingsSectionHeader(title: 'Test Data (Admin)'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'For QC testing only. Seed generates fake entries across '
                            'the last 60 days — every section, machine, product variant '
                            'and supervisor, with a realistic pass/warning/fail spread — '
                            'so you can exercise the reports and analytics. Clear removes '
                            'ALL entries (local + cloud) before handover.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(
                                    Icons.auto_awesome,
                                    size: 16,
                                  ),
                                  label: const Text('Seed sample data'),
                                  onPressed: _seedTestData,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    side: const BorderSide(color: Colors.red),
                                  ),
                                  icon: const Icon(
                                    Icons.delete_sweep_outlined,
                                    size: 16,
                                  ),
                                  label: const Text('Clear ALL data'),
                                  onPressed: _wipeTestData,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tip: remove this section before final handover to the operator.',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Future<void> _seedTestData() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seed sample data?'),
        content: const Text(
          'Generates fake QC entries across the last 60 days for testing. '
          'They sync to the cloud like real entries. Run "Clear ALL data" '
          'afterwards to remove them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Seed'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final svc = TestDataService(
      context.read<EntriesProvider>(),
      context.read<LocalStorageService>(),
    );
    final count = await _runWithProgress(
      'Seeding test data…',
      (onProgress) => svc.seed(onProgress: onProgress),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count == null
              ? 'Cancelled'
              : count == 0
              ? 'No products/machines found — open the app once so they load, then retry.'
              : 'Seeded $count test entries. They\'re uploading in the background.',
        ),
        backgroundColor: (count ?? 0) > 0 ? Colors.green : Colors.orange,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  Future<void> _wipeTestData() async {
    final total = context.read<LocalStorageService>().getEntries().length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear ALL data?'),
        content: Text(
          'This permanently deletes all $total packing entries from this device '
          'AND the cloud. This cannot be undone. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final svc = TestDataService(
      context.read<EntriesProvider>(),
      context.read<LocalStorageService>(),
    );
    final count = await _runWithProgress(
      'Clearing all data…',
      (onProgress) => svc.wipeAll(onProgress: onProgress),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(count == null ? 'Cancelled' : 'Deleted $count entries.'),
        backgroundColor: Colors.blueGrey,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  Future<int?> _runWithProgress(
    String title,
    Future<int> Function(void Function(int done, int total) onProgress) task,
  ) async {
    final progress = ValueNotifier<(int, int)>((0, 0));
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: ValueListenableBuilder<(int, int)>(
            valueListenable: progress,
            builder: (_, v, _) {
              final (done, total) = v;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: total == 0 ? null : done / total,
                  ),
                  const SizedBox(height: 12),
                  Text(total == 0 ? 'Preparing…' : '$done / $total'),
                ],
              );
            },
          ),
        ),
      ),
    );
    int? result;
    try {
      result = await task((d, t) => progress.value = (d, t));
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      progress.dispose();
    }
    return result;
  }

  Future<void> _addColumn() async {
    final result = await showDialog<CustomColumn>(
      context: context,
      builder: (ctx) => const CustomColumnDialog(),
    );
    if (result == null) return;
    setState(() => _customColumns.add(result));
    await CustomColumnsService.save(_customColumns);
  }

  Future<void> _editColumn(CustomColumn col) async {
    final result = await showDialog<CustomColumn>(
      context: context,
      builder: (ctx) => CustomColumnDialog(existing: col),
    );
    if (result == null) return;
    final idx = _customColumns.indexWhere((c) => c.id == col.id);
    if (idx == -1) return;
    setState(() => _customColumns[idx] = result);
    await CustomColumnsService.save(_customColumns);
  }

  Future<void> _deleteColumn(CustomColumn col) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Column'),
        content: Text('Remove "${col.heading}" from the bulk-entry sheet?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _customColumns.removeWhere((c) => c.id == col.id));
    await CustomColumnsService.save(_customColumns);
  }

  Future<void> _changeDownloadFolder() async {
    String? picked;
    if (kIsWeb) return; // the browser always saves to its downloads folder
    if (Platform.isAndroid || Platform.isIOS) {
      picked = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose download folder',
      );
    } else {
      picked = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose download folder',
      );
    }
    if (picked != null && picked.isNotEmpty) {
      final folder = picked;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kReportSavePath, folder);
      if (mounted) setState(() => _savePath = folder);
    }
  }

  Future<void> _resetDownloadFolder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kReportSavePath);
    if (mounted) setState(() => _savePath = '');
  }

  Future<String> _defaultFolderLabel() async {
    // dart:io Platform throws in the browser.
    if (kIsWeb) return 'Browser downloads folder';
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Public';
      return '$home\\Downloads';
    }
    return (await getApplicationDocumentsDirectory()).path;
  }

  Future<void> _quickDownload(String type) async {
    try {
      final svc = context.read<ReportService>();
      String path;
      if (type == 'entries') {
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        path = await svc.generateEntriesReport(from: yesterday, to: yesterday);
      } else {
        final now = DateTime.now();
        path = await svc.generateAnalysisReport(
          from: now.subtract(Duration(days: _analysisWeeks * 7)),
          to: now,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved: $path'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _modeDescription(BuildContext context) {
    final (icon, title, subtitle) = switch (_inputMode) {
      'excel' => (
        Icons.table_chart,
        'Excel mode — all devices',
        'Bulk row entry with one Save button. Fastest for high-volume data.',
      ),
      'form' => (
        Icons.list_alt,
        'Form mode — all devices',
        'One entry at a time. Recommended for phones in tight spaces.',
      ),
      _ => (
        Icons.devices,
        'Auto-detect (recommended)',
        'Wide screens (tablet/desktop) → Excel view. Narrow screens (phone) → Form.',
      ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _fmtDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';

  String _dayName(int d) =>
      const {
        0: 'day',
        1: 'Monday',
        2: 'Tuesday',
        3: 'Wednesday',
        4: 'Thursday',
        5: 'Friday',
        6: 'Saturday',
        7: 'Sunday',
      }[d] ??
      'Monday';
}
