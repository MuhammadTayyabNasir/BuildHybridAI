import 'package:flutter/material.dart';

import '../../ui/pma_ui.dart';
import '../analytics/insights_screen.dart';
import '../assistant/assistant_screen.dart';
import '../dashboard/dashboard_screen.dart';
import 'today_screen.dart';

/// Signed-in home: Today, the voice assistant, AI insights and the full
/// section / admin tools, switched by a floating pill bar.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// Keeps the pages (and an open assistant conversation) alive when the
  /// window crosses the phone/desktop breakpoint.
  final _stackKey = GlobalKey();

  static const _items = [
    PillNavItem(Icons.home_rounded, 'Today'),
    PillNavItem(Icons.mic_rounded, 'Assistant'),
    PillNavItem(Icons.insights_rounded, 'Insights'),
    PillNavItem(Icons.grid_view_rounded, 'Sections'),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      TodayScreen(onAsk: () => setState(() => _index = 1)),
      const AssistantScreen(),
      const InsightsScreen(),
      const DashboardScreen(),
    ];
    void go(int i) => setState(() => _index = i);
    final wide = MediaQuery.sizeOf(context).width >= pmaWideBreakpoint;
    if (wide) {
      return Scaffold(
        backgroundColor: Pma.canvas,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PillNavRail(items: _items, index: _index, onTap: go),
            Expanded(
              child: PmaFrame(
                maxWidth: 1180,
                child: IndexedStack(
                  key: _stackKey,
                  index: _index,
                  children: pages,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: Pma.canvas,
      body: IndexedStack(key: _stackKey, index: _index, children: pages),
      bottomNavigationBar: PillNavBar(items: _items, index: _index, onTap: go),
    );
  }
}
