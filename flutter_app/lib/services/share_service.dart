import 'package:share_plus/share_plus.dart';

/// Thin wrapper around share_plus for sharing an exported Excel file.
///
/// Note on WhatsApp: Android does not let an app pre-select the recipient for a
/// file attachment, so we open the system share sheet with the file attached
/// and the operator taps WhatsApp → the saved contact/group. The [recipient]
/// (set in Settings) is folded into the caption as a reminder of who to send to.
class ShareService {
  ShareService._();

  static Future<void> shareReport(String path, {String? recipient}) async {
    final caption = StringBuffer('PMA packing report');
    if (recipient != null && recipient.trim().isNotEmpty) {
      caption.write(' — for ${recipient.trim()}');
    }
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], text: caption.toString()),
    );
  }
}
