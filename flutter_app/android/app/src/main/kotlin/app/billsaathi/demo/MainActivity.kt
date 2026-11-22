package app.billsaathi.demo

import com.google.firebase.Firebase
import com.google.firebase.ai.InferenceMode
import com.google.firebase.ai.OnDeviceConfig
import com.google.firebase.ai.ai
import com.google.firebase.ai.type.GenerativeBackend
import com.google.firebase.ai.type.PublicPreviewAPI
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

@OptIn(PublicPreviewAPI::class)
class MainActivity : FlutterActivity()
{
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bill_saathi/on_device")
            .setMethodCallHandler { call, result ->
                if (call.method != "explain") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val prompt = when (call.argument<String>("topic")) {
                    "findReference" -> "For a fictional electricity bill practice, explain in one short English sentence where to find the Payment Reference. Do not invent numbers or ask for personal information."
                    "meterIsDifferent" -> "For a fictional electricity bill practice, explain in one short English sentence why a meter number is different from a Payment Reference. Do not invent numbers or ask for personal information."
                    else -> {
                        result.error("INVALID_TOPIC", "Unknown public help topic.", null)
                        return@setMethodCallHandler
                    }
                }
                scope.launch {
                    try {
                        val model = Firebase.ai(backend = GenerativeBackend.googleAI())
                            .generativeModel(
                                modelName = "gemini-3.8-flash",
                                onDeviceConfig = OnDeviceConfig(mode = InferenceMode.ONLY_ON_DEVICE),
                            )
                        result.success(model.generateContent(prompt).text)
                    } catch (_: Exception) {
                        result.error("LOCAL_MODEL_UNAVAILABLE", "The on-device model is unavailable.", null)
                    }
                }
            }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
