import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'widgets.dart';

class ReorderEntry {
  final String key;
  final String title;
  final String? subtitle;
  const ReorderEntry(this.key, this.title, [this.subtitle]);
}

/// Maniglia ≡ da trascinare (subito, senza pressione lunga).
class DragHandle extends StatelessWidget {
  final int index;
  const DragHandle(this.index, {super.key});
  @override
  Widget build(BuildContext context) => ReorderableDragStartListener(
        index: index,
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Icon(Icons.drag_handle_rounded, color: context.tt.dim),
          ),
        ),
      );
}

/// Schermata "Riordina" come in Hevy: trascini dalla maniglia ≡ e togli con il tasto rosso.
/// Restituisce le chiavi nel nuovo ordine (senza quelle tolte), o null se si torna indietro.
class ReorderScreen extends StatefulWidget {
  final String title;
  final List<ReorderEntry> entries;
  final bool allowRemove;
  const ReorderScreen({super.key, this.title = 'Riordina', required this.entries, this.allowRemove = true});
  @override
  State<ReorderScreen> createState() => _ReorderScreenState();
}

class _ReorderScreenState extends State<ReorderScreen> {
  late final List<ReorderEntry> items = [...widget.entries];

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return SubPage(
      title: widget.title,
      bottom: BottomActions(children: [
        PrimaryButton('Fatto', onTap: items.isEmpty && widget.entries.isNotEmpty ? null : () => Navigator.pop(context, items.map((e) => e.key).toList())),
      ]),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 28),
            itemCount: items.length,
            onReorderItem: (from, to) => setState(() {
              items.insert(to, items.removeAt(from));
            }),
            proxyDecorator: (child, _, _) => Material(color: t.surf2, elevation: 6, borderRadius: BorderRadius.circular(12), child: child),
            itemBuilder: (_, i) {
              final e = items[i];
              return Padding(
                key: ValueKey(e.key),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  if (widget.allowRemove)
                    IconButton(
                      tooltip: 'Togli',
                      onPressed: () => setState(() => items.removeAt(i)),
                      icon: const Icon(Icons.remove_circle_rounded, color: TC.danger),
                    )
                  else
                    const SizedBox(width: 12),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: t.ink)),
                      if (e.subtitle != null) Text(e.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TS.muted(t, 12)),
                    ]),
                  ),
                  DragHandle(i),
                ]),
              );
            },
          ),
        ),
      ),
    );
  }
}
