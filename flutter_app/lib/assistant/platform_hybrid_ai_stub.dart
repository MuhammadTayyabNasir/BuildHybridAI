import 'package:flutter/foundation.dart';

import 'cloud_hybrid_ai.dart';
import 'hybrid_ai.dart';

/// Native platforms: the Kotlin bridge on Android (Gemini Nano + cloud
/// fallback), cloud Gemini from Dart elsewhere.
HybridAi createPlatformHybridAi() =>
    defaultTargetPlatform == TargetPlatform.android ? ChannelHybridAi() : CloudHybridAi();
