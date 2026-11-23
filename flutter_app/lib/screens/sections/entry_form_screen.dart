import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/sections.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/status_utils.dart';
import '../../models/machine_model.dart';
import '../../models/packing_entry_model.dart';
import '../../models/product_model.dart';
import '../../models/custom_column_model.dart'; // NEW: Imported Custom Columns
import '../../providers/auth_provider.dart';
import '../../providers/entries_provider.dart';
import '../../providers/machines_provider.dart';
import '../../providers/products_provider.dart';

// Modular UI imports
import 'excel_entry/widgets/product_picker_dialog.dart';
import 'widgets/entry_form_components.dart';

class EntryFormScreen extends StatefulWidget {
  final SectionInfo section;
  final PackingEntryModel? existing;

  const EntryFormScreen({super.key, required this.section, this.existing});

  @override
  State<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends State<EntryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  bool _isDirty = false;
  bool _loadingCols = true; // NEW: Track column loading state

  MachineModel? _selectedMachine;
  ProductModel? _selectedProduct;
  String _shift = ShiftHelper.detectShift();
  DateTime _manufacture = DateTime.now();
  DateTime? _expiry;

  final _pouch1 = TextEditingController();
  final _pouch2 = TextEditingController();
  final _pouch3 = TextEditingController();
  final _pouch4 = TextEditingController();
  final _moistureCtrl = TextEditingController();
  String _printingStatus = 'okay';
  String? _printingColor;
  final _printingRemarksCtrl = TextEditingController();
  String _leakageStatus = 'green';
  final _leakageRemarksCtrl = TextEditingController();

  // NEW: State for custom columns
  List<CustomColumn> _customColumns = [];
  final Map<String, TextEditingController> _customCtrls = {};

  final _fnPouch1 = FocusNode();
  final _fnPouch2 = FocusNode();
  final _fnPouch3 = FocusNode();
  final _fnPouch4 = FocusNode();
  final _fnMoisture = FocusNode();

  bool get isEdit => widget.existing != null;
  bool get _hasMoisture => widget.section.id != 'wafer' && widget.section.id != 'chocolate';

  @override
  void initState() {
    super.initState();
    _loadCustomColumns(); // Fetch dynamic columns on init
    if (isEdit) _prefill();
  }

  // NEW: Fetch columns and prep controllers
  Future<void> _loadCustomColumns() async {
    final cols = await CustomColumnsService.load();
    if (!mounted) return;
    setState(() {
      _customColumns = cols;
      for (final col in cols) {
        final val = widget.existing?.customFields?[col.id] ?? '';
        _customCtrls[col.id] = TextEditingController(text: val);
      }
      _loadingCols = false;
    });
  }

  void _prefill() {
    final e = widget.existing!;
    _shift = e.shift;
    _manufacture = e.dateCodingManufacture;
    _expiry = e.dateCodingExpiry;
    _pouch1.text = e.pouch1Weight?.toString() ?? '';
    _pouch2.text = e.pouch2Weight?.toString() ?? '';
    _pouch3.text = e.pouch3Weight?.toString() ?? '';
    _pouch4.text = e.pouch4Weight?.toString() ?? '';
    _moistureCtrl.text = e.moistureActual?.toString() ?? '';
    _printingStatus = e.printingStatus;
    _printingColor = e.printingColor;
    _printingRemarksCtrl.text = e.printingRemarks ?? '';
    _leakageStatus = e.leakageStatus;
    _leakageRemarksCtrl.text = e.leakageRemarks ?? '';

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final machines = context.read<MachinesProvider>().forSection(widget.section.id);
      final products = context.read<ProductsProvider>().forSection(widget.section.id);
      setState(() {
        _selectedMachine = machines.firstWhere((m) => m.id == e.machineId, orElse: () => machines.first);
        _selectedProduct = products.firstWhere((p) => p.id == e.productId, orElse: () => products.first);
        if (_moistureCtrl.text.isEmpty && _selectedProduct != null) {
          _moistureCtrl.text = _selectedProduct!.moistureMax.toString();
        }
      });
    });
  }

  void _onProductSelected(ProductModel? p) {
    setState(() {
      _isDirty = true;
      _selectedProduct = p;
      if (p != null) {
        _expiry = AppDateUtils.expiryDate(_manufacture, p.expiryDays);
        if (_moistureCtrl.text.isEmpty || double.tryParse(_moistureCtrl.text) == null) {
          _moistureCtrl.text = p.moistureMax.toString();
        }
      }
    });
  }

  void _onManufactureChanged(DateTime dt) {
    setState(() {
      _isDirty = true;
      _manufacture = dt;
      if (_selectedProduct != null) {
        _expiry = AppDateUtils.expiryDate(dt, _selectedProduct!.expiryDays);
      }
    });
  }

  Future<void> _pickManufacture() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _manufacture,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) _onManufactureChanged(picked);
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _expiry = picked);
  }

  double? _tryParse(TextEditingController c) => double.tryParse(c.text);

  Future<void> _save() async {
    final auth = context.read<AuthProvider>();
    if (auth.user?.isViewer == true) return;
    if (!_formKey.currentState!.validate()) return;

    if (_selectedMachine == null) return _showError('Select a machine');
    if (_selectedProduct == null) return _showError('Select a product');
    if (_expiry == null) return _showError('Set expiry date');

    setState(() => _saving = true);
    try {
      final ep = context.read<EntriesProvider>();

      final p1 = _tryParse(_pouch1);
      final p2 = _tryParse(_pouch2);
      final p3 = _tryParse(_pouch3);
      final p4 = _tryParse(_pouch4);
      final moisture = _tryParse(_moistureCtrl);

      final wStatus = StatusUtils.weightStatusOfPouches(
        [p1, p2, p3, p4],
        _selectedProduct!.weightGrams,
        toleranceGreen: _selectedProduct!.weightToleranceGreen,
        toleranceYellow: _selectedProduct!.weightToleranceYellow,
      );
      final mStatus = moisture != null
          ? StatusUtils.moistureStatus(moisture, _selectedProduct!.moistureMax, _selectedProduct!.moistureYellowMax)
          : 'na';

      // NEW: Compile custom field values
      final customFieldsData = <String, String>{};
      for (final entry in _customCtrls.entries) {
        if (entry.value.text.trim().isNotEmpty) {
          customFieldsData[entry.key] = entry.value.text.trim();
        }
      }

      final now = DateTime.now();
      final entry = PackingEntryModel(
        id: widget.existing?.id ?? '',
        machineId: _selectedMachine!.id,
        machineNumber: _selectedMachine!.number,
        section: widget.section.id,
        productId: _selectedProduct!.id,
        productName: _selectedProduct!.displayName,
        price: _selectedProduct!.price,
        shift: _shift,
        operatorId: auth.user?.id ?? '',
        operatorName: auth.user?.username ?? '',
        dateCodingManufacture: _manufacture,
        dateCodingExpiry: _expiry!,
        grossWeight: _selectedProduct!.weightGrams,
        pouch1Weight: p1,
        pouch2Weight: p2,
        pouch3Weight: p3,
        pouch4Weight: p4,
        moistureIdeal: _selectedProduct!.moistureMax,
        moistureActual: moisture,
        weightStatus: wStatus,
        printingStatus: _printingStatus,
        printingColor: _printingStatus == 'not_okay' ? _printingColor : null,
        printingRemarks: _printingStatus == 'not_okay' ? _printingRemarksCtrl.text : null,
        leakageStatus: _leakageStatus,
        leakageRemarks: _leakageStatus != 'green' ? _leakageRemarksCtrl.text.trim().isEmpty ? null : _leakageRemarksCtrl.text.trim() : null,
        moistureStatus: mStatus,
        isSynced: false,
        createdAt: widget.existing?.createdAt ?? now,
        updatedAt: now,
        customFields: customFieldsData.isEmpty ? null : customFieldsData, // Append custom fields
      );

      final err = isEdit ? await ep.updateEntry(entry) : await ep.addEntry(entry);

      if (mounted) {
        if (err == null) {
          Navigator.pop(context);
        } else {
          _showError(err);
        }
      }
    } finally {
      if (context.mounted) setState(() => _saving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.red),
    );
  }

  @override
  void dispose() {
    _pouch1.dispose(); _pouch2.dispose(); _pouch3.dispose(); _pouch4.dispose();
    _moistureCtrl.dispose(); _printingRemarksCtrl.dispose(); _leakageRemarksCtrl.dispose();
    _fnPouch1.dispose(); _fnPouch2.dispose(); _fnPouch3.dispose(); _fnPouch4.dispose(); _fnMoisture.dispose();

    // NEW: Clean up custom controllers
    for (final ctrl in _customCtrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pp = context.read<ProductsProvider>();
    if (pp.allProducts.isEmpty) pp.loadAll();
  }

  Future<void> _openProductPicker(BuildContext context) async {
    final allProducts = context.read<ProductsProvider>().allProducts;
    final picked = await showDialog<ProductModel>(
      context: context,
      builder: (ctx) => ProductPickerDialog(
        allProducts: allProducts,
        currentSectionId: widget.section.id,
        selected: _selectedProduct,
      ),
    );
    if (picked != null) _onProductSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.sectionColor(widget.section.id);
    final machines = context.watch<MachinesProvider>().forSection(widget.section.id);
    final isWide = MediaQuery.of(context).size.width > 700;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!_isDirty) { Navigator.of(context).pop(); return; }
        final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Discard changes?'),
            content: const Text('You have unsaved changes. Are you sure you want to leave?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: AppColors.red),
                child: const Text('Discard'),
              ),
            ],
          ),
        );
        if (discard == true && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: color,
          title: Text(isEdit ? 'Edit Entry' : 'New Entry — ${widget.section.name}'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('SAVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // 1. Machine & Product Section
                    FormSectionCard(title: 'Machine & Product', children: [
                      FormDropdownField<MachineModel>(
                        label: 'Machine Number',
                        value: _selectedMachine,
                        items: machines,
                        display: (m) => 'Machine ${m.number}',
                        onChanged: (m) => setState(() { _isDirty = true; _selectedMachine = m; }),
                        validator: (v) => v == null ? 'Select machine' : null,
                      ),
                      const SizedBox(height: 14),
                      FormField<ProductModel>(
                        validator: (_) => _selectedProduct == null ? 'Select a product' : null,
                        builder: (state) => GestureDetector(
                          onTap: () => _openProductPicker(context),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Product',
                              suffixIcon: const Icon(Icons.search),
                              errorText: state.errorText,
                            ),
                            child: Text(
                              _selectedProduct != null ? _selectedProduct!.displayName : 'Tap to search product…',
                              style: TextStyle(fontSize: 16, color: _selectedProduct != null ? null : Theme.of(context).hintColor),
                            ),
                          ),
                        ),
                      ),
                      if (_selectedProduct != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
                          child: Row(
                            children: [
                              Expanded(child: FormInfoItem(label: 'Gross Weight', value: '${_selectedProduct!.weightGrams}g')),
                              Expanded(child: FormInfoItem(label: 'Moisture Max', value: '${_selectedProduct!.moistureMax}')),
                              Expanded(child: FormInfoItem(label: 'Expiry', value: '${_selectedProduct!.expiryDays} Months')),
                            ],
                          ),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 14),

                    // 2. Shift & Date Coding Section
                    FormSectionCard(title: 'Shift & Date Coding', children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          const Text('Shift:', style: TextStyle(fontWeight: FontWeight.w500)),
                          ChoiceChip(
                            label: const Text('☀️ Morning'),
                            selected: _shift == 'morning',
                            onSelected: (_) => setState(() { _isDirty = true; _shift = 'morning'; }),
                          ),
                          ChoiceChip(
                            label: const Text('🌙 Night'),
                            selected: _shift == 'night',
                            onSelected: (_) => setState(() { _isDirty = true; _shift = 'night'; }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(child: FormDateField(label: 'Manufacture Date', date: _manufacture, onTap: _pickManufacture)),
                          const SizedBox(width: 12),
                          Expanded(child: FormDateField(label: 'Expiry Date', date: _expiry, onTap: _pickExpiry, hint: 'Auto-calculated')),
                        ],
                      ),
                    ]),
                    const SizedBox(height: 14),

// 3. Pouch Weights Section
                    FormSectionCard(title: 'Pouch Weights (4 Samples)', children: [
                      Text(
                        _selectedProduct != null
                            ? 'Target: ${_selectedProduct!.weightGrams}g · ±${_selectedProduct!.weightToleranceGreen}g = OK · ±${_selectedProduct!.weightToleranceYellow}g = Warning · >±${_selectedProduct!.weightToleranceYellow}g = Alert'
                            : 'Weigh 4 random pouches',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      isWide
                          ? Row(children: [
                        Expanded(child: FormWeightField(controller: _pouch1, label: 'Pouch 1', focusNode: _fnPouch1, nextFocus: _fnPouch2, statusColor: _getWeightColor(_pouch1.text), onChanged: (_) => setState(() => _isDirty = true))),
                        const SizedBox(width: 10),
                        Expanded(child: FormWeightField(controller: _pouch2, label: 'Pouch 2', focusNode: _fnPouch2, nextFocus: _fnPouch3, statusColor: _getWeightColor(_pouch2.text), onChanged: (_) => setState(() => _isDirty = true))),
                        const SizedBox(width: 10),
                        Expanded(child: FormWeightField(controller: _pouch3, label: 'Pouch 3', focusNode: _fnPouch3, nextFocus: _fnPouch4, statusColor: _getWeightColor(_pouch3.text), onChanged: (_) => setState(() => _isDirty = true))),
                        const SizedBox(width: 10),
                        Expanded(child: FormWeightField(controller: _pouch4, label: 'Pouch 4', focusNode: _fnPouch4, nextFocus: _hasMoisture ? _fnMoisture : null, statusColor: _getWeightColor(_pouch4.text), onChanged: (_) => setState(() => _isDirty = true))),
                      ])
                          : Column(children: [
                        Row(children: [
                          Expanded(child: FormWeightField(controller: _pouch1, label: 'Pouch 1', focusNode: _fnPouch1, nextFocus: _fnPouch2, statusColor: _getWeightColor(_pouch1.text), onChanged: (_) => setState(() => _isDirty = true))),
                          const SizedBox(width: 10),
                          Expanded(child: FormWeightField(controller: _pouch2, label: 'Pouch 2', focusNode: _fnPouch2, nextFocus: _fnPouch3, statusColor: _getWeightColor(_pouch2.text), onChanged: (_) => setState(() => _isDirty = true))),
                        ]),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: FormWeightField(controller: _pouch3, label: 'Pouch 3', focusNode: _fnPouch3, nextFocus: _fnPouch4, statusColor: _getWeightColor(_pouch3.text), onChanged: (_) => setState(() => _isDirty = true))),
                          const SizedBox(width: 10),
                          Expanded(child: FormWeightField(controller: _pouch4, label: 'Pouch 4', focusNode: _fnPouch4, nextFocus: _hasMoisture ? _fnMoisture : null, statusColor: _getWeightColor(_pouch4.text), onChanged: (_) => setState(() => _isDirty = true))),
                        ]),
                      ]),
                      const SizedBox(height: 10),
                      _buildWeightStatus(),
                    ]),
                    const SizedBox(height: 14),

                    // 4. Moisture Section
                    if (_hasMoisture)
                      FormSectionCard(title: 'Moisture', children: [
                        Text(_moistureRule(), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        const SizedBox(height: 12),
                        FormWeightField(
                            controller: _moistureCtrl,
                            label: 'Moisture Value',
                            focusNode: _fnMoisture,
                            statusColor: _getMoistureColor(_moistureCtrl.text),
                            onChanged: (_) => setState(() => _isDirty = true)
                        ),
                        const SizedBox(height: 10),
                        _buildMoistureStatus(),
                      ]),
                    if (_hasMoisture) const SizedBox(height: 14),

                    // 5. Printing Section
                    FormSectionCard(title: 'Printing', children: [
                      Row(
                        children: [
                          Expanded(child: FormStatusChoice(label: '✅ Okay', selected: _printingStatus == 'okay', color: AppColors.green, onTap: () => setState(() { _isDirty = true; _printingStatus = 'okay'; _printingColor = null; }))),
                          const SizedBox(width: 10),
                          Expanded(child: FormStatusChoice(label: '❌ Not Okay', selected: _printingStatus == 'not_okay', color: AppColors.red, onTap: () => setState(() { _isDirty = true; _printingStatus = 'not_okay'; }))),
                        ],
                      ),
                      if (_printingStatus == 'not_okay') ...[
                        const SizedBox(height: 12),
                        const Text('Defect Level:', style: TextStyle(fontWeight: FontWeight.w500)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: FormStatusChoice(label: '🟡 Warning', selected: _printingColor == 'yellow', color: AppColors.yellow, onTap: () => setState(() { _isDirty = true; _printingColor = 'yellow'; }))),
                            const SizedBox(width: 10),
                            Expanded(child: FormStatusChoice(label: '🔴 Blocked', selected: _printingColor == 'red', color: AppColors.red, onTap: () => setState(() { _isDirty = true; _printingColor = 'red'; }))),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _printingRemarksCtrl,
                          decoration: const InputDecoration(labelText: 'Remarks (required)'),
                          validator: (v) => _printingStatus == 'not_okay' && (v == null || v.isEmpty) ? 'Enter remarks' : null,
                        ),
                      ],
                    ]),
                    const SizedBox(height: 14),

                    // 6. Leakage Section
                    FormSectionCard(title: 'Leakage', children: [
                      Row(
                        children: [
                          Expanded(child: FormStatusChoice(label: '🟢 None', selected: _leakageStatus == 'green', color: AppColors.green, onTap: () => setState(() { _isDirty = true; _leakageStatus = 'green'; _leakageRemarksCtrl.clear(); }))),
                          const SizedBox(width: 8),
                          Expanded(child: FormStatusChoice(label: '🟡 Minor', selected: _leakageStatus == 'yellow', color: AppColors.yellow, onTap: () => setState(() { _isDirty = true; _leakageStatus = 'yellow'; }))),
                          const SizedBox(width: 8),
                          Expanded(child: FormStatusChoice(label: '🔴 Major', selected: _leakageStatus == 'red', color: AppColors.red, onTap: () => setState(() { _isDirty = true; _leakageStatus = 'red'; }))),
                        ],
                      ),
                      if (_leakageStatus != 'green') ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _leakageRemarksCtrl,
                          decoration: const InputDecoration(labelText: 'Remarks (optional)'),
                          onChanged: (_) => _isDirty = true,
                        ),
                      ],
                    ]),
                    const SizedBox(height: 14),

// 7. Custom Columns Section
                    if (_loadingCols)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_customColumns.isNotEmpty) ...[
                      FormSectionCard(title: 'Additional Information', children: [
                        for (final col in _customColumns)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: col.type == CustomColumnType.options
                                ? FormDropdownField<String>(
                              // Add an asterisk if compulsory
                              label: col.heading + (col.isRequired ? ' *' : ''),
                              value: _customCtrls[col.id]!.text.isEmpty ? null : _customCtrls[col.id]!.text,
                              items: col.options,
                              display: (s) => s,
                              // BLOCKS SAVE IF COMPULSORY AND EMPTY:
                              validator: col.isRequired ? (v) => v == null || v.isEmpty ? 'Required' : null : null,
                              onChanged: (v) => setState(() {
                                _isDirty = true;
                                _customCtrls[col.id]!.text = v ?? '';
                              }),
                            )
                                : TextFormField(
                              controller: _customCtrls[col.id],
                              keyboardType: col.type == CustomColumnType.number
                                  ? const TextInputType.numberWithOptions(decimal: true)
                                  : TextInputType.text,
                              decoration: InputDecoration(
                                // Add an asterisk if compulsory
                                labelText: col.heading + (col.isRequired ? ' *' : ''),
                                isDense: true,
                                border: const OutlineInputBorder(),
                              ),
                              // BLOCKS SAVE IF COMPULSORY AND EMPTY:
                              validator: col.isRequired ? (v) => v!.trim().isEmpty ? 'Required' : null : null,
                              onChanged: (_) => setState(() => _isDirty = true),
                            ),
                          ),
                      ]),
                      const SizedBox(height: 14),
                    ],
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(backgroundColor: color),
                        child: _saving
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text(isEdit ? 'Update Entry' : 'Save Entry', style: const TextStyle(fontSize: 16)),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Local helper logic for badges
  Widget _buildWeightStatus() {
    final p1 = _tryParse(_pouch1);
    final p2 = _tryParse(_pouch2);
    final p3 = _tryParse(_pouch3);
    final p4 = _tryParse(_pouch4);
    final weights = [p1, p2, p3, p4].where((w) => w != null && w > 0).map((w) => w!).toList();
    if (weights.isEmpty || _selectedProduct == null) return const SizedBox.shrink();
    final avg = weights.reduce((a, b) => a + b) / weights.length;
    final status = StatusUtils.weightStatusOfPouches(
      [p1, p2, p3, p4], _selectedProduct!.weightGrams,
      toleranceGreen: _selectedProduct!.weightToleranceGreen,
      toleranceYellow: _selectedProduct!.weightToleranceYellow,
    );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Text('Avg: ${avg.toStringAsFixed(2)}g  Target: ${_selectedProduct!.weightGrams}g  →'),
        _statusBadge(status),
      ],
    );
  }

  Widget _buildMoistureStatus() {
    final moisture = _tryParse(_moistureCtrl);
    if (moisture == null || _selectedProduct == null) return const SizedBox.shrink();
    final status = StatusUtils.moistureStatus(moisture, _selectedProduct!.moistureMax, _selectedProduct!.moistureYellowMax);
    if (status == 'na') return const SizedBox.shrink();
    return Row(children: [Text('Moisture $moisture → '), _statusBadge(status)]);
  }

  Widget _statusBadge(String status) {
    final color = AppColors.statusColor(status);
    final labels = {'green': 'OK', 'yellow': 'Warning', 'red': 'Alert'};
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(labels[status] ?? status, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
  String _moistureRule() {
    if (_selectedProduct == null) {
      return 'Select a product to view moisture limits.';
    }

    final green = _selectedProduct!.moistureMax;
    final yellow = _selectedProduct!.moistureYellowMax;

    return 'Target: ≤$green% = OK · $green–$yellow% = Warning · >$yellow% = Alert';
  }
  Color? _getWeightColor(String text) {
    if (_selectedProduct == null) return null;
    final val = double.tryParse(text);
    if (val == null || val <= 0) return null;

    final status = StatusUtils.weightStatus(
      val,
      _selectedProduct!.weightGrams,
      toleranceGreen: _selectedProduct!.weightToleranceGreen,
      toleranceYellow: _selectedProduct!.weightToleranceYellow,
    );
    return AppColors.statusColor(status);
  }

  Color? _getMoistureColor(String text) {
    if (_selectedProduct == null) return null;
    final val = double.tryParse(text);
    if (val == null || val <= 0) return null;

    final status = StatusUtils.moistureStatus(
      val,
      _selectedProduct!.moistureMax,
      _selectedProduct!.moistureYellowMax,
    );
    if (status == 'na') return null;
    return AppColors.statusColor(status);
  }
}