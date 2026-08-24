/// Port of the server's Vocaroo handling.
///
/// textlog turns a voca.ro link into an inline player, proxying the mp3 through
/// `/media/vocaroo/{id}`. Going through the proxy is the point: it is a plain ranged
/// mp3 served by textlog, so playing a clip tells Vocaroo nothing about who listened.
/// Reading the id out of the link is also the only way to tell a voice clip from any
/// other link — these come back with no preview metadata at all, no title and no
/// image.
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

/// Where to stream the clip from: textlog's proxy, never Vocaroo directly.
///
/// Null when [url] is not a clip. [origin] is the instance the app is talking to, so
/// a self-hosted textlog proxies its own readers rather than sending them to the
/// public one.
String? audioStreamUrl(String url, {required String origin}) {
  final id = vocarooId(url);
  if (id == null) return null;
  final base = origin.endsWith('/') ? origin.substring(0, origin.length - 1) : origin;
  return '$base/media/vocaroo/${Uri.encodeComponent(id)}';
}

/// Every voice clip linked from [body], in the order written.
Iterable<String> audioLinksIn(String body) =>
    matchUrls(body).map((match) => match.url).where(isAudioLink);
