import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

enum Service {
  donations(
    'Donations',
    Icons.favorite_outline,
    'Edhi Foundation',
    'Choose a cause and amount on Edhi’s donation page.',
    'https://www.edhi.org/shop/donation-72',
  ),
  challans(
    'Punjab traffic challans',
    Icons.directions_car_outlined,
    'ePay Punjab',
    'Choose Punjab Police, then Traffic Challan. Have your challan slip ready.',
    'https://epay.punjab.gov.pk/',
  ),
  history('Payment history', Icons.receipt_long_outlined, '', '', '');

  const Service(this.title, this.icon, this.provider, this.help, this.url);
  final String title, provider, help, url;
  final IconData icon;
}

Service? resolveRequest(String query) {
  final q = query.toLowerCase();
  if (RegExp(
    r'last|recent|previous|history|receipt|when did|how much did',
  ).hasMatch(q)) {
    return Service.history;
  }
  if (RegExp(r'donat|charit|zakat|edhi|give money').hasMatch(q)) {
    return Service.donations;
  }
  if (RegExp(r'chall?an|traffic|driving fine|ticket').hasMatch(q)) {
    return Service.challans;
  }
  return null;
}

class Wallet extends StatefulWidget {
  const Wallet({super.key, required this.practice, this.interpret});
  final WidgetBuilder practice;
  final Future<Service?> Function(String)? interpret;
  @override
  State<Wallet> createState() => _WalletState();
}

class _WalletState extends State<Wallet> {
  final input = TextEditingController();
  String? reply;
  List<String> records = [];
  bool ready = false;
  bool resolving = false;
  String? unknown;
  final storage = SharedPreferencesAsync();
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final saved = await storage.getStringList('wallet.receipts') ?? [];
      if (mounted) {
        setState(() {
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
            'I can open donations, find Punjab traffic challans, or show your saved payments. Which do you need?',
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
      target = await widget.interpret?.call(query);
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
          ? 'Cloud help could not match this request. Choose a service below.'
          : null;
    });
    if (target != null) open(target);
  }

  void open(Service service) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(service.title)),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  if (service == Service.history) ...[
                    Text(
                      records.isEmpty
                          ? 'No receipts saved yet'
                          : 'Latest saved payment',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (records.isEmpty)
                      const Text(
                        'After paying with a provider, you can save the receipt details here.',
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
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () async {
                        try {
                          if (await launchUrl(
                            Uri.parse(service.url),
                            mode: LaunchMode.externalApplication,
                          )) {
                            return;
                          }
                        } catch (_) {}
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: SelectableText(
                                'Open ${service.url} in your browser.',
                              ),
                            ),
                          );
                        }
                      },
                      child: Text('Open ${service.provider}'),
                    ),
                    OutlinedButton(
                      onPressed: ready
                          ? () => saveReceipt(context, service)
                          : null,
                      child: const Text('Save a completed payment'),
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

  Widget receipt(String entry) {
    final row = jsonDecode(entry) as List;
    return ListTile(
      leading: const Icon(Icons.receipt_outlined),
      title: Text(row[0] as String),
      subtitle: Text('Manually saved · ${row[2]}'),
      trailing: Text('Rs ${row[1]}'),
    );
  }

  Future<void> saveReceipt(BuildContext page, Service service) async {
    String amount = '';
    final value = await showDialog<String>(
      context: page,
      builder: (ctx) => AlertDialog(
        title: const Text('Record your payment'),
        content: TextField(
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount paid in PKR'),
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
                  double.parse(amount) > 0) {
                Navigator.pop(ctx, amount);
              } else {
                ScaffoldMessenger.of(page).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Enter a positive amount with up to two decimal places.',
                    ),
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null || !page.mounted) return;
    final updated = [
      jsonEncode([
        service.provider,
        value,
        DateTime.now().toLocal().toString().split(' ').first,
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
                    if (unknown?.isNotEmpty == true && widget.interpret != null)
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        onPressed: resolving ? null : askCloud,
                        child: Text(
                          resolving
                              ? 'Finding service…'
                              : 'Send request to cloud AI',
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
