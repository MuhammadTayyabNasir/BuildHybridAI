import 'dart:convert';
import 'voice_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'bank_card.dart';

enum Service {
  donations(
    'Donations',
    Icons.favorite_outline,
    'Edhi Foundation',
    'Choose an amount for a simulated donation.',
    'https://www.edhi.org/shop/donation-72',
  ),
  challans(
    'Punjab traffic challans',
    Icons.directions_car_outlined,
    'ePay Punjab',
    'Demo challan · Punjab Traffic Police',
    'https://epay.punjab.gov.pk/',
  ),
  account('My account', Icons.account_balance_wallet_outlined, '', '', ''),
  transfer(
    'Send money',
    Icons.north_east,
    'Ayesha Khan',
    'Send from your demo current account to your saved contact.',
    '',
  ),
  card('My card', Icons.credit_card, '', '', ''),
  history('Payment history', Icons.receipt_long_outlined, '', '', '');

  const Service(this.title, this.icon, this.provider, this.help, this.url);
  final String title, provider, help, url;
  final IconData icon;
}

Service? resolveRequest(String query) {
  final q = query.toLowerCase();
  if (RegExp(
    r'last|recent|previous|history|receipt|when did|how much did|پچھل|آخری|رسید|ہسٹری|تاریخچہ|ادائیگیوں|pich[hl]|akhri|raseed',
  ).hasMatch(q)) {
    return Service.history;
  }
  if (RegExp(
    r'donat|charit|zakat|edhi|give money|عطیہ|عطیات|عطیہ|چندہ|صدقہ|زکو|زکا|ایدھی|خیرات|ڈونیٹ|chanda|sadqa|atiya',
  ).hasMatch(q)) {
    return Service.donations;
  }
  if (RegExp(
    r'chall?an|traffic|driving fine|ticket|چالان|ٹریفک|جرمانہ|jurmana',
  ).hasMatch(q)) {
    return Service.challans;
  }
  if (RegExp(r'balance|account|بیلنس|اکاؤنٹ|کھاتہ|رقم کتنی').hasMatch(q)) {
    return Service.account;
  }
  if (RegExp(r'transfer|send money|bhej|بھیج|ٹرانسفر').hasMatch(q)) {
    return Service.transfer;
  }
  if (RegExp(r'card|freeze|کارڈ').hasMatch(q)) return Service.card;
  return null;
}

class Wallet extends StatefulWidget {
  const Wallet({super.key, required this.practice, this.publicGuide});
  final WidgetBuilder practice;
  final Future<String?> Function(Service)? publicGuide;
  @override
  State<Wallet> createState() => _WalletState();
}

class _WalletState extends State<Wallet> {
  final input = TextEditingController();
  String? reply;
  List<String> records = [];
  bool ready = false;
  bool frozen = false;
  bool saving = false;
  int get balance => records
      .map((r) => jsonDecode(r) as List)
      .where((r) => r.length > 3 && r[3] == 'debit')
      .fold<int>(
        5000000,
        (sum, r) => sum - (double.parse(r[1].toString()) * 100).round(),
      );
  String get balanceText => 'Rs ${(balance / 100).toStringAsFixed(2)}';
  bool get supportsLocalModel =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool resolving = false;
  String? unknown;
  late final storage = SharedPreferencesAsync();
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final saved = await storage.getStringList('wallet.receipts') ?? [];
      final cardFrozen = await storage.getBool("wallet.frozen") ?? false;
      if (mounted) {
        setState(() {
          frozen = cardFrozen;
          records = saved;
          ready = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => reply = 'Saved receipts could not be loaded.');
      }
    }
  }

  @override
  void dispose() {
    live.dispose();
    input.dispose();
    super.dispose();
  }

  void ask() {
    unknown = null;
    final target = resolveRequest(input.text);
    if (target == null) {
      unknown = input.text.trim();
      setState(
        () => reply =
            'Try balance, transfers, cards, donations, Punjab challans, or payment history.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    input.clear();
    setState(() => reply = null);
    open(target);
  }

  Future<void> askCloud() async {
    final query = unknown;
    if (query == null || query.isEmpty || resolving) return;
    setState(() => resolving = true);
    Service? target;
    try {
      final name = await const MethodChannel('bill_saathi/on_device')
          .invokeMethod<String>('walletIntent', {'request': query})
          .timeout(const Duration(seconds: 20));
      target = Service.values
          .where((s) => s.name == name?.trim().toLowerCase())
          .firstOrNull;
    } catch (_) {}
    if (!mounted) return;
    setState(() => resolving = false);
    if (input.text.trim() != query ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    setState(() {
      unknown = null;
      reply = target == null
          ? 'On-device help could not match this request. Choose a service below.'
          : null;
    });
    if (target != null) open(target);
  }

  final live = LiveVoice();
  String voiceRequest(String words, bool inUrdu, {BuildContext? page}) {
    final target = resolveRequest(words);
    if (target == null) {
      if (page != null) Navigator.pop(page);
      input.text = words;
      ask();
      return inUrdu
          ? 'درخواست سمجھ نہیں آئی۔ آپ لکھ کر بھی پوچھ سکتے ہیں۔'
          : 'Please edit your request or choose a service.';
    }
    if (page != null) Navigator.pop(page);
    open(target);
    return inUrdu
        ? switch (target) {
            Service.account => 'اکاؤنٹ کھول دیا ہے۔',
            Service.transfer => 'رقم بھیجنے کا صفحہ کھول دیا ہے۔',
            Service.card => 'کارڈ کا صفحہ کھول دیا ہے۔',
            Service.donations => 'عطیات کا صفحہ کھول دیا ہے۔',
            Service.challans => 'پنجاب ٹریفک چالان کا صفحہ کھول دیا ہے۔',
            Service.history => 'ادائیگیوں کی تفصیل کھول دی ہے۔',
          }
        : 'Opened ${target.title}.';
  }

  void open(Service service) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(service.title)),
          bottomNavigationBar: SafeArea(
            child: VoiceBar(
              live: live,
              onRequest: (words, language) =>
                  voiceRequest(words, language, page: context),
            ),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  if (service == Service.account ||
                      service == Service.card) ...[
                    BankCardFace(
                      card: service == Service.card,
                      amount: ready ? balanceText : '—',
                      frozen: frozen,
                    ),
                    const SizedBox(height: 24),
                    if (service == Service.account)
                      ListTile(
                        title: const Text('Account activity'),
                        trailing: const Icon(Icons.arrow_forward),
                        onTap: () {
                          Navigator.pop(context);
                          open(Service.history);
                        },
                      )
                    else
                      FilledButton.icon(
                        icon: Icon(
                          frozen ? Icons.lock_open : Icons.lock_outline,
                        ),
                        label: Text(
                          frozen ? 'Unfreeze demo card' : 'Freeze demo card',
                        ),
                        onPressed: !ready
                            ? null
                            : () async {
                                if (saving) return;
                                saving = true;
                                final value = !frozen;
                                try {
                                  await storage.setBool('wallet.frozen', value);
                                  if (!mounted) return;
                                  setState(() => frozen = value);
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    open(Service.card);
                                  }
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Could not update card.'),
                                      ),
                                    );
                                  }
                                } finally {
                                  saving = false;
                                }
                              },
                      ),
                  ] else if (service == Service.history) ...[
                    Text(
                      records.isEmpty
                          ? 'No receipts saved yet'
                          : 'Latest saved payment',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (records.isEmpty)
                      const Text(
                        'Your confirmed demo payments will appear here.',
                      ),
                    if (records.isNotEmpty)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.insights),
                        label: const Text('Explain my activity privately'),
                        onPressed: () => explainActivity(context),
                      ),
                    ...records.map(receipt),
                  ] else ...[
                    Icon(service.icon, size: 64),
                    const SizedBox(height: 24),
                    Text(
                      service.provider,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text(service.help),
                    if (widget.publicGuide != null)
                      TextButton.icon(
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Explain this service online'),
                        onPressed: () async {
                          final guide = await widget.publicGuide!(service);
                          if (context.mounted) {
                            showDialog<void>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text(service.title),
                                content: Text(guide ?? service.help),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('Done'),
                                  ),
                                ],
                              ),
                            );
                          }
                        },
                      ),
                    const SizedBox(height: 24),
                    BankCardFace(
                      card: false,
                      amount: ready ? balanceText : '—',
                      frozen: frozen,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: ready
                          ? () => saveReceipt(context, service)
                          : null,
                      child: Text(
                        service == Service.transfer
                            ? 'Send to Ayesha'
                            : 'Make demo payment',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> explainActivity(BuildContext page) async {
    final debits = records
        .map((entry) => jsonDecode(entry) as List)
        .where((r) => r.length > 3 && r[3] == 'debit')
        .toList();
    final total = ((5000000 - balance) / 100).toStringAsFixed(2);
    final facts =
        'Demo payments: ${debits.length}. Total spent: Rs $total. Remaining balance: $balanceText.';
    final explanation = () async {
      if (!supportsLocalModel) return facts;
      try {
        final text = await const MethodChannel('bill_saathi/on_device')
            .invokeMethod<String>('activitySummary', {'facts': facts})
            .timeout(const Duration(seconds: 20));
        if (text != null && text.trim().isNotEmpty) {
          return '$facts\n\nOn-device explanation\n$text';
        }
      } catch (_) {}
      return facts;
    }();
    await showDialog<void>(
      context: page,
      builder: (ctx) => AlertDialog(
        title: const Text('Private activity summary'),
        content: FutureBuilder<String>(
          future: explanation,
          builder: (_, snapshot) => Text(
            snapshot.data ?? '$facts\n\nPreparing your on-device explanation…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget receipt(String entry) {
    final row = jsonDecode(entry) as List;
    return ListTile(
      leading: const Icon(Icons.receipt_outlined),
      title: Text(row[0] as String),
      subtitle: Text(
        '${row.length > 3 ? 'Demo payment' : 'Manually saved'} · ${row[2]}',
      ),
      trailing: Text('Rs ${row[1]}'),
    );
  }

  Future<void> saveReceipt(BuildContext page, Service service) async {
    String amount = '';
    final value = await showDialog<String>(
      context: page,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter demo payment'),
        content: TextField(
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount in PKR'),
          onChanged: (v) => amount = v.trim(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (RegExp(r'^\d{1,9}(\.\d{1,2})?$').hasMatch(amount) &&
                  double.parse(amount) > 0 &&
                  (double.parse(amount) * 100).round() <= balance) {
                Navigator.pop(ctx, amount);
              } else {
                ScaffoldMessenger.of(page).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Enter a positive amount within your available balance.',
                    ),
                  ),
                );
              }
            },
            child: const Text('Review'),
          ),
        ],
      ),
    );
    if (value == null || !page.mounted) return;
    final confirmed = await showDialog<bool>(
      context: page,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm demo payment'),
        content: Text('Send Rs $value to ${service.provider}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !page.mounted ||
        saving ||
        (double.parse(value) * 100).round() > balance) {
      return;
    }
    saving = true;
    final updated = [
      jsonEncode([
        service.provider,
        value,
        DateTime.now().toLocal().toString().split(' ').first,
        'debit',
      ]),
      ...records,
    ];
    try {
      await storage.setStringList('wallet.receipts', updated);
    } catch (_) {
      if (page.mounted) {
        ScaffoldMessenger.of(page).showSnackBar(
          const SnackBar(content: Text('Could not save this receipt.')),
        );
      }
      return;
    } finally {
      saving = false;
    }
    if (!mounted) return;
    setState(() => records = updated);
    if (page.mounted) {
      Navigator.pop(page);
      open(Service.history);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xfffffbf7),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  SvgPicture.asset('assets/saathi-mark.svg', width: 32),
                  const SizedBox(width: 10),
                  const Text(
                    'Saathi Wallet',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xff45101c),
                      Color(0xff9c3018),
                      Color(0xffbd5520),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: SvgPicture.asset(
                        'assets/saathi-mascot.svg',
                        height: 94,
                      ),
                    ),
                    const Text(
                      'Ask Buddy',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: input,
                      onSubmitted: (_) => ask(),
                      textInputAction: TextInputAction.send,
                      style: const TextStyle(color: Colors.black),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintStyle: const TextStyle(color: Colors.black54),
                        hintText: 'What would you like to do?',
                        suffixIcon: IconButton(
                          tooltip: 'Send request',
                          icon: const Icon(
                            Icons.arrow_upward,
                            color: Colors.black,
                          ),
                          onPressed: ask,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                    if (supportsLocalModel && unknown?.isNotEmpty == true)
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        onPressed: resolving ? null : askCloud,
                        child: Text(
                          resolving
                              ? 'Finding service…'
                              : 'Interpret on device',
                        ),
                      ),
                    if (reply != null)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          reply!,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
              BankCardFace(
                card: false,
                amount: ready ? balanceText : "—",
                frozen: frozen,
              ),
              VoiceBar(live: live, onRequest: voiceRequest),
              const SizedBox(height: 28),
              const Text(
                'Services',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              ...Service.values.map(
                (s) => Card(
                  color: s == Service.donations
                      ? const Color(0xffede4fa)
                      : Colors.white,
                  child: ListTile(
                    textColor: Colors.black,
                    iconColor: Colors.black,
                    leading: Icon(s.icon),
                    title: Text(s.title),
                    trailing: const Icon(Icons.north_east),
                    onTap: () => open(s),
                  ),
                ),
              ),
              if (records.isNotEmpty) Card(child: receipt(records.first)),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: widget.practice),
                ),
                child: const Text('Bill practice guide'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
