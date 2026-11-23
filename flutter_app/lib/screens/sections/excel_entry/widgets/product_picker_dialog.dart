import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../models/product_model.dart';
import '../../../../core/previews/theme_preview.dart';

// ── Preview ─────────────────────────────────────────────────────────────
@ThemePreview(name: 'Product Picker Dialog')
Widget previewProductPickerDialog() => const ProductPickerDialog(
  allProducts: [],
  currentSectionId: 'chips',
);
class ProductPickerDialog extends StatefulWidget {
  final List<ProductModel> allProducts;
  final String currentSectionId;
  final ProductModel? selected;

  const ProductPickerDialog({
    super.key,
    required this.allProducts,
    required this.currentSectionId,
    this.selected,
  });

  @override
  State<ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<ProductPickerDialog> {
  final _ctrl = TextEditingController();
  String _q = '';

  static const _labels = {
    'chips': 'Chips',
    'peri_peri': 'Peri Peri',
    'nimko': 'Nimko',
    'wafer': 'Wafer',
    'chocolate': 'Chocolate',
  };

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<ProductModel> get _filtered {
    final q = _q.toLowerCase();
    if (q.isEmpty) return widget.allProducts;
    return widget.allProducts
        .where((p) =>
    p.name.toLowerCase().contains(q) ||
        p.price.toStringAsFixed(0).contains(q) ||
        (_labels[p.section] ?? p.section).toLowerCase().contains(q))
        .toList();
  }

  List<Object> _buildItems() {
    final f = _filtered;
    final cur = f.where((p) => p.section == widget.currentSectionId).toList();
    final others = f.where((p) => p.section != widget.currentSectionId).toList();
    final grouped = <String, List<ProductModel>>{};

    for (final p in others) {
      grouped.putIfAbsent(p.section, () => []).add(p);
    }

    return [
      if (cur.isNotEmpty) ...[
        '__header__${widget.currentSectionId}',
        ...cur,
      ],
      for (final e in grouped.entries) ...[
        '__header__${e.key}',
        ...e.value,
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildItems();
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
              child: Row(children: [
                const Expanded(
                    child: Text('Select Product',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search…',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  suffixIcon: _q.isNotEmpty
                      ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() {
                        _ctrl.clear();
                        _q = '';
                      }))
                      : null,
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final item = items[i];
                  if (item is String && item.startsWith('__header__')) {
                    final sec = item.substring(10);
                    final isCurrent = sec == widget.currentSectionId;
                    return Container(
                      color: isCurrent
                          ? AppColors.sectionColor(sec).withValues(alpha: 0.08)
                          : null,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Row(children: [
                        if (isCurrent) const Text('⭐ ', style: TextStyle(fontSize: 12)),
                        Text(_labels[sec] ?? sec,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: AppColors.sectionColor(sec))),
                      ]),
                    );
                  }
                  final p = item as ProductModel;
                  final isSelected = p.id == widget.selected?.id;
                  return ListTile(
                    dense: true,
                    selected: isSelected,
                    title: Text('${p.name}  Rs.${p.price.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 13)),
                    subtitle: Text('${p.weightGrams}g · exp ${p.expiryDays} Months',
                        style: const TextStyle(fontSize: 11)),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: AppColors.green, size: 18)
                        : null,
                    onTap: () => Navigator.pop(context, p),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('${_filtered.length} products',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}