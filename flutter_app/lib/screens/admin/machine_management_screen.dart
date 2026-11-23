import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/sections.dart';
import '../../models/machine_model.dart';
import '../../providers/machines_provider.dart';

class MachineManagementScreen extends StatefulWidget {
  const MachineManagementScreen({super.key});

  @override
  State<MachineManagementScreen> createState() => _MachineManagementScreenState();
}

class _MachineManagementScreenState extends State<MachineManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: Sections.all.length, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MachinesProvider>().loadAll();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Machines'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: Sections.all.map((s) => Tab(text: s.name)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: Sections.all.map((s) => _MachineSectionList(section: s)).toList(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add Machine'),
        onPressed: () => _showAddMachine(Sections.all[_tabs.index]),
      ),
    );
  }

  void _showAddMachine(SectionInfo section) {
    final numCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Machine — ${section.name}'),
        content: TextFormField(
          controller: numCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Machine Number'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final num = int.tryParse(numCtrl.text);
              if (num == null) return;
              await context.read<MachinesProvider>().save(MachineModel(id: '', number: num, section: section.id));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _MachineSectionList extends StatelessWidget {
  final SectionInfo section;
  const _MachineSectionList({required this.section});

  @override
  Widget build(BuildContext context) {
    final mp = context.watch<MachinesProvider>();
    final machines = mp.forSection(section.id);
    final color = AppColors.sectionColor(section.id);

    if (mp.loading) return const Center(child: CircularProgressIndicator());
    if (machines.isEmpty) return const Center(child: Text('No machines — tap + to add'));

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1,
      ),
      itemCount: machines.length,
      itemBuilder: (ctx, i) {
        final m = machines[i];
        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onLongPress: () => _confirmDelete(ctx, m),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Text('${m.number}', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 4),
                Text('Mach.', style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, MachineModel m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Machine?'),
        content: Text('Remove Machine ${m.number} from ${section.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<MachinesProvider>().delete(m);
    }
  }
}
