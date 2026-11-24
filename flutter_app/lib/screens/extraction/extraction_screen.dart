import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../assistant/assistant_intent.dart';
import '../../assistant/hybrid_ai.dart';
import '../../extraction/extracted_form.dart';
import '../../extraction/form_readers.dart';
import '../../extraction/pdf_extraction_job.dart';
import '../../extraction/pdf_pages.dart';
import '../../services/local_storage_service.dart';
import '../../ui/pma_ui.dart';
import 'review_grid_screen.dart';
import '../../assistant/hybrid_ai_factory.dart';

/// Turn paper packing sheets into entries:
/// * Photo — on-device OCR (ML Kit) + Gemini Nano structures the rows, works
///   offline; falls back to cloud Gemini vision.
/// * Bulk PDF — cloud Gemini reads page by page with retry and resume.
/// Both end in the review grid; nothing is saved before review.
class ExtractionScreen extends StatefulWidget {
  const ExtractionScreen({super.key, this.ai});

  /// Hybrid model for structuring OCR text (defaults to the platform one).
  final HybridAi? ai;

  @override
  State<ExtractionScreen> createState() => _ExtractionScreenState();
}

class _ExtractionScreenState extends State<ExtractionScreen> {
  late final HybridAi _ai = widget.ai ?? createHybridAi();
  String? _status;
  bool _busy = false;
  PdfExtractionJob? _job;
  PdfPages? _pdf;

  @override
  void dispose() {
    _job?.cancel();
    _pdf?.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- photo

  Future<void> _photo(ImageSource source) async {
    final shot = await ImagePicker().pickImage(source: source, imageQuality: 85, maxWidth: 2400);
    if (shot == null) return;
    setState(() {
      _busy = true;
      _status = 'Reading the sheet…';
    });
    ExtractedPage? page;
    var label = 'photo:cloud';
    try {
      if (!kIsWeb) {
        final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
        try {
          final text = (await recognizer.processImage(InputImage.fromFilePath(shot.path))).text;
          if (text.trim().length > 20) {
            setState(() => _status = 'On-device OCR done. Structuring rows…');
            final res = await OcrTextStructurer(_ai).structure(text);
            page = res.page;
            label = 'photo:${res.source == AnswerSource.onDevice ? 'on-device' : 'cloud'}';
          }
        } finally {
          await recognizer.close();
        }
      }
      if (page == null || page.rows.isEmpty) {
        setState(() => _status = 'Asking cloud Gemini to read the photo…');
        final raw = await CloudFormReader().read(await shot.readAsBytes(), 'image/jpeg');
        page = ExtractedPage.parseModel(raw, 1);
        if (page != null) DittoFill.apply(page.rows);
        label = 'photo:cloud';
      }
    } catch (e) {
      _status = 'Could not read the photo: $e';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (page == null || page.rows.isEmpty) {
      setState(() => _status ??= 'No table rows found. Try a straighter, brighter photo.');
      return;
    }
    setState(() => _status = null);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReviewGridScreen(pages: [page!], sourceLabel: label),
    ));
  }

  // ------------------------------------------------------------- pdf

  Future<void> _pickPdf() async {
    final local = context.read<LocalStorageService>();
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    final file = picked?.files.singleOrNull;
    final Uint8List? bytes = file?.bytes;
    if (file == null || bytes == null) return;
    _job?.cancel();
    _pdf?.dispose();
    final pdf = PdfPages(bytes);
    final reader = CloudFormReader();
    final job = PdfExtractionJob(
      fileHash: sha256.convert(bytes).toString().substring(0, 24),
      fileName: file.name,
      pageCount: pdf.count,
      readPage: (n) async => reader.read(await pdf.page(n), 'application/pdf'),
      readMeta: local.getMeta,
      writeMeta: local.setMeta,
    );
    setState(() {
      _pdf = pdf;
      _job = job;
      _status = job.done > 0 ? 'Resuming: ${job.done} of ${job.pageCount} pages already read.' : null;
    });
    job.run();
  }

  Future<void> _reviewPdf() async {
    final job = _job;
    if (job == null || job.pages.isEmpty) return;
    final pages = job.pages.keys.toList()..sort();
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ReviewGridScreen(
        pages: [for (final k in pages) job.pages[k]!],
        sourceLabel: 'pdf:cloud',
      ),
    ));
    if (saved == true) {
      await job.clear();
      if (mounted) setState(() => _job = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Pma.canvas,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          GradientHero(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 20, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  BackButton(color: Colors.white),
                  Text('Paper forms',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                ]),
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 8, 0, 0),
                  child: Text(
                    'Photograph a packing sheet or upload a scanned PDF. Ditto marks (") are '
                    'filled from the row above, and you review every row before it is saved.',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: Wrap(spacing: 8, runSpacing: 6, children: [
                    TrendPill(label: 'Photo: on-device OCR + Nano', onDark: true),
                    TrendPill(label: 'PDF: cloud Gemini', onDark: true),
                  ]),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          _ActionCard(
            icon: Icons.photo_camera_outlined,
            title: 'Scan one sheet',
            subtitle: kIsWeb
                ? 'Upload a photo; cloud Gemini reads it.'
                : 'Works offline when Gemini Nano is on the phone.',
            busy: _busy,
            actions: [
              if (!kIsWeb)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Pma.ink, shape: const StadiumBorder()),
                  onPressed: _busy ? null : () => _photo(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera'),
                ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                onPressed: _busy ? null : () => _photo(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Gallery'),
              ),
            ],
          ),
          _ActionCard(
            icon: Icons.picture_as_pdf_outlined,
            title: 'Bulk PDF',
            subtitle: 'Many pages at once. Needs internet. Stops and resumes safely.',
            busy: false,
            actions: [
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Pma.ink, shape: const StadiumBorder()),
                onPressed: _job?.running == true ? null : _pickPdf,
                icon: const Icon(Icons.upload_file),
                label: const Text('Choose PDF'),
              ),
            ],
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(_status!, style: const TextStyle(color: Pma.inkSoft)),
            ),
          if (_job != null) _JobCard(job: _job!, onReview: _reviewPdf),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.busy,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> actions;
  final bool busy;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: PmaCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                backgroundColor: Pma.flame.withValues(alpha: 0.12),
                child: Icon(icon, color: Pma.ember),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Text(subtitle, style: const TextStyle(color: Pma.inkSoft, fontSize: 13)),
                ]),
              ),
              if (busy)
                const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ]),
        ),
      );
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job, required this.onReview});
  final PdfExtractionJob job;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: job,
        builder: (context, _) {
          final rows = job.pages.values.fold<int>(0, (n, p) => n + p.rows.length);
          final progress = job.pageCount == 0 ? 0.0 : (job.done + job.failures.length) / job.pageCount;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: PmaCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(job.fileName, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    color: Pma.flame,
                    backgroundColor: Pma.flame.withValues(alpha: 0.12),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  TrendPill(label: '${job.done}/${job.pageCount} pages read', color: Pma.good),
                  TrendPill(label: '$rows rows', color: Pma.ink),
                  if (job.failures.isNotEmpty)
                    TrendPill(label: '${job.failures.length} pages failed', color: Pma.bad),
                  if (job.running && job.current != null)
                    TrendPill(label: 'Reading page ${job.current}…', color: Pma.ember),
                ]),
                if (job.failures.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Failed: ${(job.failures.keys.toList()..sort()).join(', ')}',
                    style: const TextStyle(color: Pma.bad, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (job.running)
                    OutlinedButton(onPressed: job.cancel, child: const Text('Pause'))
                  else if (!job.complete)
                    OutlinedButton(onPressed: job.run, child: const Text('Resume')),
                  if (!job.running && job.failures.isNotEmpty)
                    OutlinedButton(
                      onPressed: () => job.run(retryFailed: true),
                      child: const Text('Retry failed pages'),
                    ),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Pma.ink, shape: const StadiumBorder()),
                    onPressed: job.running || job.pages.isEmpty ? null : onReview,
                    child: Text('Review $rows rows'),
                  ),
                ]),
              ]),
            ),
          );
        },
      );
}
