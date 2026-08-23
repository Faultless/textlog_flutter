import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/body_analysis.dart';
import '../../core/todos.dart';
import '../../state/cache.dart';
import '../../state/feed.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../theme.dart';
import 'post_actions.dart';

/// A `#todo` checklist from a post body.
///
/// There is no endpoint for ticking one off, and that is not an omission: a checklist
/// *is* the body, so toggling an item rewrites the body and saves it as an edit. Which
/// means only the author can tick their own list — the same rule the site has.
///
/// For everyone else it reads, which is the point of posting one.
class TodoView extends ConsumerStatefulWidget {
  const TodoView(this.post, {super.key});

  final Post post;

  @override
  ConsumerState<TodoView> createState() => _TodoViewState();
}

class _TodoViewState extends ConsumerState<TodoView> {
  /// The body as it will read once the edit lands, so a tick registers immediately.
  String? _optimistic;
  var _busy = false;

  String get _body => _optimistic ?? widget.post.body;

  Future<void> _toggle(int index) async {
    final session = ref.read(sessionProvider).valueOrNull;
    if (session == null || _busy) return;

    final next = toggleTodo(_body, index);
    if (next == null) return;

    final previous = _optimistic;
    setState(() {
      _busy = true;
      _optimistic = next;
    });

    try {
      final saved = await ref.read(apiProvider).editPost(session.token, widget.post.id, next);
      if (!mounted) return;
      setState(() => _optimistic = saved.body);
      // The list is the body, so every copy of the post has to agree.
      ref.read(postCacheProvider).replace(saved);
      ref.read(repliesCacheProvider).apply(saved.id, saved);
      applyToLiveFeeds(saved.id, saved);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _optimistic = previous);
      toast(context, failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final todo = analyseTodo(_body);
    if (todo == null) return const SizedBox.shrink();

    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final viewer = ref.watch(viewerHandleProvider);
    final mine = viewer != null && viewer == widget.post.author.handle;

    return Padding(
      padding: const EdgeInsets.only(top: space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, item) in todo.items.indexed)
            _Item(
              item,
              // Ticking is an edit, so it is the author's to make.
              onTap: mine && !_busy ? () => _toggle(index) : null,
            ),
          const SizedBox(height: space1),
          Text(
            '${todo.checked} of ${todo.items.length} done',
            style: theme.labelSmall!.copyWith(
              color: todo.complete ? palette.accent : palette.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item(this.item, {required this.onTap});

  final TodoItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    return Semantics(
      checked: item.checked,
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          // Room for a thumb even though the box itself is three characters.
          padding: const EdgeInsets.symmetric(vertical: space2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.checked ? '[x] ' : '[ ] ',
                style: theme.bodyMedium!.copyWith(
                  color: item.checked ? palette.accent : palette.muted,
                ),
              ),
              Expanded(
                child: Text(
                  item.label,
                  style: theme.bodyMedium!.copyWith(
                    color: item.checked ? palette.quoteInk : palette.ink,
                    decoration: item.checked ? TextDecoration.lineThrough : null,
                    decorationColor: palette.linkBorder,
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
