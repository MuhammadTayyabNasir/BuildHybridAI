import '../core/constants/firebase_config.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/cupertino.dart';
import '../models/machine_model.dart';
import '../models/packing_entry_model.dart';
import '../models/product_model.dart';
import '../models/temp_humidity_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: FirebaseConfig.databaseId);

  FirestoreService();

  // ── Products ──────────────────────────────────────────────
  Future<List<ProductModel>> fetchProducts({String? section}) async {
    Query<Map<String, dynamic>> query = _db.collection('products');
    if (section != null) {
      query = query.where('section', isEqualTo: section);
    }

    final snap = await query.get();
    return snap.docs
        .map((d) => ProductModel.fromMap(d.data(), d.id))
        .where((p) => p.isActive)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<String> saveProduct(ProductModel product) async {
    if (product.id.isEmpty) {
      final docRef = await _db.collection('products').add(product.toMap());
      return docRef.id;
    } else {
      await _db.collection('products').doc(product.id).set(product.toMap(), SetOptions(merge: true));
      return product.id;
    }
  }

  Future<void> deleteProduct(String id) async {
    await _db.collection('products').doc(id).update({'isActive': false});
  }

  // ── Machines ──────────────────────────────────────────────
  Future<List<MachineModel>> fetchMachines({String? section}) async {
    Query<Map<String, dynamic>> query = _db.collection('machines');
    if (section != null) {
      query = query.where('section', isEqualTo: section);
    }

    final snap = await query.get();
    return snap.docs
        .map((d) => MachineModel.fromMap(d.data(), d.id))
        .where((m) => m.isActive)
        .toList()
      ..sort((a, b) => a.number.compareTo(b.number));
  }

  Future<String> saveMachine(MachineModel machine) async {
    if (machine.id.isEmpty) {
      final docRef = await _db.collection('machines').add(machine.toMap());
      return docRef.id;
    } else {
      await _db.collection('machines').doc(machine.id).set(machine.toMap(), SetOptions(merge: true));
      return machine.id;
    }
  }

  Future<void> deleteMachine(String id) async {
    await _db.collection('machines').doc(id).update({'isActive': false});
  }

  // ── Packing Entries ───────────────────────────────────────
  Future<List<PackingEntryModel>> fetchEntries({
    required String section,
    DateTime? from,
    DateTime? to,
    String? shift,
  }) async {
    Query<Map<String, dynamic>> query = _db.collection('packing_entries')
        .where('section', isEqualTo: section);

    if (shift != null) {
      query = query.where('shift', isEqualTo: shift);
    }

    final snap = await query.get();

    // We filter dates client-side to avoid requiring complex composite indexes in Firestore
    return snap.docs
        .map((d) => PackingEntryModel.fromMap(d.data(), d.id))
        .where((e) {
      if (from != null && e.createdAt.isBefore(from)) return false;
      if (to != null && e.createdAt.isAfter(to)) return false;
      return true;
    })
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<List<PackingEntryModel>> fetchAllEntries({
    DateTime? from,
    DateTime? to,
  }) async {
    final snap = await _db.collection('packing_entries').get();

    return snap.docs
        .map((d) => PackingEntryModel.fromMap(d.data(), d.id))
        .where((e) {
      if (from != null && e.createdAt.isBefore(from)) return false;
      if (to != null && e.createdAt.isAfter(to)) return false;
      return true;
    })
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<String> saveEntry(PackingEntryModel entry) async {
    final data = entry.toMap()..['isSynced'] = true;
    if (entry.id.isEmpty) {
      final docRef = await _db.collection('packing_entries').add(data);
      return docRef.id;
    } else {
      await _db.collection('packing_entries').doc(entry.id).set(data, SetOptions(merge: true));
      return entry.id;
    }
  }

  Future<void> deleteEntry(String id) async {
    await _db.collection('packing_entries').doc(id).delete();
  }

  // ── Seed default data ─────────────────────────────────────
  Future<void> seedInitialData() async {
    try {
      final existing = await _db.collection('products').limit(1).get();
      if (existing.docs.isNotEmpty) return;

      final batch = _db.batch();

      for (final p in _defaultProducts()) {
        final docRef = _db.collection('products').doc();
        batch.set(docRef, p.toMap());
      }
      for (final m in _defaultMachines()) {
        final docRef = _db.collection('machines').doc();
        batch.set(docRef, m.toMap());
      }

      await batch.commit();
    } catch (e) {
      debugPrint('[FirestoreService] seedInitialData failed: $e');
    }
  }

  // Peri Peri: moisture green≤1.8, yellow≤2.2
  ProductModel _pp(String name, double price, double wg, int exp, {String? img}) =>
      ProductModel(id: '', name: name, section: 'peri_peri', price: price,
          weightGrams: wg, moistureMax: 1.8, moistureYellowMax: 2.2, expiryDays: exp, imagePath: img);

  // Chips: moisture green≤1.7, yellow≤2.0
  ProductModel _ch(String name, double price, double wg, int exp, {String? img}) =>
      ProductModel(id: '', name: name, section: 'chips', price: price,
          weightGrams: wg, moistureMax: 1.7, moistureYellowMax: 2.0, expiryDays: exp, imagePath: img);

  // Nimko: yellow = moistureMax+0.2 (handled by model default)
  ProductModel _nk(String name, double price, double wg, double mmax, int exp, {String? img}) =>
      ProductModel(id: '', name: name, section: 'nimko', price: price,
          weightGrams: wg, moistureMax: mmax, expiryDays: exp, imagePath: img);

  // Wafer / Chocolate: moisture N/A (moistureMax=0)
  ProductModel _wf(String name, double price, double wg, int exp, {String? img}) =>
      ProductModel(id: '', name: name, section: 'wafer', price: price,
          weightGrams: wg, moistureMax: 0, expiryDays: exp, imagePath: img);

  ProductModel _coc(String name, double price, double wg, int exp, {String? img}) =>
      ProductModel(id: '', name: name, section: 'chocolate', price: price,
          weightGrams: wg, moistureMax: 0, expiryDays: exp, imagePath: img);

  /// Default catalogue, also used to seed demo mode.
  List<ProductModel> defaultProducts() => _defaultProducts();
  List<MachineModel> defaultMachines() => _defaultMachines();

  List<ProductModel> _defaultProducts() => [
    // Peri Peri
    _pp("Peri Peri Flamin' Hot",   20, 18,  30),
    _pp("Peri Peri Flamin' Hot",   50, 45,  30),
    _pp("Peri Peri Flamin' Hot",  100, 100, 30),
    _pp('Peri Peri Chutney Chaska', 20, 18,  30),
    _pp('Peri Peri Chutney Chaska', 50, 45,  30),
    _pp('Peri Peri Chutney Chaska',100, 100, 30),
    _pp('Peri Peri Toofani Mirch',  20, 18,  30),
    _pp('Peri Peri Toofani Mirch',  50, 45,  30),
    _pp('Peri Peri Toofani Mirch', 100, 100, 30),
    _pp('Peri Peri Cheese',  20, 18,  30),
    _pp('Peri Peri Cheese',  50, 45,  30),
    _pp('Peri Peri Cheese', 100, 100, 30),
    _pp('Barbeta',  20, 10, 30),
    _pp('Barbeta',  30, 16, 30),
    _pp('Barbeta',  50, 30, 30),
    _pp('Barbeta', 100, 75, 30),
    _pp('Corn Sticks Cheese', 10, 12, 30),
    _pp('Corn Sticks Cheese', 20, 18, 30),
    _pp('Ringo Masala', 20, 18, 30),
    _pp('Ringo Masala', 50, 45, 30),
    _pp('Ringo Cheese', 20, 18, 30),
    _pp('Ringo Cheese', 50, 45, 30),
    _pp('Magic Puff Cheese', 10, 12, 30),
    _pp('Magic Puff Cheese', 20, 18, 30),
    _pp('Magic Puff Masala', 10, 12, 30),
    _pp('Magic Puff Masala', 20, 18, 30),
    // Chips
    _ch('Chips Masala',      20, 12, 30),
    _ch('Chips Masala',      30, 21, 30),
    _ch('Chips Masala',      50, 35, 30),
    _ch('Chips Masala',     100, 75, 30),
    _ch('Chips Yogurt & Herb', 20, 12, 30),
    _ch('Chips Yogurt & Herb', 30, 21, 30),
    _ch('Chips Yogurt & Herb', 50, 35, 30),
    _ch('Chips Yogurt & Herb',100, 75, 30),
    _ch('Chips Cheese',  20, 12, 30),
    _ch('Chips Cheese',  30, 21, 30),
    _ch('Chips Cheese',  50, 35, 30),
    _ch('Chips Cheese', 100, 75, 30),
    _ch('Chips Saltish',  20, 12, 30),
    _ch('Chips Saltish',  30, 21, 30),
    _ch('Chips Saltish',  50, 35, 30),
    _ch('Chips Saltish', 100, 75, 30),
    _ch('Liners BBQ',  20, 12, 30),
    _ch('Liners BBQ',  30, 21, 30),
    _ch('Liners BBQ',  50, 35, 30),
    _ch('Liners BBQ', 100, 75, 30),
    _ch('Potato Stick', 30, 12, 30),
    _ch('Potato Stick', 50, 42, 30),
    // Nimko (moistureYellowMax = moistureMax + 0.2 by default)
    _nk('Nimko Mix',  20,  20, 1.8, 90),
    _nk('Nimko Mix',  30,  28, 1.8, 90),
    _nk('Nimko Mix',  50,  45, 1.8, 90),
    _nk('Nimko Mix', 100, 113, 1.8, 90),
    _nk('Peanut',  30, 14, 1.8, 90),
    _nk('Peanut',  50, 23, 1.8, 90),
    _nk('Peanut', 100, 50, 1.6, 90),
    _nk('Peanut', 200,100, 1.6, 90),
    _nk('Dal Chana',  10, 14, 2.8, 90),
    _nk('Dal Chana',  20, 28, 2.8, 90),
    _nk('Dal Moong',  20, 19, 1.8, 90),
    _nk('Dal Moong',  50, 50, 1.8, 90),
    _nk('Dal Bhujiya', 10, 10, 2.8, 90),
    _nk('Unique Nimko', 20, 30, 2.8, 90),
    _nk('Unique Nimko', 30, 40, 2.8, 90),
    _nk('Unique Nimko', 50, 55, 2.8, 90),
    _nk('Salty', 20, 10, 2.7, 60),
    _nk('Salty', 30, 18, 2.7, 60),
    _nk('Salty', 50, 35, 2.7, 60),
    _nk('Vegi', 20, 10, 2.7, 60),
    _nk('Vegi', 30, 18, 2.7, 60),
    _nk('Vegi', 50, 35, 2.7, 60),
    _nk('Tikonay', 20, 10, 2.8, 90),
    // Wafer
    _wf('Wafer Banana',     10, 12, 90),
    _wf('Wafer Banana',     20, 26, 90),
    _wf('Wafer Chocolate',  10, 12, 90),
    _wf('Wafer Chocolate',  20, 26, 90),
    _wf('Wafer Strawberry', 10, 12, 90),
    _wf('Wafer Strawberry', 20, 26, 90),
    _wf('Wafer Orange',     10, 12, 90),
    _wf('Wafer Orange',     20, 26, 90),
    // Chocolate
    _coc('Unique Chocolate Liquid', 10, 10, 180),
    _coc('Chocobar Brown',           5,  6, 180),
    _coc('Chocobar White',           5,  6, 180),
  ];

  List<MachineModel> _defaultMachines() {
    final m = <MachineModel>[];
    for (int i = 1; i <= 5; i++) { m.add(MachineModel(id: '', number: i, section: 'chips')); }
    for (final i in [1, 2, 3, 4, 6, 7, 8]) { m.add(MachineModel(id: '', number: i, section: 'peri_peri')); }
    for (int i = 1; i <= 18; i++) { m.add(MachineModel(id: '', number: i, section: 'nimko')); }
    m.add(const MachineModel(id: '', number: 1, section: 'wafer'));
    for (int i = 1; i <= 10; i++) { m.add(MachineModel(id: '', number: i, section: 'chocolate')); }
    return m;
  }

  // ── Temperature & Humidity Reports ───────────────────────

  Future<List<TempHumidityReport>> fetchTempHumidityReports({
    String? sectionId,
  }) async {
    Query<Map<String, dynamic>> query = _db.collection('temp_humidity');
    if (sectionId != null) {
      query = query.where('sectionId', isEqualTo: sectionId);
    }

    final snap = await query.get();
    return snap.docs
        .map((d) => TempHumidityReport.fromMap(d.data(), d.id))
        .toList();
  }

  Future<String> saveTempHumidityReport(TempHumidityReport report) async {
    final data = report.toMap()..['isSynced'] = true;
    if (report.id.isEmpty) {
      final docRef = await _db.collection('temp_humidity').add(data);
      return docRef.id;
    } else {
      await _db.collection('temp_humidity').doc(report.id).set(data, SetOptions(merge: true));
      return report.id;
    }
  }

  Future<void> deleteTempHumidityReport(String id) async {
    await _db.collection('temp_humidity').doc(id).delete();
  }
}