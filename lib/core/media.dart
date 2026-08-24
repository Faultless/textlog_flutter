/// Port of the server's Vocaroo handling.
///
/// textlog turns a voca.ro link into an inline player, proxying the mp3 through
/// `/media/vocaroo/{id}` so the reader's address never reaches Vocaroo. This app
/// deliberately does not play it: an audio engine is a real dependency, with a
/// lock-screen, a focus policy and an interruption story attached, and none of that
/// is what a Vocaroo link in a text feed is asking for. Tapping it opens Vocaroo,
/// which has a player already.
///
/// What is worth porting is *recognising* one. These links come back with no preview
/// at all — no title, no image — so without this they render as a bare URL and the
/// reader cannot tell a voice clip from any other link.
library;

import 'content.dart';

const _hosts = {'voca.ro', 'www.voca.ro', 'vocaroo.com', 'www.vocaroo.com'};

final _id = RegExp(r'^/([a-z0-9]+)/?$', caseSensitive: false);

/// The clip id, or null if this is not a Vocaroo link.
String? vocarooId(String url) {
  final parsed = Uri.tryParse(url);
  if (parsed == null || !_hosts.contains(parsed.host.toLowerCase())) return null;
  return _id.firstMatch(parsed.path)?.group(1);
}

/// Is this link a voice clip?
bool isAudioLink(String url) => vocarooId(url) != null;

/// Every voice clip linked from [body], in the order written.
Iterable<String> audioLinksIn(String body) =>
    matchUrls(body).map((match) => match.url).where(isAudioLink);
