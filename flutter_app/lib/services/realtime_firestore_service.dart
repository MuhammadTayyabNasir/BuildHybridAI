import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../core/constants/firebase_config.dart';
import '../models/machine_model.dart';
import '../models/packing_entry_model.dart';
import '../models/product_model.dart';
import '../models/temp_humidity_model.dart';

/// Kind of change delivered by a real-time listener.
enum RemoteChangeType { upsert, remove }

/// A single document delta from the live gRPC stream.
class RemoteEntryChange {
  final RemoteChangeType type;
  final String id;

  /// Present for [RemoteChangeType.upsert]; null for removals.
  final PackingEntryModel? entry;

  const RemoteEntryChange(this.type, this.id, this.entry);
}

/// A single temp/humidity report delta from the live gRPC stream.
class RemoteThChange {
  final RemoteChangeType type;
  final String id;
  final TempHumidityReport? report;

  const RemoteThChange(this.type, this.id, this.report);
}

/// gRPC Firestore access via the cloud_firestore SDK (mobile only).
///
/// This is the real-time backend: it listens to Firestore over gRPC and
/// pushes deltas as they happen — no polling, no timer. It targets the
/// *named* database `remoxindatabase` (not `(default)`), which the SDK only
/// reaches through `instanceFor(databaseId:)`.
///
/// Reads are scoped by `updatedAt` so a device only ever streams what changed
/// since its cursor — keeping daily reads well inside the Firebase free tier.
/// Older history lives in the local SQLite cache and is never re-streamed.
class RealtimeFirestoreService {
  FirebaseFirestore? _cached;

  FirebaseFirestore get _db => _cached ??= FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: FirebaseConfig.databaseId,
      );

  CollectionReference<Map<String, dynamic>> get _entries =>
      _db.collection('packing_entries');

  /// Enable offline persistence so reads are served from the SDK's local cache
  /// when possible (fewer billed reads, instant cold start). Call once at init.
  void configure() {
    _db.settings = const Settings(persistenceEnabled: true);
  }

  // ── Real-time entries ───────────────────────────────────────────────────
  /// Live deltas for entries changed at/after [since].
  ///
  /// Uses `docChanges` so each snapshot yields only what actually changed,
  /// not the whole result set — minimal SQLite writes and minimal churn.
  Stream<List<RemoteEntryChange>> watchEntryChanges({DateTime? since}) {
    Query<Map<String, dynamic>> q = _entries.orderBy('updatedAt');
    if (since != null) {
      q = _entries
          .where('updatedAt', isGreaterThan: since.millisecondsSinceEpoch)
          .orderBy('updatedAt');
    }
    return q.snapshots().map((snap) {
      return snap.docChanges.map((c) {
        if (c.type == DocumentChangeType.removed) {
          return RemoteEntryChange(RemoteChangeType.remove, c.doc.id, null);
        }
        final data = c.doc.data();
        return RemoteEntryChange(
          RemoteChangeType.upsert,
          c.doc.id,
          data == null ? null : PackingEntryModel.fromMap(data, c.doc.id),
        );
      }).toList();
    });
  }

  /// On-demand fetch of entries created within a date range — used by reports
  /// for ranges older than the local 90-day window. Bounded by the requested
  /// dates, so it never pulls the whole history.
  Future<List<PackingEntryModel>> fetchEntriesInRange(
      DateTime from, DateTime to) async {
    final snap = await _entries
        .where('createdAt', isGreaterThanOrEqualTo: from.millisecondsSinceEpoch)
        .where('createdAt', isLessThanOrEqualTo: to.millisecondsSinceEpoch)
        .get();
    return snap.docs
        .map((d) => PackingEntryModel.fromMap(d.data(), d.id))
        .toList();
  }

  /// One-shot pull of entries changed since [since] — used for manual sync and
  /// the initial backfill on a fresh install.
  Future<List<PackingEntryModel>> fetchEntriesOnce({DateTime? since}) async {
    Query<Map<String, dynamic>> q = _entries.orderBy('updatedAt');
    if (since != null) {
      q = _entries
          .where('updatedAt', isGreaterThan: since.millisecondsSinceEpoch)
          .orderBy('updatedAt');
    }
    final snap = await q.get();
    return snap.docs
        .map((d) => PackingEntryModel.fromMap(d.data(), d.id))
        .toList();
  }

  // ── Writes (gRPC) ───────────────────────────────────────────────────────
  /// Create/replace an entry. Stamps `updatedAt` and the originating
  /// `deviceId` so other devices can attribute and resolve conflicts.
  Future<void> saveEntry(PackingEntryModel entry, String deviceId) async {
    final data = entry.toMap()
      ..remove('isSynced') // local-only concept
      ..['updatedAt'] = DateTime.now().millisecondsSinceEpoch
      ..['deviceId'] = deviceId;
    await _entries.doc(entry.id).set(data);
  }

  Future<void> deleteEntry(String id) => _entries.doc(id).delete();

  // ── Real-time temp/humidity ─────────────────────────────────────────────
  CollectionReference<Map<String, dynamic>> get _th =>
      _db.collection('temp_humidity');

  /// Create/replace a T&H report over gRPC (mobile write path). `isSynced` is a
  /// local-only concept and is stripped before upload.
  Future<void> saveTempHumidityReport(TempHumidityReport report) async {
    final data = report.toMap()..remove('isSynced');
    await _th.doc(report.id).set(data);
  }

  Future<void> deleteTempHumidityReport(String id) => _th.doc(id).delete();

  /// Live deltas for temp/humidity reports. The collection is small (a few
  /// per day), so we watch it whole; the initial snapshot backfills.
  Stream<List<RemoteThChange>> watchTempHumidityChanges() {
    return _th.snapshots().map((snap) {
      return snap.docChanges.map((c) {
        if (c.type == DocumentChangeType.removed) {
          return RemoteThChange(RemoteChangeType.remove, c.doc.id, null);
        }
        final data = c.doc.data();
        return RemoteThChange(
          RemoteChangeType.upsert,
          c.doc.id,
          data == null ? null : TempHumidityReport.fromMap(data, c.doc.id),
        );
      }).toList();
    });
  }

  // ── Real-time reference data (products + machines) ──────────────────────
  // Small, rarely-changing collections — watch them whole and replace local.
  Stream<List<ProductModel>> watchProducts() {
    return _db.collection('products').snapshots().map((s) => s.docs
        .map((d) => ProductModel.fromMap(d.data(), d.id))
        .where((p) => p.isActive)
        .toList());
  }

  Stream<List<MachineModel>> watchMachines() {
    return _db.collection('machines').snapshots().map((s) => s.docs
        .map((d) => MachineModel.fromMap(d.data(), d.id))
        .where((m) => m.isActive)
        .toList());
  }

  // ── Reference-data writes (gRPC) — mirror FirestoreService, no REST ───────
  Future<String> saveProduct(ProductModel product) async {
    final col = _db.collection('products');
    if (product.id.isEmpty) return (await col.add(product.toMap())).id;
    await col.doc(product.id).set(product.toMap());
    return product.id;
  }

  /// Soft-delete: isActive:false → the watch stream drops it and local replaces.
  Future<void> deleteProduct(String id) => _db
      .collection('products')
      .doc(id)
      .set({'isActive': false}, SetOptions(merge: true));

  Future<String> saveMachine(MachineModel machine) async {
    final col = _db.collection('machines');
    if (machine.id.isEmpty) return (await col.add(machine.toMap())).id;
    await col.doc(machine.id).set(machine.toMap());
    return machine.id;
  }

  Future<void> deleteMachine(String id) => _db
      .collection('machines')
      .doc(id)
      .set({'isActive': false}, SetOptions(merge: true));

  // ── Device registry ─────────────────────────────────────────────────────
  Future<void> upsertDevice(Map<String, dynamic> payload) async {
    final id = payload['deviceId'] as String;
    await _db.collection('devices').doc(id).set(payload, SetOptions(merge: true));
  }
}
