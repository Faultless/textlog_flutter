import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/feed_source.dart';
import '../../core/models.dart';
import '../../state/cache.dart';
import '../../state/feed.dart';
import '../../state/providers.dart';
import '../../state/thread.dart';
import '../../state/session.dart';
import '../theme.dart';
import 'form_parts.dart';
import 'status.dart';

const postMaxLength = 280;

enum ComposeKind { post, reply, edit }

/// The site's compose box, as a sheet. One form for posting, replying and editing,
/// because on textlog they are the same 280 characters and the same button.
Future<bool> showCompose(
  BuildContext context, {
  ComposeKind kind = ComposeKind.post,
  Post? target,
}) async {
  final posted = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _Compose(kind: kind, target: target),
    ),
  );
  return posted ?? false;
}

class _Compose extends ConsumerStatefulWidget {
  const _Compose({required this.kind, this.target});

  final ComposeKind kind;
  final Post? target;

  @override
  ConsumerState<_Compose> createState() => _ComposeState();
}

class _ComposeState extends ConsumerState<_Compose> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.kind == ComposeKind.edit ? widget.target?.body ?? '' : '',
  );
  String? _error;
  var _sending = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _heading => switch (widget.kind) {
    ComposeKind.post => "What's on your mind",
    ComposeKind.reply => 'Reply to @${widget.target?.author.handle}',
    ComposeKind.edit => 'Edit your post',
  };

  Future<void> _send() async {
    final session = ref.read(sessionProvider).valueOrNull;
    final body = _controller.text;
    if (session == null) return;
    if (body.trim().isEmpty || body.length > postMaxLength) {
      setState(() => _error = 'Posts contain between 1 and $postMaxLength characters.');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final api = ref.read(apiProvider);
      switch (widget.kind) {
        case ComposeKind.post:
          await api.createPost(session.token, body);
          ref.invalidate(feedProvider(const LatestFeed()));
          ref.invalidate(profileProvider(session.account.handle));
        case ComposeKind.reply:
          await api.createPost(session.token, body, parentId: widget.target!.id);
          _replyLanded(widget.target!.id);
        case ComposeKind.edit:
          final updated = await api.editPost(session.token, widget.target!.id, body);
          _editLanded(updated);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach textlog.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// The reply itself has to come from the server to get its id and timestamp, so
  /// this drops the thread and lets it reload rather than inventing a post.
  void _replyLanded(int parentId) {
    ref.read(repliesCacheProvider).forget(parentId);
    ref.read(postCacheProvider).forget(parentId);
    ref.invalidate(postProvider(parentId));
    ref.invalidate(threadProvider(parentId));
    ref.invalidate(feedProvider(const LatestFeed()));
    ref.invalidate(profileProvider(ref.read(sessionProvider).valueOrNull!.account.handle));
  }

  /// An edit comes back fully formed, so write it straight into everything holding it.
  void _editLanded(Post updated) {
    ref.read(postCacheProvider).replace(updated);
    ref.read(repliesCacheProvider).apply(updated.id, updated);
    applyToLiveFeeds(updated.id, updated);
    ref.invalidate(postProvider(updated.id));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final handle = ref.watch(sessionProvider).valueOrNull?.account.handle ?? '';
    final remaining = postMaxLength - _controller.text.length;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.bg,
        border: Border(top: BorderSide(color: palette.soft)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: gutterOf(context), vertical: space5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // `.compose-heading` with its accent @.
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '$_heading, '),
                    TextSpan(text: '@', style: TextStyle(color: palette.accent)),
                    TextSpan(text: '$handle?'),
                  ],
                ),
                style: theme.titleLarge!.copyWith(fontWeight: FontWeight.w400),
              ),
              const SizedBox(height: space3),
              FormMessage(_error),
              TextlogField(
                controller: _controller,
                autofocus: true,
                maxLength: postMaxLength,
                minLines: 5,
                maxLines: 8,
                onSubmitted: (_) => _send(),
              ),
              const SizedBox(height: space3),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$remaining characters left · use #hashtags and @mentions',
                      style: theme.labelSmall!.copyWith(color: palette.muted),
                    ),
                  ),
                  const SizedBox(width: space4),
                  if (_sending)
                    const Spinner()
                  else
                    TextlogButton(
                      switch (widget.kind) {
                        ComposeKind.post => 'post →',
                        ComposeKind.reply => 'reply →',
                        ComposeKind.edit => 'save →',
                      },
                      onPressed: _send,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
