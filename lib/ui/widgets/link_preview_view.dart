import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/body_tokens.dart' show linkOrigin;
import '../../core/media.dart';
import '../../core/models.dart';
import '../router.dart';
import '../theme.dart';
import 'voice_clip.dart';

/// The unfurled card for a link in a post body.
///
/// These waited on the server. Unfurling client side would have meant a request per
/// link to a third party, blocked by CORS on the web, and every reader's address handed
/// to every site anyone linked. textlog fetches and stores them itself, so the image
/// comes from textlog and the linked site learns nothing.
///
/// Only the first is shown. A post can carry several and a column of cards buries the
/// words that were actually written.
///
/// The shape is a thumbnail beside the text when there is an image, and a compact
/// text-only line when there is not.
class LinkPreviews extends StatelessWidget {
  const LinkPreviews(this.post, {super.key});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final entry = _first;
    if (entry == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: space3),
      child: _Card(url: entry.$1, preview: entry.$2),
    );
  }

  /// The preview to draw, if any.
  ///
  /// A voice clip is the one card the server does not send: it drives its own player
  /// straight off the link, so there is no preview entry to iterate. Recognising the
  /// link is what tells a clip apart from any other bare URL, so it is synthesised
  /// here — and only when the server sent nothing, which keeps a real preview first.
  (String, LinkPreview)? get _first {
    if (post.linkPreviews.isNotEmpty) {
      final entry = post.linkPreviews.entries.first;
      return (entry.key, entry.value);
    }
    for (final url in audioLinksIn(post.body)) {
      return (url, const LinkPreview(imageUrl: '', mimeType: 'audio/mpeg'));
    }
    return null;
  }
}

/// The map card for a `#map` post.
///
/// Same card as an unfurled link, because that is what the server sends: a tile it
/// rendered itself and a caption from the geocoder. Tapping it opens whichever maps
/// site the server chose — this app does not pick, and no coordinates of the
/// reader's ever leave the phone.
class LocationPreview extends StatelessWidget {
  const LocationPreview(this.post, {super.key});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final location = post.location;
    if (location == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: space3),
      child: _Card(url: location.url.toString(), preview: location.preview),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.url, required this.preview});

  final String url;
  final LinkPreview preview;

  /// A thumbnail, not a hero. One of the previews on textlog is 1191×1684 — rendered
  /// at its own aspect that is 475px of a phone screen, which buries the post that
  /// linked it. A fixed square crop is predictable whatever the source shape.
  static const _thumbnail = 72.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final title = preview.title?.trim();
    final description = preview.description?.trim();
    final site = preview.siteName?.trim();

    // Audio has no image worth showing, and neither does a preview that only came
    // back with words — either way it reads as a compact line rather than a card
    // with a hole where a picture should be.
    //
    // Nor does anything on the web build. textlog stores every preview image on a
    // host that sends no `Access-Control-Allow-Origin` at all, and Flutter's canvas
    // renderer fetches images with XHR — so on web these cannot be drawn from any
    // origin. Rendering an <img> element instead escapes Flutter's layout entirely
    // and fills the screen, which is worse than not having the picture. The compact
    // form is the honest rendering there.
    final hasThumbnail = !kIsWeb && preview.imageUrl.isNotEmpty && !preview.isAudio;

    // A voice clip. Vocaroo answers with no preview metadata at all, so without
    // recognising the link a clip and a blog post look exactly alike.
    final stream = audioStreamUrl(url, origin: linkOrigin);

    // A clip plays here rather than opening anywhere, so it is its own control and
    // not a link card at all.
    if (stream != null) return VoiceClip(url: url, streamUrl: stream);

    // Nothing but an image is not a preview worth a card; the link is already in the
    // body above it.
    if (!hasThumbnail && title == null && description == null && !preview.isAudio) {
      return const SizedBox.shrink();
    }

    return Semantics(
      button: true,
      label: preview.isAudio ? 'open the audio at $url' : 'open ${title ?? url}',
      child: GestureDetector(
        // A preview of a textlog post opens in the app, like the link itself.
        onTap: () => openLink(context, url),
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: palette.soft)),
          child: Row(
            // Never stretch. `CrossAxisAlignment.stretch` resolves against the
            // incoming maximum cross-axis extent, which inside a scrollable is
            // unbounded — so it throws "BoxConstraints forces an infinite height"
            // and takes the whole list down with it. The thumbnail has a fixed size
            // and the text centres against it, which needs no such measurement.
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (hasThumbnail)
                SizedBox(
                  width: _thumbnail,
                  height: _thumbnail,
                  child: Image.network(
                    preview.imageUrl,
                    fit: BoxFit.cover,
                    // A card is decoration: a broken image costs its own square, not
                    // an exception in the middle of a feed.
                    errorBuilder: (_, _, _) => ColoredBox(color: palette.tagBg),
                    loadingBuilder: (context, child, progress) =>
                        progress == null ? child : ColoredBox(color: palette.tagBg),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(space3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (preview.isAudio)
                        Text(
                          '♪ audio${site != null && site.isNotEmpty ? ' · $site' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.labelSmall!.copyWith(color: palette.accent),
                        )
                      else if (site != null && site.isNotEmpty)
                        Text(
                          site,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.labelSmall!.copyWith(color: palette.muted),
                        ),
                      if (title != null && title.isNotEmpty)
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
                      if (description != null && description.isNotEmpty)
                        Text(
                          description,
                          // Two lines with a thumbnail beside it, three without —
                          // the compact form has the width to spare.
                          maxLines: hasThumbnail ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.labelSmall!.copyWith(
                            color: palette.quoteInk,
                            height: 1.45,
                          ),
                        ),
                    ],
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
