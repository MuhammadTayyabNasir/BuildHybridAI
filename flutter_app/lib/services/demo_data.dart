import 'dart:math';

import '../core/constants/sections.dart';
import '../models/machine_model.dart';
import '../models/product_model.dart';
import '../models/temp_humidity_model.dart';
import '../models/user_model.dart';
import '../providers/entries_provider.dart';
import 'firestore_service.dart';
import 'local_storage_service.dart';
import 'test_data_service.dart';

/// "Try the demo": a local-only admin session filled with made-up factory
/// data, so judges (and automated UI tests) can see every screen without an
/// account. Nothing here signs in to Firebase; uploads simply fail quietly.
class DemoData {
  DemoData(this._local, this._firestore, this._entries);

  final LocalStorageService _local;
  final FirestoreService _firestore;
  final EntriesProvider _entries;

  static final user = UserModel(
    id: 'demo',
    username: 'demo',
    role: 'admin',
    createdAt: DateTime(2026, 11, 1),
  );

  /// Seeds once: catalogue, 3 weeks of packing checks and twice-daily
  /// temperature / humidity readings, leaving today's evening reading open so
  /// "missed entries" has something to find.
  Future<void> ensureSeeded() async {
    if (_local.getMeta('pma_demo_seeded') == '1') return;

    if (_local.getProducts().isEmpty) {
      var i = 0;
      await _local.saveProducts([
        for (final p in _firestore.defaultProducts())
          ProductModel.fromMap(p.toMap(), 'demo-p${i++}'),
      ]);
    }
    if (_local.getMachines().isEmpty) {
      var i = 0;
      await _local.saveMachines([
        for (final m in _firestore.defaultMachines())
          MachineModel.fromMap(m.toMap(), 'demo-m${i++}'),
      ]);
    }
    await TestDataService(_entries, _local).seed(days: 21, maxPerDayPerSection: 3);
    await _seedReadings(days: 21);
    await _local.setMeta('pma_demo_seeded', '1');
  }

  Future<void> _seedReadings({required int days}) async {
    final rng = Random(7);
    final now = DateTime.now();
    for (final section in Sections.all) {
      for (var d = days; d >= 0; d--) {
        final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: d));
        for (final shift in const ['morning', 'night']) {
          // Today: only the morning reading is in, so one is "missing".
          if (d == 0 && shift == 'night') continue;
          final hot = rng.nextDouble() < 0.12;
          final row = TempHumidityRow(
            time: shift == 'morning' ? '10:00' : '22:00',
            temperature: double.parse((28 + rng.nextDouble() * 6 + (hot ? 7 : 0)).toStringAsFixed(1)),
            humidity: double.parse((40 + rng.nextDouble() * 10 + (hot ? 8 : 0)).toStringAsFixed(1)),
            section: section.id,
            enteredBy: 'demo',
            source: 'demo',
          );
          await _local.saveTempHumidityReport(TempHumidityReport(
            id: 'demo-th-${section.id}-${day.millisecondsSinceEpoch}-$shift',
            sectionId: section.id,
            date: day,
            shift: shift,
            rows: [row],
            preparedBy: 'demo',
            isSynced: true,
            createdAt: day,
            updatedAt: day,
          ));
        }
      }
    }
  }
}
