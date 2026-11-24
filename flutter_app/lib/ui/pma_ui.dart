import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// PMA visual language: warm red-orange gradient heroes, big numbers with
/// small trend pills, rounded white cards, a floating pill navigation bar and
/// charts with dark tooltip bubbles.
class Pma {
  Pma._();

  static const ink = Color(0xFF1C1A1F);
  static const inkSoft = Color(0xFF6E6872);
  static const canvas = Color(0xFFF6F3F1);
  static const card = Colors.white;
  static const flame = Color(0xFFFF6A3D);
  static const ember = Color(0xFFE8431F);
  static const sun = Color(0xFFFFA24C);
  static const good = Color(0xFF2FA866);
  static const warn = Color(0xFFF0A202);
  static const bad = Color(0xFFE5383B);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFA24C), Color(0xFFFF6A3D), Color(0xFFE8431F)],
  );

  static const radius = 24.0;

  static List<BoxShadow> softShadow = const [
    BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 10)),
  ];

  static Color status(String s) => switch (s) {
    'green' => good,
    'yellow' => warn,
    'red' => bad,
    _ => inkSoft,
  };
}

/// Rounded gradient header with soft decorative circles.
class GradientHero extends StatelessWidget {
  const GradientHero({super.key, required this.child, this.bottomRadius = 32});
  final Widget child;
  final double bottomRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.vertical(
        bottom: Radius.circular(bottomRadius),
      ),
      child: Container(
        decoration: const BoxDecoration(gradient: Pma.heroGradient),
        child: Stack(
          children: [
            Positioned(
              right: -40,
              top: -30,
              child: _Orb(size: 180, alpha: 0.18),
            ),
            Positioned(
              left: -50,
              bottom: -70,
              child: _Orb(size: 200, alpha: 0.12),
            ),
            SafeArea(bottom: false, child: child),
          ],
        ),
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.size, required this.alpha});
  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: alpha),
    ),
  );
}

/// Small rounded pill showing a change, e.g. "+12%" or "2 missed".
class TrendPill extends StatelessWidget {
  const TrendPill({
    super.key,
    required this.label,
    this.up,
    this.color,
    this.onDark = false,
  });
  final String label;
  final bool? up;
  final Color? color;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final c =
        color ??
        (up == null
            ? Pma.inkSoft
            : up!
            ? Pma.good
            : Pma.bad);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: onDark
            ? Colors.white.withValues(alpha: 0.22)
            : c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (up != null)
            Icon(
              up! ? Icons.north_east : Icons.south_east,
              size: 12,
              color: onDark ? Colors.white : c,
            ),
          if (up != null) const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: onDark ? Colors.white : c,
            ),
          ),
        ],
      ),
    );
  }
}

/// Big number with a caption and an optional trend pill.
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.value,
    required this.caption,
    this.pill,
    this.onDark = false,
    this.icon,
  });
  final String value;
  final String caption;
  final Widget? pill;
  final bool onDark;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white : Pma.ink;
    final sub = onDark ? Colors.white70 : Pma.inkSoft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: sub),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                caption,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: sub,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 30,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: fg,
                letterSpacing: -0.5,
              ),
            ),
            if (pill != null) ...[const SizedBox(width: 8), pill!],
          ],
        ),
      ],
    );
  }
}

/// Rounded white card.
class PmaCard extends StatelessWidget {
  const PmaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.color,
  });
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: color ?? (dark ? const Color(0xFF26222A) : Pma.card),
      borderRadius: BorderRadius.circular(Pma.radius),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(Pma.radius),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Pma.radius),
            boxShadow: dark ? null : Pma.softShadow,
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// Frosted glass panel for content layered over the gradient hero.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Pma.radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(Pma.radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class PillNavItem {
  const PillNavItem(this.icon, this.label);
  final IconData icon;
  final String label;
}

/// Floating pill bottom navigation with a dark circle behind the active icon.
class PillNavBar extends StatelessWidget {
  const PillNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onTap,
  });
  final List<PillNavItem> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Container(
          height: 66,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(40),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 28,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < items.length; i++)
                Semantics(
                  button: true,
                  selected: i == index,
                  label: items[i].label,
                  child: InkResponse(
                    onTap: () => onTap(i),
                    radius: 32,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == index ? Pma.ink : Colors.transparent,
                      ),
                      child: Icon(
                        items[i].icon,
                        color: i == index ? Colors.white : Pma.inkSoft,
                        size: 24,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Width at which PMA switches from the phone layout (bottom pill bar) to
/// the desktop layout (side rail).
const pmaWideBreakpoint = 900.0;

/// Desktop navigation: the same pill look, standing up on the left, with the
/// PMA mark on top.
class PillNavRail extends StatelessWidget {
  const PillNavRail({
    super.key,
    required this.items,
    required this.index,
    required this.onTap,
  });
  final List<PillNavItem> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 0, 16),
    child: Container(
      width: 96,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(40),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      // Scrolls in short windows so every item stays reachable.
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 18),
            Image.asset(
              'assets/images/pma_mark.png',
              width: 56,
              semanticLabel: 'PMA',
            ),
            const SizedBox(height: 4),
            const Text(
              'PMA',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Pma.ink,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 24),
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Semantics(
                  button: true,
                  selected: i == index,
                  label: items[i].label,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => onTap(i),
                    child: SizedBox(
                      width: 80,
                      child: Column(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i == index ? Pma.ink : Colors.transparent,
                            ),
                            child: Icon(
                              items[i].icon,
                              color: i == index ? Colors.white : Pma.inkSoft,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            items[i].label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: i == index
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: i == index ? Pma.ink : Pma.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );
}

/// Keeps pages readable on big screens: content is centered and capped at
/// [maxWidth]; on phones it is a no-op.
class PmaFrame extends StatelessWidget {
  const PmaFrame({super.key, required this.child, this.maxWidth = 1180});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Pma.canvas,
    child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    ),
  );
}

/// Smooth area chart with a dark tooltip bubble.
class AreaTrendChart extends StatelessWidget {
  const AreaTrendChart({
    super.key,
    required this.values,
    required this.labels,
    this.color = Pma.flame,
    this.unit = '',
    this.height = 160,
  });
  final List<double> values;
  final List<String> labels;
  final Color color;
  final String unit;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text('No data yet', style: TextStyle(color: Pma.inkSoft)),
        ),
      );
    }
    final maxY = values.reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY <= 0 ? 1 : maxY * 1.25,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: 1,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= labels.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      labels[i],
                      style: const TextStyle(fontSize: 10, color: Pma.inkSoft),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => Pma.ink,
              tooltipRoundedRadius: 12,
              getTooltipItems: (spots) => spots
                  .map(
                    (s) => LineTooltipItem(
                      '${s.y.toStringAsFixed(s.y % 1 == 0 ? 0 : 1)}$unit',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < values.length; i++)
                  FlSpot(i.toDouble(), values[i]),
              ],
              isCurved: true,
              curveSmoothness: 0.3,
              color: color,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                checkToShowDot: (s, _) => s.x == values.length - 1,
                getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                  radius: 5,
                  color: Colors.white,
                  strokeWidth: 3,
                  strokeColor: color,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    color.withValues(alpha: 0.35),
                    color.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded bars with the highlighted bar in the accent colour.
class RoundedBarChart extends StatelessWidget {
  const RoundedBarChart({
    super.key,
    required this.values,
    required this.labels,
    this.highlight,
    this.unit = '',
    this.height = 170,
  });
  final List<double> values;
  final List<String> labels;
  final int? highlight;
  final String unit;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return SizedBox(height: height);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final hi = highlight ?? values.length - 1;
    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: maxY <= 0 ? 1 : maxY * 1.2,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= labels.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      labels[i],
                      style: const TextStyle(fontSize: 10, color: Pma.inkSoft),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => Pma.ink,
              tooltipRoundedRadius: 12,
              getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                '${rod.toY.toStringAsFixed(rod.toY % 1 == 0 ? 0 : 1)}$unit',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < values.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: values[i],
                    width: 22,
                    borderRadius: BorderRadius.circular(10),
                    gradient: i == hi
                        ? const LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Pma.ember, Pma.sun],
                          )
                        : null,
                    color: i == hi ? null : const Color(0xFFF1E6E1),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
