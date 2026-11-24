import 'hybrid_ai.dart';
import 'platform_hybrid_ai_stub.dart'
    if (dart.library.js_interop) 'chrome_hybrid_ai.dart' as platform;

/// The hybrid model for this platform:
/// * Android — Firebase AI Logic hybrid (Gemini Nano on-device, cloud fallback)
/// * Chrome  — built-in Gemini Nano (Prompt API), cloud fallback
/// * others  — cloud Gemini
HybridAi createHybridAi() => platform.createPlatformHybridAi();
