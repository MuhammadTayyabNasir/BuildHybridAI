import 'package:flutter/material.dart';

import '../core/coach_service.dart';
import '../core/reference_validator.dart';
import '../core/sample_bill.dart';
import 'saathi_theme.dart';
import 'saathi_widgets.dart';

class BillSaathiApp extends StatelessWidget {
  const BillSaathiApp({super.key, required this.coach});
  final CoachService coach;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bill Saathi',
    debugShowCheckedModeBanner: false,
    theme: saathiTheme(Brightness.light),
    darkTheme: saathiTheme(Brightness.dark),
    home: _PracticeFlow(coach: coach),
  );
}

enum _Page { home, addBill, reference, assistant, review, complete }

class _PracticeFlow extends StatefulWidget {
  const _PracticeFlow({required this.coach});
  final CoachService coach;
  @override
  State<_PracticeFlow> createState() => _PracticeFlowState();
}

class _PracticeFlowState extends State<_PracticeFlow> {
  final _controller = TextEditingController();
  final _validator = const ReferenceValidator();
  _Page _page = _Page.home;
  AppLanguage _language = AppLanguage.english;
  ReferenceIssue? _issue;
  HelpReply? _reply;
  HelpTopic _topic = HelpTopic.findReference;
  bool _loading = false;

  bool get _urdu => _language == AppLanguage.urdu;
  String _t(String en, String ur) => _urdu ? ur : en;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(_Page page) => setState(() => _page = page);

  void _back() => _go(switch (_page) {
    _Page.home || _Page.addBill => _Page.home,
    _Page.reference => _Page.addBill,
    _Page.assistant || _Page.review => _Page.reference,
    _Page.complete => _Page.home,
  });

  void _validate() {
    final result = _validator.validate(_controller.text);
    setState(() {
      _issue = result.issue;
      if (result.isValid) _page = _Page.review;
    });
  }

  void _openHelp() => setState(() {
    _topic = _issue == ReferenceIssue.meterNumber
        ? HelpTopic.meterIsDifferent
        : HelpTopic.findReference;
    _reply = widget.coach.reviewedHint(_topic, _language);
    _page = _Page.assistant;
  });

  Future<void> _askAi() async {
    setState(() => _loading = true);
    final reply = await widget.coach.explain(_topic, _language);
    if (!mounted) return;
    setState(() {
      _reply = reply;
      _loading = false;
    });
  }

  Future<void> _askOnDevice() async {
    setState(() => _loading = true);
    final reply = await widget.coach.explainOnDevice(_topic, _language);
    if (!mounted) return;
    setState(() {
      _reply = reply;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) => SaathiPage(
    key: ValueKey(_page),
    title: switch (_page) {
      _Page.home => _t('Pay with confidence', 'اعتماد کے ساتھ بل کی مشق کریں'),
      _Page.addBill => _t('Add a sample bill', 'نمونہ بل شامل کریں'),
      _Page.reference => _t('Find the right number', 'درست نمبر تلاش کریں'),
      _Page.assistant => _t('Let’s find it together', 'آئیے ساتھ تلاش کریں'),
      _Page.review => _t(
        'Review the practice payment',
        'مشق کی ادائیگی کی تفصیلات دیکھیں',
      ),
      _Page.complete => _t('Practice complete', 'مشق مکمل ہوئی'),
    },
    body: switch (_page) {
      _Page.home => _home(),
      _Page.addBill => _addBill(),
      _Page.reference => _reference(),
      _Page.assistant => _assistant(),
      _Page.review => _review(),
      _Page.complete => _complete(),
    },
    language: _language,
    onLanguageChanged: (language) => setState(() {
      _language = language;
      if (_page == _Page.assistant) {
        _reply = widget.coach.reviewedHint(_topic, language);
      }
    }),
    step: switch (_page) {
      _Page.addBill => 1,
      _Page.reference || _Page.assistant => 2,
      _Page.review => 3,
      _ => null,
    },
    onBack: _page == _Page.home ? null : _back,
  );

  Widget _home() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SaathiCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('Practice electricity bill', 'بجلی کے بل کی مشق'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              _t(
                'Find the payment reference and check every detail before you confirm.',
                'ادائیگی کا حوالہ نمبر تلاش کریں اور تصدیق سے پہلے تمام تفصیلات دیکھیں۔',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      SaathiAction(
        label: _t('Start practice', 'مشق شروع کریں'),
        icon: Icons.arrow_forward,
        onPressed: () => _go(_Page.addBill),
      ),
      const SizedBox(height: 18),
      SaathiCard(
        tinted: true,
        child: Row(
          children: [
            const SaathiMascot(size: 96),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t('Saathi can guide you', 'ساتھی آپ کی رہنمائی کرے گا'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _t(
                      'Short hints in English or Urdu. You make every decision.',
                      'انگریزی یا اردو میں مختصر رہنمائی۔ ہر فیصلہ آپ خود کریں گے۔',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      _demoNotice(),
    ],
  );

  Widget _addBill() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        _t(
          'Start with a fictional bill so you can learn the steps safely.',
          'طریقہ محفوظ انداز میں سیکھنے کے لیے فرضی بل سے شروع کریں۔',
        ),
      ),
      const SizedBox(height: 18),
      _billCard(highlight: false),
      const SizedBox(height: 20),
      SaathiAction(
        label: _t('Use this sample bill', 'یہ نمونہ بل استعمال کریں'),
        onPressed: () => _go(_Page.reference),
      ),
      const SizedBox(height: 18),
      _demoNotice(),
    ],
  );

  Widget _reference() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _billCard(highlight: _issue != null),
      const SizedBox(height: 20),
      TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        textDirection: TextDirection.ltr,
        maxLength: 20,
        decoration: InputDecoration(
          labelText: _t('Payment reference', 'ادائیگی کا حوالہ نمبر'),
          hintText: _t('Enter 14 digits', '۱۴ ہندسے درج کریں'),
          errorText: _errorText(),
          helperText: _t(
            'Use Payment Reference, not Meter Number.',
            'میٹر نمبر کے بجائے Payment Reference لکھیں۔',
          ),
        ),
        onChanged: (_) {
          if (_issue != null) setState(() => _issue = null);
        },
        onSubmitted: (_) => _validate(),
      ),
      const SizedBox(height: 12),
      SaathiAction(
        label: _t('Review details', 'تفصیلات دیکھیں'),
        onPressed: _validate,
      ),
      const SizedBox(height: 12),
      SaathiAction(
        label: _t('Show me on the bill', 'بل پر دکھائیں'),
        icon: Icons.help_outline,
        secondary: true,
        onPressed: _openHelp,
      ),
    ],
  );

  String? _errorText() => switch (_issue) {
    null => null,
    ReferenceIssue.empty => _t(
      'Enter the Payment Reference shown on the sample bill.',
      'نمونہ بل پر دیا گیا Payment Reference درج کریں۔',
    ),
    ReferenceIssue.meterNumber => _t(
      'That is the meter number. Use Payment Reference instead.',
      'یہ میٹر نمبر ہے۔ اس کی جگہ Payment Reference درج کریں۔',
    ),
    ReferenceIssue.wrongLength => _t(
      'The sample Payment Reference has 14 digits.',
      'نمونہ Payment Reference میں ۱۴ ہندسے ہیں۔',
    ),
    ReferenceIssue.notSampleReference => _t(
      'These digits do not match the sample bill. Check each digit.',
      'یہ ہندسے نمونہ بل سے نہیں ملتے۔ ہر ہندسہ دوبارہ دیکھیں۔',
    ),
  };

  Widget _assistant() {
    final reply = _reply ?? widget.coach.reviewedHint(_topic, _language);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SaathiCard(
          tinted: true,
          child: Row(
            children: [
              const SaathiMascot(size: 80),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _t(
                    'A short hint, then you decide.',
                    'مختصر رہنمائی، پھر فیصلہ آپ کا۔',
                  ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _billCard(highlight: true),
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: SaathiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t(
                    'Look beside “Payment Reference”',
                    '“Payment Reference” کے ساتھ دیکھیں',
                  ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Text(reply.text),
                const SizedBox(height: 12),
                Text(switch (reply.source) {
                  HelpSource.cloudAi => _t(
                    'Source: Gemini cloud explanation',
                    'ماخذ: Gemini کلاؤڈ وضاحت',
                  ),
                  HelpSource.onDeviceAi => 'Source: Gemini on this device',
                  HelpSource.reviewedGuide => _t(
                    'Source: built-in guide',
                    'ماخذ: نظرثانی شدہ رہنمائی',
                  ),
                }, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (widget.coach.localTextGenerator != null && !_urdu) ...[
          SaathiAction(
            label: _loading
                ? 'Checking local model…'
                : 'Explain on this device',
            secondary: true,
            onPressed: _loading ? null : _askOnDevice,
          ),
          const SizedBox(height: 12),
        ],
        if (widget.coach.cloudTextGenerator != null) ...[
          SaathiAction(
            label: _loading
                ? _t('Getting explanation…', 'وضاحت حاصل کی جا رہی ہے…')
                : _t('Explain with Gemini', 'Gemini سے وضاحت لیں'),
            secondary: true,
            onPressed: _loading ? null : _askAi,
          ),
          const SizedBox(height: 12),
        ],
        SaathiAction(
          label: _t('Return to reference', 'حوالہ نمبر پر واپس جائیں'),
          onPressed: () => _go(_Page.reference),
        ),
      ],
    );
  }

  Widget _review() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SaathiCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _t('Payment details', 'ادائیگی کی تفصیلات'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            DetailRow(
              label: _t('Provider', 'ادارہ'),
              value: SampleBill.provider,
            ),
            const DetailRow(
              label: 'Reference',
              value: SampleBill.reference,
              ltrValue: true,
            ),
            const DetailRow(
              label: 'Amount',
              value: 'PKR 4,280',
              ltrValue: true,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _demoNotice(),
      const SizedBox(height: 20),
      SaathiAction(
        label: _t('Confirm practice payment', 'مشق کی ادائیگی کی تصدیق کریں'),
        onPressed: () => _go(_Page.complete),
      ),
      const SizedBox(height: 12),
      SaathiAction(
        label: _t('Edit reference', 'حوالہ نمبر بدلیں'),
        secondary: true,
        onPressed: () => _go(_Page.reference),
      ),
    ],
  );

  Widget _complete() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SaathiCard(
        tinted: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle_outline, size: 48),
            const SizedBox(height: 12),
            Text(
              _t('No payment was sent', 'کوئی ادائیگی نہیں بھیجی گئی'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              _t(
                'You found the reference and reviewed the sample payment yourself.',
                'آپ نے حوالہ نمبر تلاش کیا اور نمونہ ادائیگی کی تفصیلات خود دیکھیں۔',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      SaathiCard(
        child: Column(
          children: [
            DetailRow(
              label: _t('Provider', 'ادارہ'),
              value: SampleBill.provider,
            ),
            const DetailRow(
              label: 'Amount',
              value: 'PKR 4,280',
              ltrValue: true,
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      SaathiAction(
        label: _t('Back to home', 'ابتدائی صفحے پر جائیں'),
        onPressed: () {
          _controller.clear();
          setState(() {
            _issue = null;
            _page = _Page.home;
          });
        },
      ),
    ],
  );

  Widget _demoNotice() => SaathiCard(
    tinted: true,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _t(
              'Demo only. This is a fictional bill; no money moves.',
              'صرف مشق کے لیے۔ یہ فرضی بل ہے، کوئی رقم منتقل نہیں ہوتی۔',
            ),
          ),
        ),
      ],
    ),
  );

  Widget _billCard({required bool highlight}) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: _t('Fictional sample electricity bill', 'بجلی کا فرضی نمونہ بل'),
      child: SaathiCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'SAMPLE — NO PAYMENT DUE',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Text(
              SampleBill.provider,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(height: 26),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: highlight ? scheme.primary : scheme.outline,
                  width: highlight ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payment Reference',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 5),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: SelectableText(
                        SampleBill.reference,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const DetailRow(
              label: 'Meter Number',
              value: SampleBill.meter,
              ltrValue: true,
            ),
            const DetailRow(
              label: 'Amount Due',
              value: 'PKR 4,280',
              ltrValue: true,
            ),
          ],
        ),
      ),
    );
  }
}
