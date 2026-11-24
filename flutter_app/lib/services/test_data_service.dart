import 'dart:math';

import '../models/machine_model.dart';
import '../models/packing_entry_model.dart';
import '../models/product_model.dart';
import '../providers/entries_provider.dart';
import 'local_storage_service.dart';

/// Generates realistic-but-fake packing entries for QC testing, and wipes them
/// again before handover. Test-only — exposed in Settings to admins. Writes go
/// through [EntriesProvider] so they take the same local-first + platform-correct
/// (gRPC mobile / REST Windows) path as a real operator's entries.
class TestDataService {
  final EntriesProvider _entries;
  final LocalStorageService _local;

  TestDataService(this._entries, this._local);

  static const _supervisors = <String>[
    'Ahmed Raza',
    'Bilal Khan',
    'Sara Iqbal',
    'Usman Tariq',
    'Khadija Noor',
  ];

  /// Seed entries spread across the last [days] days, every section, every
  /// machine, a mix of products (incl. price variants) and supervisors, with a
  /// realistic pass/warning/fail spread on each quality check. Returns the count
  /// generated (0 if no products/machines exist yet — open the app once first).
  Future<int> seed({
    int days = 60,
    int maxPerDayPerSection = 4,
    void Function(int done, int total)? onProgress,
    /// Where generated entries go. Defaults to the entries provider (which
    /// also uploads); demo mode passes a local-only sink.
    Future<void> Function(List<PackingEntryModel> slice)? sink,
  }) async {
    final products = _local.getProducts();
    final machines = _local.getMachines();
    if (products.isEmpty || machines.isEmpty) return 0;

    final rng = Random();
    final now = DateTime.now();
    final sections = <String>{
      ...products.map((p) => p.section),
      ...machines.map((m) => m.section),
    }.toList();

    final batch = <PackingEntryModel>[];
    for (var d = 0; d < days; d++) {
      final day = now.subtract(Duration(days: d));
      for (final sec in sections) {
        final secProducts = products.where((p) => p.section == sec).toList();
        final secMachines = machines.where((m) => m.section == sec).toList();
        if (secProducts.isEmpty || secMachines.isEmpty) continue;
        final n = 1 + rng.nextInt(maxPerDayPerSection);
        for (var i = 0; i < n; i++) {
          batch.add(_makeEntry(rng, day, sec, secProducts, secMachines));
        }
      }
    }

    final total = batch.length;
    var done = 0;
    const chunk = 40;
    for (var i = 0; i < batch.length; i += chunk) {
      final slice = batch.sublist(i, min(i + chunk, batch.length));
      if (sink != null) {
        await sink(slice);
      } else {
        await _entries.addEntries(slice); // local-first; uploads in background
      }
      done += slice.length;
      onProgress?.call(done, total);
      await Future.delayed(const Duration(milliseconds: 25)); // throttle uploads
    }
    return total;
  }

  /// Delete every entry locally and in the cloud. Returns count removed.
  Future<int> wipeAll({void Function(int done, int total)? onProgress}) =>
      _entries.wipeAll(onProgress: onProgress);

  PackingEntryModel _makeEntry(
    Random rng,
    DateTime day,
    String section,
    List<ProductModel> products,
    List<MachineModel> machines,
  ) {
    final p = products[rng.nextInt(products.length)];
    final m = machines[rng.nextInt(machines.length)];
    final created = DateTime(
        day.year, day.month, day.day, 6 + rng.nextInt(14), rng.nextInt(60));

    final weight = _pick(rng, green: 72, yellow: 18, red: 10);
    final hasMoisture = p.moistureMax > 0;
    final moisture =
        hasMoisture ? _pick(rng, green: 75, yellow: 17, red: 8) : 'na';
    final printOk = rng.nextInt(100) < 86;
    final printColor = printOk ? null : _pick(rng, green: 0, yellow: 55, red: 45);
    final leak = _pick(rng, green: 80, yellow: 13, red: 7);

    final target = p.weightGrams > 0 ? p.weightGrams : 100.0;
    final tolG = p.weightToleranceGreen > 0 ? p.weightToleranceGreen : 2.0;
    final tolY = p.weightToleranceYellow > 0 ? p.weightToleranceYellow : 4.0;
    double pouch() {
      final spread = weight == 'green'
          ? tolG * 0.6
          : weight == 'yellow'
              ? (tolG + tolY) / 2
              : tolY + 3;
      final sign = rng.nextBool() ? 1 : -1;
      return double.parse(
          (target + sign * (spread * 0.4 + rng.nextDouble() * spread))
              .toStringAsFixed(1));
    }

    double? moistureActual;
    if (hasMoisture) {
      final yMax = p.moistureYellowMax > 0 ? p.moistureYellowMax : p.moistureMax + 2;
      final base = moisture == 'green'
          ? p.moistureMax * 0.6
          : moisture == 'yellow'
              ? (p.moistureMax + yMax) / 2
              : yMax + 1;
      moistureActual = double.parse((base + rng.nextDouble()).toStringAsFixed(2));
    }

    return PackingEntryModel(
      id: '', // EntriesProvider stamps a uuid
      machineId: m.id,
      machineNumber: m.number,
      section: section,
      productId: p.id,
      productName: p.name,
      price: p.price,
      shift: rng.nextBool() ? 'morning' : 'night',
      operatorId: 'seed',
      operatorName: _supervisors[rng.nextInt(_supervisors.length)],
      dateCodingManufacture: created,
      dateCodingExpiry:
          created.add(Duration(days: p.expiryDays > 0 ? p.expiryDays : 180)),
      grossWeight: double.parse((target * 4 + rng.nextDouble() * 5).toStringAsFixed(1)),
      pouch1Weight: pouch(),
      pouch2Weight: pouch(),
      pouch3Weight: pouch(),
      pouch4Weight: pouch(),
      moistureIdeal: hasMoisture ? p.moistureMax : null,
      moistureActual: moistureActual,
      weightStatus: weight,
      printingStatus: printOk ? 'okay' : 'not_okay',
      printingColor: printColor,
      printingRemarks: printOk ? null : 'Seed: print shade off',
      leakageStatus: leak,
      leakageRemarks:
          leak == 'green' ? null : 'Seed: ${leak == 'red' ? 'major' : 'minor'} leak',
      moistureStatus: moisture,
      isSynced: false,
      createdAt: created,
      updatedAt: DateTime.now(),
      customFields: null,
    );
  }

  /// Weighted random of green/yellow/red.
  String _pick(Random rng, {required int green, required int yellow, required int red}) {
    final r = rng.nextInt(green + yellow + red);
    if (r < green) return 'green';
    if (r < green + yellow) return 'yellow';
    return 'red';
  }
}
