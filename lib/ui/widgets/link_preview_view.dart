import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models.dart';
import '../theme.dart';

/// The unfurled card for a link in a post body.
///
/// These waited on the server. Unfurling client side would have meant a request per
/// link to a third party, blocked by CORS on the web, and every reader's address handed
/// to every site anyone linked. textlog fetches and stores them itself, so the image
/// comes from textlog and the linked site learns nothing.
///
/// Only the first is shown. A post can carry several and a column of cards buries the
/// words that were actually written.
class LinkPreviews extends StatelessWidget {
  const LinkPreviews(this.post, {super.key});

  final Post post;

  @override
  Widget build(BuildContext context) {
    if (post.linkPreviews.isEmpty) return const SizedBox.shrink();
    final entry = post.linkPreviews.entries.first;
    return Padding(
      padding: const EdgeInsets.only(top: space3),
      child: _Card(url: entry.key, preview: entry.value),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.url, required this.preview});

  final String url;
  final LinkPreview preview;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final title = preview.title?.trim();
    final description = preview.description?.trim();

    return Semantics(
      button: true,
      label: title == null ? 'open $url' : 'open $title',
      child: GestureDetector(
        onTap: () {
          final target = Uri.tryParse(url);
          if (target != null) launchUrl(target, mode: LaunchMode.externalApplication);
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: palette.soft)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (preview.imageUrl.isNotEmpty && !preview.isAudio)
                // The stored aspect reserves the space before the bytes arrive, so
                // the post does not jump as it loads.
                AspectRatio(
                  aspectRatio: preview.aspect ?? 1.91,
                  child: Image.network(
                    preview.imageUrl,
                    fit: BoxFit.cover,
                    // A card is decoration. A broken image should cost nothing but
                    // the card's image, not an exception in the middle of a feed.
                    errorBuilder: (_, _, _) => ColoredBox(color: palette.tagBg),
                    loadingBuilder: (context, child, progress) =>
                        progress == null ? child : ColoredBox(color: palette.tagBg),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(space3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (preview.siteName?.trim().isNotEmpty ?? false)
                      Text(
                        preview.siteName!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.labelSmall!.copyWith(color: palette.muted),
                      ),
                    if (title != null && title.isNotEmpty) ...[
                      const SizedBox(height: space1),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodySmall!.copyWith(
                          color: palette.ink,
                          fontWeight: FontWeight.w700,
                          fontVariations: const [FontVariation.weight(700)],
                        ),
                      ),
                    ],
                    if (description != null && description.isNotEmpty) ...[
                      const SizedBox(height: space1),
                      Text(
                        description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.labelSmall!.copyWith(
                          color: palette.quoteInk,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
