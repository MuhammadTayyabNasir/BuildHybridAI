import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/coach_service.dart';

class SaathiMark extends StatelessWidget {
  const SaathiMark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/saathi-mark.svg',
    width: size,
    height: size,
    excludeFromSemantics: true,
  );
}

class SaathiMascot extends StatelessWidget {
  const SaathiMascot({super.key, this.size = 140});

  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/saathi-mascot.svg',
    width: size,
    height: size,
    excludeFromSemantics: true,
  );
}

class SaathiCard extends StatelessWidget {
  const SaathiCard({super.key, required this.child, this.tinted = false});

  final Widget child;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tinted ? scheme.primaryContainer : scheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    );
  }
}

class SaathiAction extends StatelessWidget {
  const SaathiAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.secondary = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool secondary;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = icon == null
        ? Text(label, textAlign: TextAlign.center)
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Flexible(child: Text(label, textAlign: TextAlign.center)),
            ],
          );
    return SizedBox(
      width: double.infinity,
      child: secondary
          ? OutlinedButton(onPressed: onPressed, child: child)
          : FilledButton(onPressed: onPressed, child: child),
    );
  }
}

class SaathiPage extends StatelessWidget {
  const SaathiPage({
    super.key,
    required this.title,
    required this.body,
    required this.language,
    required this.onLanguageChanged,
    this.step,
    this.onBack,
  });

  final String title;
  final Widget body;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final int? step;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final urdu = language == AppLanguage.urdu;
    return Directionality(
      textDirection: urdu ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          leading: onBack == null
              ? const Padding(padding: EdgeInsets.all(12), child: SaathiMark())
              : IconButton(
                  onPressed: onBack,
                  tooltip: urdu ? 'واپس' : 'Back',
                  icon: const Icon(Icons.arrow_back),
                ),
          title: Text(
            urdu ? 'بل ساتھی' : 'Bill Saathi',
            style: theme.textTheme.titleMedium,
          ),
          actions: [
            PopupMenuButton<AppLanguage>(
              tooltip: urdu ? 'زبان تبدیل کریں' : 'Change language',
              onSelected: onLanguageChanged,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: AppLanguage.english,
                  child: Text('English'),
                ),
                PopupMenuItem(value: AppLanguage.urdu, child: Text('اردو')),
              ],
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 64, minHeight: 48),
                child: Center(
                  child: Text(
                    urdu ? 'اردو' : 'EN',
                    style: theme.textTheme.labelLarge,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                children: [
                  if (step != null) ...[
                    Text(
                      urdu ? 'مرحلہ $step از ۳' : 'Step $step of 3',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: step! / 3,
                      minHeight: 5,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    const SizedBox(height: 24),
                  ],
                  Text(title, style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 24),
                  body,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.ltrValue = false,
  });
  final String label;
  final String value;
  final bool ltrValue;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Directionality(
            textDirection: ltrValue
                ? TextDirection.ltr
                : Directionality.of(context),
            child: SelectableText(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
      ],
    ),
  );
}
