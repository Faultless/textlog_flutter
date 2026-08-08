import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/feed_source.dart';
import '../../data/api.dart';
import '../../state/feed.dart';
import '../../state/providers.dart';
import '../theme.dart';

/// Everything that writes happens on textlog.cc, in a web view that owns the
/// session cookie. The app itself stays read-only and stateless about accounts —
/// no tokens to store, no login to build, nothing to keep in sync.
///
/// The path is the site's own, so logging in, replying and posting all work
/// exactly as they do in a browser, and the cookie survives between launches.

Future<void> openReply(BuildContext context, WidgetRef ref, int postId) =>
    _open(context, ref, '/post/$postId?reply=1', 'reply', postId: postId);

Future<void> openCompose(BuildContext context, WidgetRef ref) =>
    _open(context, ref, '/write', 'write');

Future<void> _open(
  BuildContext context,
  WidgetRef ref,
  String path,
  String title, {
  int? postId,
}) async {
  final url = Uri.parse('$textlogOrigin$path');

  // webview_flutter has no web implementation, and on the web a new tab is the
  // native equivalent anyway.
  if (kIsWeb) {
    await launchUrl(url, webOnlyWindowName: '_blank');
    return;
  }

  await Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => WebActionScreen(url: url, title: title)),
  );

  // Whatever was written is now on the server; drop the caches that would still
  // be showing the state from before.
  if (postId != null) {
    ref.invalidate(postProvider(postId));
    ref.invalidate(feedProvider(RepliesFeed(postId)));
  }
  ref.invalidate(feedProvider(const LatestFeed()));
}

class WebActionScreen extends StatefulWidget {
  const WebActionScreen({super.key, required this.url, required this.title});

  final Uri url;
  final String title;

  @override
  State<WebActionScreen> createState() => _WebActionScreenState();
}

class _WebActionScreenState extends State<WebActionScreen> {
  late final WebViewController _controller;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => setState(() => _loading = false),
          onNavigationRequest: (request) {
            // Keep the session inside textlog.cc; send anything else to the
            // real browser so we never become a general-purpose web view.
            if (Uri.parse(request.url).origin == Uri.parse(textlogOrigin).origin) {
              return NavigationDecision.navigate;
            }
            launchUrl(Uri.parse(request.url), mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(widget.url);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, size: 18, color: palette.ink),
          onPressed: () => context.pop(),
        ),
        title: Text(widget.title, style: Theme.of(context).textTheme.bodySmall),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) LinearProgressIndicator(color: palette.accent, minHeight: 1),
        ],
      ),
    );
  }
}
