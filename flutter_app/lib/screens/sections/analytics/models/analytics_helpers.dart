import 'package:flutter/material.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../models/packing_entry_model.dart';

bool isFail(PackingEntryModel e) =>
    e.weightStatus == 'red' ||
        e.moistureStatus == 'red' ||
        e.printingStatus == 'not_okay' ||
        e.leakageStatus == 'red';

bool isWarn(PackingEntryModel e) =>
    !isFail(e) &&
        (e.weightStatus == 'yellow' ||
            e.moistureStatus == 'yellow' ||
            e.leakageStatus == 'yellow');

Color rateColor(double pct) {
  if (pct >= 90) return AppColors.green;
  if (pct >= 70) return AppColors.yellow;
  return AppColors.red;
}

double passRate(List<PackingEntryModel> list) {
  if (list.isEmpty) return 0;
  final fails = list.where(isFail).length;
  return (list.length - fails) / list.length * 100;
}

class MachineAgg {
  final int number;
  int total = 0, fails = 0, warns = 0;
  int weight = 0, moisture = 0, print = 0, leak = 0;
  MachineAgg(this.number);

  void add(PackingEntryModel e) {
    total++;
    if (e.weightStatus == 'red') weight++;
    if (e.moistureStatus == 'red') moisture++;
    if (e.printingStatus == 'not_okay') print++;
    if (e.leakageStatus == 'red') leak++;
    if (isFail(e)) {
      fails++;
    } else if (isWarn(e)) {
      warns++;
    }
  }

  double get passRatePct => total == 0 ? 0 : (total - fails) / total * 100;
  Color get color => rateColor(passRatePct);
}

class ProductAgg {
  final String name;
  int total = 0, fails = 0;
  ProductAgg(this.name);
  double get passRatePct => total == 0 ? 0 : (total - fails) / total * 100;
}

class SupAgg {
  final String name;
  int total = 0, fails = 0, warns = 0;
  int weight = 0, moisture = 0, print = 0, leak = 0;
  SupAgg(this.name);

  void add(PackingEntryModel e) {
    total++;
    if (e.weightStatus == 'red') weight++;
    if (e.moistureStatus == 'red') moisture++;
    if (e.printingStatus == 'not_okay') print++;
    if (e.leakageStatus == 'red') leak++;
    if (isFail(e)) {
      fails++;
    } else if (isWarn(e)) {
      warns++;
    }
  }

  double get passRatePct => total == 0 ? 0 : (total - fails) / total * 100;
  Color get color => rateColor(passRatePct);
}

class AnalyticsInsight {
  final IconData icon;
  final Color color;
  final String text;
  const AnalyticsInsight(this.icon, this.color, this.text);
}

class AnalyticsCat {
  final String name;
  final IconData icon;
  final int pass, warn, fail;
  const AnalyticsCat(this.name, this.icon, this.pass, this.warn, this.fail);
}