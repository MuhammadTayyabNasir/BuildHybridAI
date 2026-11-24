import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../assistant/assistant_intent.dart';
import '../../core/constants/sections.dart';
import '../../extraction/extracted_form.dart';
import '../../extraction/row_to_entry.dart';
import '../../providers/auth_provider.dart';
import '../../providers/entries_provider.dart';
import '../../providers/machines_provider.dart';
import '../../providers/products_provider.dart';
import '../../ui/pma_ui.dart';

/// Editable grid of extracted rows. Nothing is saved until the reviewer taps
/// Save; ditto-filled cells are tinted, cells with problems are red, and rows
/// can be unticked to skip them.
class ReviewGridScreen extends StatefulWidget {
  const ReviewGridScreen({
    super.key,
    required this.pages,
    required this.sourceLabel,
    this.initialSection,
  });

  final List<ExtractedPage> pages;

  /// 'pdf:cloud', 'photo:on-device', ...
  final String sourceLabel;
  final String? initialSection;

  @override
  State<ReviewGridScreen> createState() => _ReviewGridScreenState();
}

class _ReviewGridScreenState extends State<ReviewGridScreen> {
  late String _section = widget.initialSection ??
      AssistantIntent.normalizeSection(widget.pages.firstOrNull?.product) ??
      Sections.ids.first;
  late String _shift = RowToEntry.normShift(widget.pages.firstOrNull?.shift ?? '');
  late final List<({ExtractedPage page, ExtractedRow row})> _rows = [
    for (final p in widget.pages)
      for (final r in p.rows) (page: p, row: r),
  ];
  late final Set<int> _skip = {};
  bool _saving = false;

  Future<void> _editCell(int i, FormColumn c) async {
    final ctrl = TextEditingController(text: _rows[i].row[c]);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Row ${i + 1} · ${c.label}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: c.numeric ? const TextInputType.numberWithOptions(decimal: true) : null,
          onSubmitted: (s) => Navigator.pop(ctx, s),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('OK')),
        ],
      ),
    );
    ctrl.dispose();
    if (v != null) setState(() => _rows[i].row.set(c, v));
  }

  Future<void> _save() async {
    final user = context.read<AuthProvider>().user;
    final conv = RowToEntry(
      sectionId: _section,
      shift: _shift,
      products: context.read<ProductsProvider>().allProducts,
      machines: context.read<MachinesProvider>().allMachines,
      operatorId: user?.id ?? '',
      operatorName: user?.username ?? '',
      sourceLabel: widget.sourceLabel,
    );
    final entries = [
      for (var i = 0; i < _rows.length; i++)
        if (!_skip.contains(i)) conv.convert(_rows[i].page, _rows[i].row),
    ];
    if (entries.isEmpty) return;
    setState(() => _saving = true);
    final n = await context.read<EntriesProvider>().addEntries(entries);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved $n packing entries.')));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final issues = <int, List<String>>{
      for (var i = 0; i < _rows.length; i++)
        if (!_skip.contains(i) && _rows[i].row.issues().isNotEmpty) i: _rows[i].row.issues(),
    };
    final dittos = _rows.fold<int>(
        0, (n, r) => n + r.row.origin.values.where((o) => o == CellOrigin.ditto).length);
    final keep = _rows.length - _skip.length;

    return Scaffold(
      backgroundColor: Pma.canvas,
      appBar: PmaAppBar(
        title: const Text('Review extracted rows'),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Pma.ink,
              minimumSize: const Size.fromHeight(52),
              shape: const StadiumBorder(),
            ),
            onPressed: _saving || keep == 0 ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_alt),
            label: Text(issues.isEmpty
                ? 'Save $keep entries'
                : 'Save $keep entries (${issues.length} with warnings)'),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _section,
                  decoration: const InputDecoration(labelText: 'Section'),
                  items: [
                    for (final s in Sections.all) DropdownMenuItem(value: s.id, child: Text(s.name)),
                  ],
                  onChanged: (v) => setState(() => _section = v ?? _section),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _shift,
                  decoration: const InputDecoration(labelText: 'Shift'),
                  items: const [
                    DropdownMenuItem(value: 'morning', child: Text('Morning (A)')),
                    DropdownMenuItem(value: 'night', child: Text('Night (B)')),
                  ],
                  onChanged: (v) => setState(() => _shift = v ?? _shift),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 8, runSpacing: 6, children: [
              TrendPill(label: '${_rows.length} rows · ${widget.pages.length} pages', color: Pma.ink),
              TrendPill(label: '$dittos ditto cells filled', color: Pma.warn),
              if (issues.isNotEmpty) TrendPill(label: '${issues.length} rows need a look', color: Pma.bad),
              const Text('Tap a cell to fix it.', style: TextStyle(color: Pma.inkSoft, fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DataTable(
                  headingRowHeight: 40,
                  dataRowMinHeight: 40,
                  dataRowMaxHeight: 48,
                  columnSpacing: 14,
                  headingRowColor: WidgetStatePropertyAll(Pma.flame.withValues(alpha: 0.10)),
                  columns: [
                    const DataColumn(label: Text('Use')),
                    const DataColumn(label: Text('Pg')),
                    for (final c in FormColumn.values) DataColumn(label: Text(c.label)),
                  ],
                  rows: [
                    for (var i = 0; i < _rows.length; i++)
                      DataRow(
                        color: WidgetStatePropertyAll(issues.containsKey(i)
                            ? Pma.bad.withValues(alpha: 0.06)
                            : _skip.contains(i)
                                ? Colors.black.withValues(alpha: 0.04)
                                : null),
                        cells: [
                          DataCell(Checkbox(
                            value: !_skip.contains(i),
                            onChanged: (v) => setState(() => v == true ? _skip.remove(i) : _skip.add(i)),
                          )),
                          DataCell(Text('${_rows[i].page.page}')),
                          for (final c in FormColumn.values) _cell(i, c),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  DataCell _cell(int i, FormColumn c) {
    final row = _rows[i].row;
    final v = row[c];
    final origin = row.origin[c];
    final bad = c.numeric && v.isNotEmpty && double.tryParse(v) == null;
    return DataCell(
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: bad
              ? Pma.bad.withValues(alpha: 0.15)
              : origin == CellOrigin.ditto
                  ? Pma.warn.withValues(alpha: 0.18)
                  : origin == CellOrigin.edited
                      ? Pma.good.withValues(alpha: 0.15)
                      : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(v.isEmpty ? '—' : v,
            style: TextStyle(
              color: v.isEmpty ? Pma.inkSoft : Pma.ink,
              fontStyle: origin == CellOrigin.ditto ? FontStyle.italic : null,
            )),
      ),
      onTap: () => _editCell(i, c),
    );
  }
}
