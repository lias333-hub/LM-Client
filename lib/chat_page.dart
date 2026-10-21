part of 'main.dart';

class ProjectRuntimeBanner extends ConsumerWidget {
  final ChatSession? session;
  const ProjectRuntimeBanner({super.key, this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = pal(context);
    final root = workspaceRootFromSettings();
    final atlas = WorkflowHarness.detectProjectAtlas(root);
    final task = WorkflowHarness.createTask(
      title: session?.meta.title.isNotEmpty == true ? session!.meta.title : 'Current task',
      objective: 'Project-aware execution in the active workspace.',
      rootPath: root,
    );
    final decision = WorkflowHarness.decideNextPhase(task);
    final tools = ToolRegistry.namesForProjectType(atlas.projectType).take(5).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.border),
        boxShadow: <BoxShadow>[
          BoxShadow(color: Colors.black.withAlpha(12), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: p.surfaceHi,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.smart_toy_outlined, color: p.accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Project runtime',
                  style: TextStyle(color: p.muted, fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: p.surfaceHi,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  atlas.projectType.toUpperCase(),
                  style: TextStyle(color: p.text, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            root,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _statusChip(p, Icons.route, decision.phase),
              _statusChip(p, Icons.bolt, '${task.tokensUsed}/${task.tokensBudget} tokens'),
              _statusChip(p, Icons.check_circle_outline, '${tools.length} tools'),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            decision.reason,
            style: TextStyle(color: p.muted, fontSize: 12.3, height: 1.55),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: tools
                .map((name) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: p.surfaceHi,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        name,
                        style: TextStyle(color: p.muted, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(Pal p, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: p.surfaceHi,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: p.accent),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(color: p.text, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
