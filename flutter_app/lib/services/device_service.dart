import 'package:uuid/uuid.dart';
import '../core/utils/platform_info.dart';
import 'local_storage_service.dart';

/// Identifies this installation and assembles the payload written to the
/// `devices/{deviceId}` registry on each sync.
///
/// The device id is generated once and stored in the local KV table. It
/// survives app restarts but is regenerated on reinstall (local storage is
/// wiped) — which is fine and even useful: a new id in the registry marks a
/// fresh install, and the sync cursor resetting triggers a clean full pull.
class DeviceService {
  static const _kDeviceIdKey = 'deviceId';
  static const _kDeviceNameKey = 'deviceName';

  // Bumped manually with releases; surfaced in the registry for support.
  static const appVersion = '1.0.0+1';

  final LocalStorageService _local;
  final _uuid = const Uuid();

  DeviceService(this._local);

  /// Stable id for this install. Created on first call, then reused.
  Future<String> deviceId() async {
    final existing = _local.getMeta(_kDeviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _uuid.v4();
    await _local.setMeta(_kDeviceIdKey, id);
    return id;
  }

  /// Human-friendly name shown in the admin device list. Defaults to the OS
  /// name until the user sets one in Settings.
  String deviceName() =>
      _local.getMeta(_kDeviceNameKey) ?? PlatformInfo.osName;

  Future<void> setDeviceName(String name) =>
      _local.setMeta(_kDeviceNameKey, name.trim());

  /// Registry document fields for `devices/{deviceId}`.
  Future<Map<String, dynamic>> registryPayload() async {
    return {
      'deviceId': await deviceId(),
      'name': deviceName(),
      'platform': PlatformInfo.osName,
      'appVersion': appVersion,
      'lastSyncAt': DateTime.now().millisecondsSinceEpoch,
    };
  }
}
