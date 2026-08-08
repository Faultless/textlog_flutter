import 'package:flutter/material.dart';

import '../../core/feed_source.dart';
import '../theme.dart';
import '../widgets/feed_view.dart';
import '../widgets/shell.dart';

class TagScreen extends StatelessWidget {
  const TagScreen({super.key, required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: textlogAppBar(context, path: '/tag/$tag', showBack: true),
    body: FeedView(
      TagFeed(tag),
      emptyMessage: 'Nothing tagged #$tag yet.',
      header: SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: gutterOf(context), vertical: space5),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '#', style: TextStyle(color: context.palette.accent)),
                TextSpan(text: tag),
              ],
            ),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ),
    ),
  );
}
