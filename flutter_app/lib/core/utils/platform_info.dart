import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Centralised platform detection.
///
/// The app ships to Android/iOS (mobile) and Windows (desktop). The sync
/// engine differs by platform:
///   • mobile  → Firebase SDK with real-time listeners
///   • Windows → REST delta sync
///
/// Keeping the checks here means the rest of the code never hard-codes a
/// `Platform.isX` test, so adding a platform later touches only this file.
class PlatformInfo {
  PlatformInfo._();

  /// True on Android or iOS — the platforms that use the Firebase SDK backend.
  static bool get isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// True on Windows — uses the REST delta-sync backend.
  static bool get isWindows => !kIsWeb && Platform.isWindows;

  /// True on any desktop OS.
  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// Short label for the device registry (e.g. "android", "windows").
  static String get osName {
    if (kIsWeb) return 'web';
    return Platform.operatingSystem;
  }
}
