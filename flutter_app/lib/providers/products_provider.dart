import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../models/product_model.dart';
import '../services/firestore_service.dart';
import '../services/local_storage_service.dart';

class ProductsProvider extends ChangeNotifier {
  final FirestoreService _firestore;
  final LocalStorageService _local;

  final Map<String, List<ProductModel>> _cache = {};
  bool _loading = false;
  StreamSubscription? _sub;

  ProductsProvider(this._firestore, this._local);

  bool get loading => _loading;

  List<ProductModel> forSection(String section) => _cache[section] ?? [];

  List<ProductModel> getAll() {
    final out = <ProductModel>[];
    for (final list in _cache.values) {
      out.addAll(list);
    }
    return out;
  }

  // ── gRPC Real-Time Listener ────────────────────────────────────────────────
  void startListening() {
    _sub?.cancel();
    _sub = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'remoxindatabase').collection('products').snapshots().listen((snap) async {
      final products = snap.docs.map((d) => ProductModel.fromMap(d.data(), d.id)).toList();

      _cache.clear();
      for (final p in products) {
        _cache.putIfAbsent(p.section, () => []).add(p);
      }

      // Keep SQLite up to date for offline support
      await _local.saveProducts(products);

      _loading = false;
      notifyListeners();
    }, onError: (e) {
      debugPrint('[ProductsProvider] Snapshot listener error: $e');
    });
  }

  void stopListening() {
    _sub?.cancel();
    _sub = null;
  }
  // ───────────────────────────────────────────────────────────────────────────

  void reloadFromLocal() {
    final cached = _local.getProducts();
    _cache.clear();
    for (final p in cached) {
      _cache.putIfAbsent(p.section, () => []).add(p);
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> loadSection(String section) async {
    if (_cache[section] == null) {
      final local = _local.getProducts().where((p) => p.section == section).toList();
      if (local.isNotEmpty) {
        _cache[section] = local;
        notifyListeners();
      } else {
        _loading = true;
        notifyListeners();
      }
    }
    // The snapshot listener automatically handles fetching from the server
  }

  Future<void> loadAll() async {
    final cached = _local.getProducts();
    if (cached.isNotEmpty) {
      _cache.clear();
      for (final p in cached) {
        _cache.putIfAbsent(p.section, () => []).add(p);
      }
      notifyListeners();
    } else {
      _loading = true;
      notifyListeners();
    }
  }

  Future<String?> save(ProductModel product) async {
    try {
      await _firestore.saveProduct(product);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> delete(ProductModel product) async {
    try {
      await _firestore.deleteProduct(product.id);
      return null;
    } catch (e) {
      return e.toString();
    }
  }
  List<ProductModel> get allProducts {
    final out = <ProductModel>[];
    for (final list in _cache.values) {
      out.addAll(list);
    }
    return out;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}