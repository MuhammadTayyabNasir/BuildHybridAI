import 'package:flutter/material.dart';

class BankCardFace extends StatelessWidget {
  const BankCardFace({
    super.key,
    required this.card,
    required this.amount,
    required this.frozen,
  });
  final bool card, frozen;
  final String amount;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 12),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: card
            ? [
                const Color(0xff272137),
                const Color(0xff43325c),
                const Color(0xff574469),
              ]
            : [
                const Color(0xffeadbff),
                const Color(0xffeee8ff),
                const Color(0xfff8dce1),
              ],
      ),
    ),
    child: DefaultTextStyle(
      style: TextStyle(color: card ? Colors.white : const Color(0xff352641)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(card ? 'SAATHI  /  DEBIT' : 'DEMO CURRENT ACCOUNT'),
              ),
              Icon(
                card ? Icons.contactless_outlined : Icons.account_balance,
                color: card ? Colors.white : const Color(0xff352641),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text(
            card ? '••••   ••••   ••••   2048' : amount,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Text(
            card
                ? (frozen ? 'Card frozen' : 'Card active')
                : 'Available balance · PKR',
          ),
        ],
      ),
    ),
  );
}
