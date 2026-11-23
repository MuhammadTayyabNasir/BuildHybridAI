enum AppLanguage { english, urdu }

enum HelpTopic { findReference, meterIsDifferent }

enum HelpSource { reviewedGuide, onDeviceAi, cloudAi }

class HelpReply {
  const HelpReply(this.text, this.source);

  final String text;
  final HelpSource source;
}

typedef CloudTextGenerator = Future<String?> Function(String prompt);
typedef LocalTextGenerator = Future<String?> Function(HelpTopic topic);

/// A public glossary topic is the entire cloud input. No image, entered value,
/// transcript, or raw screen state can enter this API.
class CoachService {
  const CoachService({
    this.cloudTextGenerator,
    this.localTextGenerator,
    this.cloudTimeout = const Duration(seconds: 45),
    this.localTimeout = const Duration(minutes: 5),
  });

  final CloudTextGenerator? cloudTextGenerator;
  final LocalTextGenerator? localTextGenerator;
  final Duration cloudTimeout;
  final Duration localTimeout;

  HelpReply reviewedHint(HelpTopic topic, AppLanguage language) {
    return HelpReply(switch ((topic, language)) {
      (HelpTopic.findReference, AppLanguage.english) =>
        'Find “Payment Reference” near the top of the sample bill. Copy those 14 digits into the field.',
      (HelpTopic.findReference, AppLanguage.urdu) =>
        'نمونہ بل کے اوپر "Payment Reference" تلاش کریں۔ اس کے ۱۴ ہندسے متعلقہ خانے میں لکھیں۔',
      (HelpTopic.meterIsDifferent, AppLanguage.english) =>
        'The meter number identifies the meter. This practice form needs the separate Payment Reference.',
      (HelpTopic.meterIsDifferent, AppLanguage.urdu) =>
        'میٹر نمبر، میٹر کی شناخت ہے۔ اس مشق کے لیے الگ Payment Reference نمبر درکار ہے۔',
    }, HelpSource.reviewedGuide);
  }

  /// Built from enums only. Keep this method separate for privacy regression tests.
  String publicPrompt(HelpTopic topic, AppLanguage language) {
    final topicCode = switch (topic) {
      HelpTopic.findReference => 'find_payment_reference',
      HelpTopic.meterIsDifferent => 'meter_number_is_not_payment_reference',
    };
    final languageCode = language == AppLanguage.urdu ? 'ur' : 'en';
    return 'You explain a fictional electricity bill practice flow. '
        'Topic: $topicCode. Language: $languageCode. '
        'In at most two short sentences, explain where to find the Payment Reference '
        'or how it differs from a meter number. Do not invent a number, request '
        'personal data, suggest a real payment, or claim to have read a bill image. '
        'Return plain text only.';
  }

  Future<HelpReply> explain(HelpTopic topic, AppLanguage language) async {
    final generator = cloudTextGenerator;
    if (generator == null) return reviewedHint(topic, language);
    try {
      final reply = (await generator(
        publicPrompt(topic, language),
      ).timeout(cloudTimeout))?.trim();
      if (reply == null ||
          reply.isEmpty ||
          reply.length > 360 ||
          RegExp(r'\d{6,}').hasMatch(reply)) {
        return reviewedHint(topic, language);
      }
      return HelpReply(reply, HelpSource.cloudAi);
    } catch (_) {
      return reviewedHint(topic, language);
    }
  }

  Future<HelpReply> explainOnDevice(
    HelpTopic topic,
    AppLanguage language,
  ) async {
    final generator = localTextGenerator;
    // Firebase currently validates Android on-device text inference for English
    // and Korean. Built-in Urdu guidance remains available without model access.
    if (language != AppLanguage.english || generator == null) {
      return reviewedHint(topic, language);
    }
    try {
      final reply = (await generator(topic).timeout(localTimeout))?.trim();
      if (reply == null ||
          reply.isEmpty ||
          reply.length > 360 ||
          RegExp(r'\d{6,}').hasMatch(reply)) {
        return reviewedHint(topic, language);
      }
      return HelpReply(reply, HelpSource.onDeviceAi);
    } catch (_) {
      return reviewedHint(topic, language);
    }
  }
}
