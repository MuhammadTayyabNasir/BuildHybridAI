import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';

class FormSectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const FormSectionCard({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class FormDropdownField<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) display;
  final void Function(T?) onChanged;
  final String? Function(T?)? validator;

  const FormDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.display,
    required this.onChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final T? safeValue = (value != null && items.contains(value)) ? value : null;
    return DropdownButtonFormField<T>(
      initialValue: safeValue,
      decoration: InputDecoration(labelText: label),
      items: items.map((i) => DropdownMenuItem(value: i, child: Text(display(i)))).toList(),
      onChanged: onChanged,
      validator: validator,
      isExpanded: true,
    );
  }
}

class FormDateField extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  final String? hint;

  const FormDateField({
    super.key,
    required this.label,
    required this.date,
    required this.onTap,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(
          date != null ? DateFormat('dd/MM/yyyy').format(date!) : (hint ?? 'Select'),
          style: TextStyle(fontSize: 14, color: date == null ? AppColors.textHint : null),
        ),
      ),
    );
  }
}

class FormWeightField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final FocusNode? focusNode;
  final FocusNode? nextFocus;
  final ValueChanged<String>? onChanged;
  final Color? statusColor; // NEW: Accepts a dynamic color

  const FormWeightField({
    super.key,
    required this.controller,
    required this.label,
    this.focusNode,
    this.nextFocus,
    this.onChanged,
    this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    // If a status color is provided, we override the default borders
    final border = statusColor != null
        ? OutlineInputBorder(borderSide: BorderSide(color: statusColor!, width: 1.8))
        : const OutlineInputBorder();

    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      textInputAction: nextFocus != null ? TextInputAction.next : TextInputAction.done,
      onFieldSubmitted: (_) => nextFocus?.requestFocus(),
      style: TextStyle(color: statusColor, fontWeight: statusColor != null ? FontWeight.w600 : null), // Optionally tint the text too!
      decoration: InputDecoration(
        labelText: label,
        suffixText: 'g',
        border: border,
        enabledBorder: border,
        focusedBorder: statusColor != null
            ? border.copyWith(borderSide: BorderSide(color: statusColor!, width: 2.2))
            : null,
      ),
      onChanged: onChanged,
    );
  }
}
class FormInfoItem extends StatelessWidget {
  final String label;
  final String value;

  const FormInfoItem({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }
}

class FormStatusChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const FormStatusChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? color : AppColors.divider, width: selected ? 2 : 1),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w600, color: selected ? color : null, fontSize: 13),
          ),
        ),
      ),
    );
  }
}