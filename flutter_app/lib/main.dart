import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/coach_service.dart';
import 'firebase_options.dart';
import 'ui/bill_saathi_app.dart';
import 'ui/wallet.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  late final coach = _configureCoach().timeout(
    const Duration(seconds: 15),
    onTimeout: () => const CoachService(),
  );
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Saathi Wallet',
      home: Wallet(
        interpret: (request) async {
          final generate = (await coach).cloudTextGenerator;
          if (generate == null) return null;
          final result = await generate(
            'Classify the following wallet navigation request. Return only donations, challans, history, or unknown. Request: $request',
          ).timeout(const Duration(seconds: 12));
          for (final service in Service.values) {
            if (service.name == result?.trim().toLowerCase()) return service;
          }
          return null;
        },
        practice: (_) => FutureBuilder<CoachService>(
          future: coach,
          builder: (_, snapshot) =>
              BillSaathiApp(coach: snapshot.data ?? const CoachService()),
        ),
      ),
    ),
  );
}

Future<CoachService> _configureCoach() async {
  // The practice flow remains usable on platforms without Firebase options.
  if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android) {
    return const CoachService();
  }
  if (kIsWeb &&
      !kDebugMode &&
      const String.fromEnvironment('RECAPTCHA_ENTERPRISE_SITE_KEY') == '') {
    return const CoachService();
  }
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode
          ? const AppleDebugProvider()
          : const AppleAppAttestWithDeviceCheckFallbackProvider(),
      providerWeb: kDebugMode
          ? WebDebugProvider()
          : ReCaptchaEnterpriseProvider(
              String.fromEnvironment('RECAPTCHA_ENTERPRISE_SITE_KEY'),
            ),
    );
    final model = FirebaseAI.googleAI().generativeModel(
      model: const String.fromEnvironment(
        'GEMINI_MODEL',
        defaultValue: 'gemini-3.8-flash',
      ),
    );
    const localChannel = MethodChannel('bill_saathi/on_device');
    return CoachService(
      localTextGenerator:
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? (topic) => localChannel.invokeMethod<String>('explain', {
              'topic': topic.name,
            })
          : null,
      cloudTextGenerator: (prompt) async {
        final response = await model.generateContent([Content.text(prompt)]);
        return response.text;
      },
    );
  } catch (_) {
    debugPrint('Firebase AI is unavailable; using the built-in guide.');
    return const CoachService();
  }
}
