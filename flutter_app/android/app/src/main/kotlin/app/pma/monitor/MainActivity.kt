package app.pma.monitor

import com.google.firebase.Firebase
import com.google.firebase.ai.GenerativeModel
import com.google.firebase.ai.InferenceMode
import com.google.firebase.ai.InferenceSource
import com.google.firebase.ai.OnDeviceConfig
import com.google.firebase.ai.ai
import com.google.firebase.ai.ondevice.DownloadStatus
import com.google.firebase.ai.ondevice.FirebaseAIOnDevice
import com.google.firebase.ai.ondevice.OnDeviceModelStatus
import com.google.firebase.ai.type.GenerativeBackend
import com.google.firebase.ai.type.PublicPreviewAPI
import com.google.firebase.ai.type.Schema
import com.google.firebase.ai.type.generationConfig
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout

/**
 * Firebase AI Logic hybrid inference for PMA.
 *
 * Flutter's firebase_ai package has no hybrid mode yet, so the Android SDK is
 * called here and exposed on the "pma/hybrid_ai" MethodChannel:
 *
 *  - status        -> on-device model status; starts the Nano download if needed
 *  - parseIntent   -> operator command -> strict JSON intent (PREFER_ON_DEVICE)
 *  - generate      -> free text answer (PREFER_ON_DEVICE, or ONLY_IN_CLOUD for
 *                     long reports)
 *
 * Every answer carries "source": "on-device" or "cloud", taken from the SDK's
 * GenerateContentResponse.inferenceSource. The model only extracts intent and
 * slots; the Dart side validates values and decides what to save.
 */
@OptIn(PublicPreviewAPI::class)
class MainActivity : FlutterActivity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var download: Job? = null

    private val cloudModelName = "gemini-3.8-flash"

    private val intentSchema: Schema by lazy {
        Schema.obj(
            mapOf(
                "intent" to Schema.enumeration(
                    listOf(
                        "count_entries",
                        "find_missing_entries",
                        "add_th_reading",
                        "add_packing_entry",
                        "open_screen",
                        "daily_summary",
                        "unknown",
                    ),
                    "What the operator wants",
                ),
                "section" to Schema.string(
                    "Section id: chips, peri_peri, nimko, wafer or chocolate. Empty if not said.",
                ),
                "temperature" to Schema.double("Temperature in Celsius if said", true),
                "humidity" to Schema.double("Relative humidity percent if said", true),
                "shift" to Schema.string("morning or night if said, else empty"),
                "screen" to Schema.string(
                    "For open_screen: dashboard, temp_humidity, entries, analytics, settings, automations. Else empty.",
                ),
                "period" to Schema.string("today, yesterday or week. Default today."),
                "product" to Schema.string("Product name for add_packing_entry, else empty"),
                "weight" to Schema.double("Gross weight in grams for add_packing_entry", true),
                "confidence" to Schema.double("0 to 1, how sure you are"),
            ),
            listOf("temperature", "humidity", "weight"),
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pma/hybrid_ai")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> scope.launch {
                        result.success(modelStatus(startDownload = true))
                    }

                    "parseIntent" -> {
                        val text = call.argument<String>("text").orEmpty().take(600)
                        val today = call.argument<String>("today").orEmpty().take(40)
                        if (text.isBlank()) {
                            result.error("EMPTY", "Nothing to parse.", null)
                            return@setMethodCallHandler
                        }
                        scope.launch {
                            try {
                                val model = model(InferenceMode.PREFER_ON_DEVICE, json = true)
                                val response = withTimeout(25_000L) {
                                    model.generateContent(intentPrompt(text, today))
                                }
                                result.success(
                                    mapOf(
                                        "json" to response.text.orEmpty(),
                                        "source" to sourceLabel(response.inferenceSource),
                                    ),
                                )
                            } catch (e: Exception) {
                                result.error("AI_UNAVAILABLE", e.javaClass.simpleName, null)
                            }
                        }
                    }

                    "generate" -> {
                        val prompt = call.argument<String>("prompt").orEmpty().take(12_000)
                        val cloudOnly = call.argument<Boolean>("cloudOnly") ?: false
                        if (prompt.isBlank()) {
                            result.error("EMPTY", "Nothing to send.", null)
                            return@setMethodCallHandler
                        }
                        scope.launch {
                            try {
                                val mode = if (cloudOnly) InferenceMode.ONLY_IN_CLOUD
                                else InferenceMode.PREFER_ON_DEVICE
                                val response = withTimeout(45_000L) {
                                    model(mode, json = false).generateContent(prompt)
                                }
                                result.success(
                                    mapOf(
                                        "text" to response.text.orEmpty(),
                                        "source" to sourceLabel(response.inferenceSource),
                                    ),
                                )
                            } catch (e: Exception) {
                                result.error("AI_UNAVAILABLE", e.javaClass.simpleName, null)
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun model(mode: InferenceMode, json: Boolean): GenerativeModel {
        val ai = Firebase.ai(backend = GenerativeBackend.googleAI())
        return if (json) {
            ai.generativeModel(
                modelName = cloudModelName,
                generationConfig = generationConfig {
                    responseMimeType = "application/json"
                    responseSchema = intentSchema
                    temperature = 0f
                },
                onDeviceConfig = OnDeviceConfig(mode = mode),
            )
        } else {
            ai.generativeModel(
                modelName = cloudModelName,
                onDeviceConfig = OnDeviceConfig(mode = mode),
            )
        }
    }

    private fun intentPrompt(text: String, today: String): String = """
        You read short commands from a snack factory floor operator. They speak
        English, Urdu, or Roman Urdu (Urdu in Latin letters). Extract the intent
        and slots as JSON. Do not invent values that were not said.
        Intents:
        - count_entries: how many entries were made (e.g. "aaj main ne kitni entries ki")
        - find_missing_entries: which scheduled readings are missing (e.g. "koi entry miss to nahi hui")
        - add_th_reading: record temperature and/or humidity for a section
          (e.g. "Peri Peri section ki humidity 45 dal do")
        - add_packing_entry: record a packing check (product, weight)
        - open_screen: open a sheet or screen (e.g. "Peri Peri ki sheet kholo")
        - daily_summary: a short report of today (e.g. "aaj ki report kya hai")
        - unknown: anything else
        Sections: chips, peri_peri (Peri Peri), nimko, wafer, chocolate.
        Urdu number words count, e.g. "paintalis" = 45, "pachees" = 25.
        Today is $today.
        Operator said: "$text"
    """.trimIndent()

    private fun sourceLabel(source: InferenceSource?): String =
        if (source == InferenceSource.ON_DEVICE) "on-device" else "cloud"

    private suspend fun modelStatus(startDownload: Boolean): String = try {
        when (FirebaseAIOnDevice.checkStatus()) {
            OnDeviceModelStatus.AVAILABLE -> "available"
            OnDeviceModelStatus.DOWNLOADING -> "downloading"
            OnDeviceModelStatus.DOWNLOADABLE -> {
                if (startDownload) startModelDownload()
                "downloadable"
            }
            else -> "unavailable"
        }
    } catch (_: Exception) {
        "unavailable"
    }

    /** Fetch Gemini Nano in the background; cloud answers until it is ready. */
    private fun startModelDownload() {
        if (download?.isActive == true) return
        download = scope.launch {
            try {
                FirebaseAIOnDevice.download().first { status ->
                    status is DownloadStatus.DownloadCompleted ||
                        status is DownloadStatus.DownloadFailed
                }
            } catch (_: Exception) {
                // Stay on cloud fallback.
            }
        }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
