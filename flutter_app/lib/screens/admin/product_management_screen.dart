import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/sections.dart';
import '../../models/product_model.dart';
import '../../providers/products_provider.dart';

class ProductManagementScreen extends StatefulWidget {
  const ProductManagementScreen({super.key});

  @override
  State<ProductManagementScreen> createState() =>
      _ProductManagementScreenState();
}

class _ProductManagementScreenState extends State<ProductManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: Sections.all.length, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProductsProvider>().loadAll();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Products'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: Sections.all.map((s) => Tab(text: s.name)).toList(),
        ),
      ),
      body: Column(
        children: [
          // ── Search Bar ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search products by name...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              onChanged: (val) {
                setState(() => _searchQuery = val.toLowerCase());
              },
            ),
          ),
          // ── Tab Views ───────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: Sections.all
                  .map(
                    (s) => _ProductSectionList(
                      section: s,
                      searchQuery: _searchQuery,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
        onPressed: () => _showProductForm(context, Sections.all[_tabs.index]),
      ),
    );
  }

  void _showProductForm(
    BuildContext context,
    SectionInfo section, [
    ProductModel? existing,
  ]) {
    showDialog(
      context: context,
      builder: (ctx) =>
          _ProductFormDialog(section: section, existing: existing),
    );
  }
}

// ── Section List (Stateful to manage default expiry and tolerances) ───────

class _ProductSectionList extends StatefulWidget {
  final SectionInfo section;
  final String searchQuery;

  const _ProductSectionList({required this.section, required this.searchQuery});

  @override
  State<_ProductSectionList> createState() => _ProductSectionListState();
}

class _ProductSectionListState extends State<_ProductSectionList> {
  int _defaultExpiry = 3;
  double _defWtGreen = 2.0;
  double _defWtYellow = 4.0;
  double _defMoistMax = 1.8;
  double _defMoistYellow = 2.0;

  @override
  void initState() {
    super.initState();
    _loadSectionDefaults();
  }

  Future<void> _loadSectionDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _defaultExpiry =
            prefs.getInt('default_expiry_${widget.section.id}') ?? 3;
        _defWtGreen =
            prefs.getDouble('def_wt_green_${widget.section.id}') ?? 2.0;
        _defWtYellow =
            prefs.getDouble('def_wt_yellow_${widget.section.id}') ?? 4.0;
        _defMoistMax =
            prefs.getDouble('def_moist_max_${widget.section.id}') ?? 1.8;
        _defMoistYellow =
            prefs.getDouble('def_moist_yellow_${widget.section.id}') ?? 2.0;
      });
    }
  }

  Future<void> _changeSectionDefaults(
    List<ProductModel> allSectionProducts,
  ) async {
    final expCtrl = TextEditingController(text: _defaultExpiry.toString());
    final wtGreenCtrl = TextEditingController(text: _defWtGreen.toString());
    final wtYellowCtrl = TextEditingController(text: _defWtYellow.toString());
    final moistMaxCtrl = TextEditingController(text: _defMoistMax.toString());
    final moistYellowCtrl = TextEditingController(
      text: _defMoistYellow.toString(),
    );

    bool applyToExisting = false;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Section Defaults: ${widget.section.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Expiry (Months)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: expCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 12),
                const Text(
                  'Weight Tolerances (±g)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: wtGreenCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Green (OK)',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: wtYellowCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Yellow (Warn)',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),

                if (widget.section.id != 'wafer' &&
                    widget.section.id != 'chocolate') ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Moisture Limits (%)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: moistMaxCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Green Max',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: moistYellowCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Yellow Max',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 16),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Update all existing products',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Apply these new bounds to every product currently in this tab.',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: applyToExisting,
                  onChanged: (v) =>
                      setLocal(() => applyToExisting = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx, {
                  'exp': int.tryParse(expCtrl.text) ?? _defaultExpiry,
                  'wtG': double.tryParse(wtGreenCtrl.text) ?? _defWtGreen,
                  'wtY': double.tryParse(wtYellowCtrl.text) ?? _defWtYellow,
                  'mG': double.tryParse(moistMaxCtrl.text) ?? _defMoistMax,
                  'mY':
                      double.tryParse(moistYellowCtrl.text) ?? _defMoistYellow,
                  'apply': applyToExisting,
                });
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result != null && mounted) {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setInt('default_expiry_${widget.section.id}', result['exp']);
      await prefs.setDouble('def_wt_green_${widget.section.id}', result['wtG']);
      await prefs.setDouble(
        'def_wt_yellow_${widget.section.id}',
        result['wtY'],
      );
      await prefs.setDouble('def_moist_max_${widget.section.id}', result['mG']);
      await prefs.setDouble(
        'def_moist_yellow_${widget.section.id}',
        result['mY'],
      );

      if (!mounted) return;
      setState(() {
        _defaultExpiry = result['exp'];
        _defWtGreen = result['wtG'];
        _defWtYellow = result['wtY'];
        _defMoistMax = result['mG'];
        _defMoistYellow = result['mY'];
      });

      if (result['apply'] == true) {
        final messenger = ScaffoldMessenger.of(context);
        final pp = context.read<ProductsProvider>();

        messenger.showSnackBar(
          const SnackBar(
            content: Text('Updating all products in this section...'),
          ),
        );

        for (final p in allSectionProducts) {
          final updatedP = p.copyWith(
            expiryDays: result['exp'],
            weightToleranceGreen: result['wtG'],
            weightToleranceYellow: result['wtY'],
            moistureMax: result['mG'],
            moistureYellowMax: result['mY'],
          );
          await pp.save(updatedP);
          if (!mounted) return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pp = context.watch<ProductsProvider>();
    final allSectionProducts = pp.forSection(widget.section.id);

    final filteredProducts = allSectionProducts
        .where((p) => p.name.toLowerCase().contains(widget.searchQuery))
        .toList();

    if (pp.loading) return const Center(child: CircularProgressIndicator());

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: filteredProducts.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return Card(
            color: AppColors.primary.withValues(alpha: 0.1),
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: ListTile(
              leading: const Icon(
                Icons.settings_suggest,
                color: AppColors.primary,
              ),
              title: const Text(
                'Section Defaults',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'Exp: $_defaultExpiry mos · Wt: ±$_defWtGreen/$_defWtYellow · Moist: $_defMoistMax/$_defMoistYellow',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: TextButton(
                onPressed: () => _changeSectionDefaults(allSectionProducts),
                child: const Text('Configure'),
              ),
            ),
          );
        }

        final p = filteredProducts[i - 1];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: p.imagePath != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      p.imagePath!,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(Icons.inventory_2),
                    ),
                  )
                : const CircleAvatar(child: Icon(Icons.inventory_2)),
            title: Text(
              p.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rs.${p.price.toStringAsFixed(0)} · Target: ${p.weightGrams}g · Exp: ${p.expiryDays} months',
                ),
                Text(
                  'Weight bands: ±${p.weightToleranceGreen}g green / ±${p.weightToleranceYellow}g yellow'
                  '${p.moistureMax > 0 ? '  ·  Moisture: ≤${p.moistureMax} / ≤${p.moistureYellowMax}' : '  ·  Moisture: N/A'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit',
                  onPressed: () => showDialog(
                    context: ctx,
                    builder: (_) => _ProductFormDialog(
                      section: widget.section,
                      existing: p,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.red),
                  tooltip: 'Delete',
                  onPressed: () => _confirmDelete(ctx, p),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, ProductModel p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Product?'),
        content: Text('Delete "${p.name}"? This will hide it from operators.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<ProductsProvider>().delete(p);
    }
  }
}

// ── Product Form Dialog ───────────────────────────────────────────────────

class _ProductFormDialog extends StatefulWidget {
  final SectionInfo section;
  final ProductModel? existing;

  const _ProductFormDialog({required this.section, this.existing});

  @override
  State<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<_ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final _nameCtrl = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final _priceCtrl = TextEditingController(
    text: widget.existing?.price.toStringAsFixed(0) ?? '',
  );
  late final _weightCtrl = TextEditingController(
    text: widget.existing?.weightGrams.toStringAsFixed(1) ?? '',
  );

  // Set to empty initially; populated by existing data or by defaults
  late final _tolGreenCtrl = TextEditingController(
    text: widget.existing?.weightToleranceGreen.toStringAsFixed(1) ?? '',
  );
  late final _tolYellowCtrl = TextEditingController(
    text: widget.existing?.weightToleranceYellow.toStringAsFixed(1) ?? '',
  );
  late final _moistureMaxCtrl = TextEditingController(
    text: widget.existing?.moistureMax.toStringAsFixed(1) ?? '',
  );
  late final _moistureYellowCtrl = TextEditingController(
    text: widget.existing?.moistureYellowMax.toStringAsFixed(1) ?? '',
  );
  late final _expiryCtrl = TextEditingController(
    text: widget.existing?.expiryDays.toString() ?? '',
  );

  bool _saving = false;

  bool get _isNaMoisture =>
      widget.section.id == 'wafer' || widget.section.id == 'chocolate';

  @override
  void initState() {
    super.initState();
    if (widget.existing == null) {
      _loadDefaults();
    }
  }

  Future<void> _loadDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    final defExp = prefs.getInt('default_expiry_${widget.section.id}') ?? 3;
    final defWtG = prefs.getDouble('def_wt_green_${widget.section.id}') ?? 2.0;
    final defWtY = prefs.getDouble('def_wt_yellow_${widget.section.id}') ?? 4.0;
    final defMoistG =
        prefs.getDouble('def_moist_max_${widget.section.id}') ?? 1.8;
    final defMoistY =
        prefs.getDouble('def_moist_yellow_${widget.section.id}') ?? 2.0;

    if (mounted && widget.existing == null) {
      setState(() {
        _expiryCtrl.text = defExp.toString();
        _tolGreenCtrl.text = defWtG.toStringAsFixed(1);
        _tolYellowCtrl.text = defWtY.toStringAsFixed(1);
        _moistureMaxCtrl.text = defMoistG.toStringAsFixed(1);
        _moistureYellowCtrl.text = defMoistY.toStringAsFixed(1);
      });
    }
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _priceCtrl,
      _weightCtrl,
      _tolGreenCtrl,
      _tolYellowCtrl,
      _moistureMaxCtrl,
      _moistureYellowCtrl,
      _expiryCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.existing != null ? 'Edit Product' : 'Add Product'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Product Name'),
                  validator: (v) => v!.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _numField(
                        _priceCtrl,
                        'Price (Rs)',
                        suffix: 'Rs',
                        required: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _numField(
                        _expiryCtrl,
                        'Expiry',
                        suffix: 'months',
                        required: true,
                        isInt: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _sectionLabel(theme, 'Weight Settings'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _numField(
                        _weightCtrl,
                        'Target Weight',
                        suffix: 'g',
                        required: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _numField(
                        _tolGreenCtrl,
                        'Green Tolerance',
                        suffix: '±g',
                        hint: 'e.g. 2',
                        required: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _numField(
                        _tolYellowCtrl,
                        'Yellow Tolerance',
                        suffix: '±g',
                        hint: 'e.g. 4',
                        required: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Within ±green → OK   ±yellow → Warning   >±yellow → Alert',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 16),
                _sectionLabel(theme, 'Moisture Settings'),
                const SizedBox(height: 8),
                if (_isNaMoisture)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Moisture not measured for ${widget.section.name}',
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                else ...[
                  Row(
                    children: [
                      Expanded(
                        child: _numField(
                          _moistureMaxCtrl,
                          'Green Max',
                          suffix: '%',
                          hint: 'e.g. 1.8',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _numField(
                          _moistureYellowCtrl,
                          'Yellow Max',
                          suffix: '%',
                          hint: 'e.g. 2.0',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '≤ Green Max → OK   ≤ Yellow Max → Warning   > Yellow Max → Alert',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.55,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) {
    return Text(
      text,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _numField(
    TextEditingController ctrl,
    String label, {
    String? suffix,
    String? hint,
    bool required = false,
    bool isInt = false,
  }) {
    return TextFormField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        hintText: hint,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: required ? (v) => v!.trim().isEmpty ? 'Required' : null : null,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final moistureMax = _isNaMoisture
        ? 0.0
        : (double.tryParse(_moistureMaxCtrl.text) ?? 0.0);
    final moistureYellowMax = _isNaMoisture
        ? 0.0
        : (double.tryParse(_moistureYellowCtrl.text) ?? moistureMax + 0.2);

    final product = ProductModel(
      id: widget.existing?.id ?? '',
      name: _nameCtrl.text.trim(),
      section: widget.section.id,
      price: double.tryParse(_priceCtrl.text) ?? 0,
      weightGrams: double.tryParse(_weightCtrl.text) ?? 0,
      weightToleranceGreen: double.tryParse(_tolGreenCtrl.text) ?? 2.0,
      weightToleranceYellow: double.tryParse(_tolYellowCtrl.text) ?? 4.0,
      moistureMax: moistureMax,
      moistureYellowMax: moistureYellowMax,
      expiryDays: int.tryParse(_expiryCtrl.text) ?? 3,
      imagePath: widget.existing?.imagePath,
    );

    final err = await context.read<ProductsProvider>().save(product);
    if (mounted) {
      Navigator.pop(context);
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: AppColors.red),
        );
      }
    }
  }
}
