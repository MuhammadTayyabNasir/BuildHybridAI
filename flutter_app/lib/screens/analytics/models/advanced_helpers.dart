import 'package:flutter/material.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../models/packing_entry_model.dart';

bool isAdvancedDefect(PackingEntryModel e) =>
    e.weightStatus == 'red' ||
        e.moistureStatus == 'red' ||
        e.printingStatus == 'not_okay' ||
        e.leakageStatus == 'red';

class MachineStats {
  final int machineNumber;
  final String section;
  int total = 0;
  int defectEntries = 0;
  int weightDefects = 0;
  int moistureDefects = 0;
  int printDefects = 0;
  int leakageDefects = 0;
  final Map<String, int> productCounts = {};

  MachineStats(this.machineNumber, this.section);

  void add(PackingEntryModel e) {
    total++;
    bool bad = false;
    if (e.weightStatus == 'red') { weightDefects++; bad = true; }
    if (e.moistureStatus == 'red') { moistureDefects++; bad = true; }
    if (e.printingStatus == 'not_okay') { printDefects++; bad = true; }
    if (e.leakageStatus == 'red') { leakageDefects++; bad = true; }
    if (bad) defectEntries++;
    productCounts[e.productName] = (productCounts[e.productName] ?? 0) + 1;
  }

  int get totalDefects => weightDefects + moistureDefects + printDefects + leakageDefects;
  double get defectRate => total == 0 ? 0 : defectEntries / total;

  String? get topProduct {
    if (productCounts.isEmpty) return null;
    return productCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  Color get statusColor {
    if (defectRate > 0.15) return AppColors.red;
    if (defectRate > 0.05) return AppColors.yellow;
    return AppColors.green;
  }
}

class SecData {
  int total = 0, defects = 0;
  int weight = 0, leak = 0, print = 0, moist = 0;
  double get passRate => total == 0 ? 0 : (total - defects) / total;
}

class DayData {
  int green = 0, yellow = 0, red = 0;
}

class BreakdownCat {
  final String name;
  final IconData icon;
  final int pass, warn, fail;
  const BreakdownCat(this.name, this.icon, this.pass, this.warn, this.fail);
}