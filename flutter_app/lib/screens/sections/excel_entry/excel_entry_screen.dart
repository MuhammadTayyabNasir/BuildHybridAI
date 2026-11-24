import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/sections.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/status_utils.dart';
import '../../../models/custom_column_model.dart';
import '../../../models/machine_model.dart';
import '../../../models/packing_entry_model.dart';
import '../../../models/product_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/entries_provider.dart';
import '../../../providers/machines_provider.dart';
import '../../../providers/products_provider.dart';

// Modular UI imports
import 'widgets/option_picker_dialog.dart';
import 'widgets/product_picker_dialog.dart';
import 'widgets/status_detail_dialogs.dart';
import '../../../ui/pma_ui.dart';

// ── Column widths ─────────────────────────────────────────────────────────────
const _wNum = 36.0;
const _wMachine = 110.0;
const _wProduct = 175.0;
const _wShift = 68.0;
const _wDate = 86.0;
const _wExpiry = 86.0;
const _wWeight = 78.0;
const _wPouch = 72.0;
const _wMoist = 76.0;
const _wStatus = 86.0;
const _wDel = 44.0;
const _rowH = 52.0;
const _headH = 38.0;

const _defaultRowsFallback = 8;

// ── Per-row mutable state ─────────────────────────────────────────────────────
class _Row {
  MachineModel? machine;
  ProductModel? product;
  String shift;
  DateTime manufacture;
  DateTime? expiry;
  final TextEditingController grossWt = TextEditingController();
  final TextEditingController p1 = TextEditingController();
  final TextEditingController p2 = TextEditingController();
  final TextEditingController p3 = TextEditingController();
  final TextEditingController p4 = TextEditingController();
  final TextEditingController moisture = TextEditingController();
  String printStatus = 'okay';
  String? printColor;
  String printRemarks = '';
  String leakageStatus = 'green';
  String leakageRemarks = '';
  bool hasError = false;

  Map<String, TextEditingController> customCtrls = {};

  _Row({required this.shift, required this.manufacture});

  void dispose() {
    grossWt.dispose();
    p1.dispose();
    p2.dispose();
    p3.dispose();
    p4.dispose();
    moisture.dispose();
    for (final c in customCtrls.values) {
      c.dispose();
    }
  }

  double? _parse(TextEditingController c) => double.tryParse(c.text.trim());

  String get weightStatus {
    if (product == null) return 'green';
    final weights = [_parse(p1), _parse(p2), _parse(p3), _parse(p4)];
    return StatusUtils.weightStatusOfPouches(
      weights,
      product!.weightGrams,
      toleranceGreen: product!.weightToleranceGreen,
      toleranceYellow: product!.weightToleranceYellow,
    );
  }

  String get moistureStatusCalc {
    if (product == null) return 'na';
    final m = _parse(moisture);
    if (m == null) return 'na';
    return StatusUtils.moistureStatus(
      m,
      product!.moistureMax,
      product!.moistureYellowMax,
    );
  }
// Inside class _Row
  bool isValid(List<CustomColumn> customCols) {
    if (machine == null || product == null) return false;

    // Check if any compulsory custom column is empty
    for (final col in customCols) {
      if (col.isRequired) {
        final ctrl = customCtrls[col.id];
        if (ctrl == null || ctrl.text.trim().isEmpty) return false;
      }
    }
    return true;
  }
  PackingEntryModel toEntry(
    String operatorId,
    String operatorName,
    String section,
  ) {
    final pList = [_parse(p1), _parse(p2), _parse(p3), _parse(p4)];
    final now = DateTime.now();
    final fields = {
      for (final e in customCtrls.entries)
        if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
    };
    return PackingEntryModel(
      id: '',
      machineId: machine!.id,
      machineNumber: machine!.number,
      section: section,
      productId: product!.id,
      productName: product!.name,
      price: product!.price,
      shift: shift,
      operatorId: operatorId,
      operatorName: operatorName,
      dateCodingManufacture: manufacture,
      dateCodingExpiry:
          expiry ?? AppDateUtils.expiryDate(manufacture, product!.expiryDays),
      grossWeight: _parse(grossWt) ?? product!.weightGrams,
      pouch1Weight: pList[0],
      pouch2Weight: pList[1],
      pouch3Weight: pList[2],
      pouch4Weight: pList[3],
      moistureIdeal: product!.moistureMax > 0 ? product!.moistureMax : null,
      moistureActual: _parse(moisture),
      weightStatus: weightStatus,
      printingStatus: printStatus,
      printingColor: printColor,
      printingRemarks: printRemarks.isEmpty ? null : printRemarks,
      leakageStatus: leakageStatus == 'minor'
          ? 'yellow'
          : (leakageStatus == 'major' ? 'red' : leakageStatus),
      leakageRemarks: leakageRemarks.isEmpty ? null : leakageRemarks,
      moistureStatus: moistureStatusCalc,
      customFields: fields.isEmpty ? null : fields,
      isSynced: false,
      createdAt: now,
      updatedAt: now,
    );
  }
}

// ── Main screen ───────────────────────────────────────────────────────────────
class ExcelEntryScreen extends StatefulWidget {
  final SectionInfo section;

  const ExcelEntryScreen({super.key, required this.section});

  @override
  State<ExcelEntryScreen> createState() => _ExcelEntryScreenState();
}

class _ExcelEntryScreenState extends State<ExcelEntryScreen> {
  final List<_Row> _rows = [];
  List<CustomColumn> _customColumns = [];
  bool _saving = false;
  bool _ready = false;
  int _defaultRows = _defaultRowsFallback;
  final _hScrollCtrl = ScrollController();
  late final auth = context.read<AuthProvider>();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final cols = await CustomColumnsService.load();
    if (!context.mounted) return;
    _defaultRows = prefs.getInt('excel_rows') ?? _defaultRowsFallback;
    _customColumns = cols;
    for (int i = 0; i < _defaultRows; i++) {
      _addRowInternal();
    }
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _hScrollCtrl.dispose();
    super.dispose();
  }

  void _addRowInternal() {
    final last = _rows.isEmpty ? null : _rows.last;
    final row =
        _Row(
            shift: last?.shift ?? ShiftHelper.detectShift(),
            manufacture: last?.manufacture ?? DateTime.now(),
          )
          ..machine = last?.machine
          ..product = last?.product
          ..expiry = last?.expiry;
    for (final col in _customColumns) {
      row.customCtrls[col.id] = TextEditingController();
    }
    _rows.add(row);
  }

  void _addRow() {
    _addRowInternal();
    setState(() {});
  }

  void _removeRow(int i) {
    if (_rows.length == 1) return;
    final r = _rows.removeAt(i);
    r.dispose();
    setState(() {});
  }

  Future<void> _saveAll() async {
    if (auth.user?.isViewer == true) return;

    bool anyError = false;
    for (final r in _rows) {
      r.hasError = !r.isValid(_customColumns); // Pass the columns here
      if (r.hasError) anyError = true;
    }
    setState(() {});

    if (anyError) {
      // Updated error message
      _showSnack('Please fill in Machine, Product, and any required Custom Columns (*).', error: true);
      return;
    }

    setState(() => _saving = true);
    final ep = context.read<EntriesProvider>();
    final uid = auth.user?.id ?? '';
    final name = auth.user?.username ?? '';

    final entries = _rows
        .map((r) => r.toEntry(uid, name, widget.section.id))
        .toList();
    final saved = await ep.addEntries(entries);

    if (mounted) {
      setState(() => _saving = false);
      _showSnack('$saved ${saved == 1 ? "entry" : "entries"} saved · syncing…');
      Navigator.pop(context);
    } else {
      return;
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.red : null,
      ),
    );
  }

  Future<ProductModel?> _pickProduct(_Row row) async {
    final pp = context.read<ProductsProvider>();
    return showDialog<ProductModel>(
      context: context,
      builder: (ctx) => ProductPickerDialog(
        allProducts: pp.allProducts,
        currentSectionId: widget.section.id,
        selected: row.product,
      ),
    );
  }

  Future<DateTime?> _pickDate(DateTime initial) => showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2024),
    lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
  );

  Future<void> _editPrintDetails(_Row row) async {
    final result = await showDialog<(String, String?, String)>(
      context: context,
      builder: (_) => PrintDetailDialog(
        status: row.printStatus,
        color:
            row.printColor ?? (row.printStatus == 'minor' ? 'yellow' : 'red'),
        remarks: row.printRemarks,
      ),
    );
    if (result != null && context.mounted) {
      setState(() {
        row.printStatus = result.$1;
        row.printColor = result.$2;
        row.printRemarks = result.$3;
      });
    }
  }

  Future<void> _editLeakageDetails(_Row row) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => LeakageDetailDialog(
        status: row.leakageStatus,
        remarks: row.leakageRemarks,
      ),
    );
    if (result != null && context.mounted) {
      setState(() {
        row.leakageStatus = result.$1;
        row.leakageRemarks = result.$2;
      });
    }
  }

  Future<void> _pickOption(CustomColumn col, _Row row) async {
    final ctrl = row.customCtrls[col.id]!;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => OptionPickerDialog(
        heading: col.heading,
        options: col.options,
        selected: ctrl.text,
      ),
    );
    if (picked != null) setState(() => ctrl.text = picked);
  }

  // ── NEW: Live Coloring Helpers ──────────────────────────────────────────────
  Color? _getWeightColor(String text, ProductModel? product) {
    if (product == null) return null;
    final val = double.tryParse(text.trim());
    if (val == null || val <= 0) return null;

    final status = StatusUtils.weightStatus(
      val,
      product.weightGrams,
      toleranceGreen: product.weightToleranceGreen,
      toleranceYellow: product.weightToleranceYellow,
    );
    return AppColors.statusColor(status);
  }

  Color? _getMoistureColor(String text, ProductModel? product) {
    if (product == null) return null;
    final val = double.tryParse(text.trim());
    if (val == null || val <= 0) return null;

    final status = StatusUtils.moistureStatus(
      val,
      product.moistureMax,
      product.moistureYellowMax,
    );
    if (status == 'na') return null;
    return AppColors.statusColor(status);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(
        appBar: PmaAppBar(title: Text('${widget.section.name} — Bulk Entry')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final color = AppColors.sectionColor(widget.section.id);
    final valid = _rows.where((r) => r.isValid(_customColumns)).length;

    return Scaffold(
      appBar: PmaAppBar(
        title: Text('${widget.section.name} — Bulk Entry'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '$valid / ${_rows.length} ready',
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_alt, size: 18),
            label: Text(_saving ? 'Saving…' : 'Save All ($valid)'),
            onPressed: _saving ? null : _saveAll,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _hScrollCtrl,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _tableWidth,
                child: Column(
                  children: [
                    _buildHeader(color),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _rows.length,
                        itemBuilder: (_, i) =>
                            _buildDataRow(i, _rows[i], color),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _buildFooter(color),
        ],
      ),
    );
  }

  double get _tableWidth {
    final customWidth = _customColumns.fold<double>(0, (s, c) => s + c.width);
    return _wNum +
        _wMachine +
        _wProduct +
        _wShift +
        _wDate +
        _wExpiry +
        _wWeight +
        _wPouch * 4 +
        _wMoist +
        _wStatus * 2 +
        customWidth +
        _wDel +
        16;
  }

  Widget _buildHeader(Color accent) {
    return Container(
      height: _headH,
      color: accent.withValues(alpha: 0.12),
      child: Row(
        children: [
          _hCell('#', _wNum),
          _hCell('Machine', _wMachine),
          _hCell('Product', _wProduct),
          _hCell('Shift', _wShift),
          _hCell('Mfg Date', _wDate),
          _hCell('Exp Date', _wExpiry),
          _hCell('Gross (g)', _wWeight),
          _hCell('P1 (g)', _wPouch),
          _hCell('P2 (g)', _wPouch),
          _hCell('P3 (g)', _wPouch),
          _hCell('P4 (g)', _wPouch),
          _hCell('Moist.', _wMoist),
          _hCell('Print', _wStatus),
          _hCell('Leakage', _wStatus),
          // Add asterisk if custom column is required
          for (final col in _customColumns)
            _hCell(col.heading + (col.isRequired ? ' *' : ''), col.width),
          SizedBox(width: _wDel),
        ],
      ),
    );
  }

  Widget _hCell(String label, double width) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );

  Widget _buildDataRow(int i, _Row row, Color accent) {
    final machines = context.watch<MachinesProvider>().forSection(
      widget.section.id,
    );
    final odd = i.isOdd;
    final bg = row.hasError
        ? AppColors.red.withValues(alpha: 0.07)
        : odd
        ? Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
        : null;

    return Container(
      height: _rowH,
      color: bg,
      child: Row(
        children: [
          SizedBox(
            width: _wNum,
            child: Center(
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          _machineCell(row, machines),
          _productCell(row, i),
          _shiftCell(row),
          _dateCell(row),
          _expiryCell(row),
          _grossWeightCell(row),

          // Pass dynamic status colors to cells
          _numCell(
            row.p1,
            _wPouch,
            statusColor: _getWeightColor(row.p1.text, row.product),
          ),
          _numCell(
            row.p2,
            _wPouch,
            statusColor: _getWeightColor(row.p2.text, row.product),
          ),
          _numCell(
            row.p3,
            _wPouch,
            statusColor: _getWeightColor(row.p3.text, row.product),
          ),
          _numCell(
            row.p4,
            _wPouch,
            statusColor: _getWeightColor(row.p4.text, row.product),
          ),
          _numCell(
            row.moisture,
            _wMoist,
            statusColor: _getMoistureColor(row.moisture.text, row.product),
          ),

          _statusCell(
            label: _printLabel(row),
            color: _printColor(row),
            onTap: () => _editPrintDetails(row),
            width: _wStatus,
          ),
          _statusCell(
            label: _leakLabel(row),
            color: _leakColor(row),
            onTap: () => _editLeakageDetails(row),
            width: _wStatus,
          ),
          for (final col in _customColumns) _customCell(col, row),
          SizedBox(
            width: _wDel,
            child: IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 18),
              color: AppColors.red.withValues(alpha: 0.7),
              onPressed: _rows.length > 1 ? () => _removeRow(i) : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _machineCell(_Row row, List<MachineModel> machines) {
    return SizedBox(
      width: _wMachine,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<MachineModel>(
            value: machines.contains(row.machine) ? row.machine : null,
            isDense: true,
            isExpanded: true,
            hint: const Text('Machine', style: TextStyle(fontSize: 12)),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            items: machines
                .map(
                  (m) => DropdownMenuItem(
                    value: m,
                    child: Text(
                      'M ${m.number}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                )
                .toList(),
            onChanged: (m) => setState(() => row.machine = m),
          ),
        ),
      ),
    );
  }

  Widget _productCell(_Row row, int i) {
    return SizedBox(
      width: _wProduct,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () async {
            final p = await _pickProduct(row);
            if (p != null) {
              setState(() {
                row.product = p;
                  row.grossWt.text = p.weightGrams.toStringAsFixed(0);
                row.expiry = AppDateUtils.expiryDate(
                  row.manufacture,
                  p.expiryDays,
                );
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(
                color: row.hasError && row.product == null
                    ? AppColors.red
                    : AppColors.divider,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              row.product != null
                  ? '${row.product!.name}  Rs.${row.product!.price.toStringAsFixed(0)}'
                  : 'Tap to select…',
              style: TextStyle(
                fontSize: 11,
                color: row.product != null ? null : AppColors.textHint,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  Widget _shiftCell(_Row row) {
    return SizedBox(
      width: _wShift,
      child: Center(
        child: GestureDetector(
          onTap: () => setState(
            () => row.shift = row.shift == 'morning' ? 'night' : 'morning',
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: row.shift == 'morning'
                  ? Colors.orange.withValues(alpha: 0.15)
                  : Colors.indigo.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              row.shift == 'morning' ? '☀️ M' : '🌙 N',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateCell(_Row row) {
    return SizedBox(
      width: _wDate,
      child: InkWell(
        onTap: () async {
          final d = await _pickDate(row.manufacture);
          if (d != null) {
            setState(() {
              row.manufacture = d;
              if (row.product != null) {
                row.expiry = AppDateUtils.expiryDate(
                  d,
                  row.product!.expiryDays,
                );
              }
            });
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            DateFormat('dd/MM/yy').format(row.manufacture),
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ),
    );
  }

  Widget _expiryCell(_Row row) {
    final expiry =
        row.expiry ??
        (row.product != null
            ? AppDateUtils.expiryDate(row.manufacture, row.product!.expiryDays)
            : null);
    return SizedBox(
      width: _wExpiry,
      child: InkWell(
        onTap: () async {
          final d = await _pickDate(
            expiry ?? row.manufacture.add(const Duration(days: 90)),
          );
          if (d != null) setState(() => row.expiry = d);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            expiry != null ? DateFormat('dd/MM/yy').format(expiry) : '—',
            style: TextStyle(
              fontSize: 11,
              color: expiry != null ? null : AppColors.textHint,
            ),
          ),
        ),
      ),
    );
  }

  Widget _grossWeightCell(_Row row) {
    final g = double.tryParse(row.grossWt.text.trim());
    final st = (g != null && g > 0 && row.product != null)
        ? StatusUtils.weightStatus(
            g,
            row.product!.weightGrams,
            toleranceGreen: row.product!.weightToleranceGreen,
            toleranceYellow: row.product!.weightToleranceYellow,
          )
        : null;
    final statusColor = st != null ? AppColors.statusColor(st) : null;
    final border = statusColor != null
        ? OutlineInputBorder(
            borderSide: BorderSide(color: statusColor, width: 1.8),
          )
        : const OutlineInputBorder();

    return SizedBox(
      width: _wWeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: TextField(
          controller: row.grossWt,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [_numFmt],
          style: TextStyle(
            fontSize: 12,
            color: statusColor,
            fontWeight: statusColor != null ? FontWeight.w600 : null,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 8,
              horizontal: 6,
            ),
            border: border,
            enabledBorder: border,
            focusedBorder: statusColor != null
                ? border.copyWith(
                    borderSide: BorderSide(color: statusColor, width: 2.2),
                  )
                : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
      ),
    );
  }

  static final _numFmt = FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'));

  // Updated to accept a dynamic status color
  Widget _numCell(
    TextEditingController ctrl,
    double width, {
    Color? statusColor,
  }) {
    final border = statusColor != null
        ? OutlineInputBorder(
            borderSide: BorderSide(color: statusColor, width: 1.8),
          )
        : const OutlineInputBorder();

    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [_numFmt],
          style: TextStyle(
            fontSize: 12,
            color: statusColor,
            fontWeight: statusColor != null ? FontWeight.w600 : null,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 8,
              horizontal: 6,
            ),
            border: border,
            enabledBorder: border,
            focusedBorder: statusColor != null
                ? border.copyWith(
                    borderSide: BorderSide(color: statusColor, width: 2.2),
                  )
                : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
      ),
    );
  }

  Widget _statusCell({
    required String label,
    required Color color,
    required VoidCallback onTap,
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: Center(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _customCell(CustomColumn col, _Row row) {
    final ctrl = row.customCtrls[col.id];
    if (ctrl == null) return SizedBox(width: col.width);

    // If the row failed validation, and THIS specific column is required but empty, flag it!
    final isError = row.hasError && col.isRequired && ctrl.text.trim().isEmpty;
    final borderColor = isError ? AppColors.red : AppColors.divider;

    if (col.type == CustomColumnType.options) {
      final val = ctrl.text;
      return SizedBox(
        width: col.width,
        child: Center(
          child: InkWell(
            onTap: col.options.isEmpty ? null : () => _pickOption(col, row),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                // Apply Red border if error
                border: Border.all(color: borderColor, width: isError ? 1.5 : 1.0),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                val.isEmpty ? (col.options.isEmpty ? '—' : 'Select…') : val,
                style: TextStyle(
                  fontSize: 11,
                  color: val.isEmpty ? AppColors.textHint : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      );
    }

    final border = OutlineInputBorder(
        borderSide: BorderSide(
          // Apply Red border if error
            color: isError ? AppColors.red : Colors.grey.shade400,
            width: isError ? 1.5 : 1.0
        )
    );

    return SizedBox(
      width: col.width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: TextField(
          controller: ctrl,
          keyboardType: col.type == CustomColumnType.number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          inputFormatters: col.type == CustomColumnType.number ? [_numFmt] : [],
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(borderSide: border.borderSide.copyWith(width: 2.0)),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ),
    );
  }
  String _printLabel(_Row r) {
    if (r.printStatus == 'okay') return 'OK';
    return r.printStatus[0].toUpperCase() + r.printStatus.substring(1);
  }

  Color _printColor(_Row r) {
    switch (r.printStatus) {
      case 'okay':
        return AppColors.green;
      case 'minor':
        return AppColors.yellow;
      default:
        return AppColors.red;
    }
  }

  String _leakLabel(_Row r) {
    if (r.leakageStatus == 'green') return 'OK';
    return r.leakageStatus[0].toUpperCase() + r.leakageStatus.substring(1);
  }

  Color _leakColor(_Row r) {
    switch (r.leakageStatus) {
      case 'green':
        return AppColors.green;
      case 'minor':
        return AppColors.yellow;
      default:
        return AppColors.red;
    }
  }

  Widget _buildFooter(Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Row'),
            onPressed: _addRow,
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.content_copy, size: 16),
            label: const Text('Duplicate Last'),
            onPressed: _rows.isEmpty
                ? null
                : () {
                    final last = _rows.last;
                    final dup =
                        _Row(shift: last.shift, manufacture: last.manufacture)
                          ..machine = last.machine
                          ..product = last.product
                          ..expiry = last.expiry
                          ..grossWt.text = last.grossWt.text
                          ..p1.text = last.p1.text
                          ..p2.text = last.p2.text
                          ..p3.text = last.p3.text
                          ..p4.text = last.p4.text
                          ..moisture.text = last.moisture.text
                          ..printStatus = last.printStatus
                          ..printColor = last.printColor
                          ..printRemarks = last.printRemarks
                          ..leakageStatus = last.leakageStatus
                          ..leakageRemarks = last.leakageRemarks;
                    for (final col in _customColumns) {
                      dup.customCtrls[col.id] = TextEditingController(
                        text: last.customCtrls[col.id]?.text ?? '',
                      );
                    }
                    setState(() => _rows.add(dup));
                  },
          ),
          const Text(
            'Tap Print/Leakage cells to add details',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
