import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/body_tokens.dart';
import '../theme.dart';

/// Renders a post body with the same tokens the website links: URLs, @mentions
/// and #hashtags. Stateful only because tap recognizers need disposing.
class PostBody extends StatefulWidget {
  const PostBody(this.body, {super.key, this.style});

  final String body;

  /// Defaults to `.post p`; the quoted parent passes its smaller, quieter style.
  final TextStyle? style;

  @override
  State<PostBody> createState() => _PostBodyState();
}

class _PostBodyState extends State<PostBody> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  TapGestureRecognizer _onTap(VoidCallback action) {
    final recognizer = TapGestureRecognizer()..onTap = action;
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();

    final palette = context.palette;
    final base = widget.style ?? Theme.of(context).textTheme.bodyMedium!;
    final link = base.asLink(palette);

    return Text.rich(
      TextSpan(
        children: [
          for (final token in tokenizeBody(widget.body))
            switch (token) {
              PlainText(:final text) => TextSpan(text: text),
              LinkToken(:final url) => TextSpan(
                text: url,
                style: link,
                recognizer: _onTap(
                  () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                ),
              ),
              MentionToken(:final handle) => TextSpan(
                text: '@$handle',
                style: link,
                recognizer: _onTap(() => context.push('/u/${handle.toLowerCase()}')),
              ),
              TagToken(:final tag) => TextSpan(
                text: '#$tag',
                style: link,
                recognizer: _onTap(() => context.push('/tag/${tag.toLowerCase()}')),
              ),
            },
        ],
        style: base,
      ),
    );
  }
}
