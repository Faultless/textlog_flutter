import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/feed_source.dart';
import '../theme.dart';
import '../widgets/feed_view.dart';
import '../widgets/shell.dart';
import '../widgets/status.dart';

/// `/search` — the real thing, against `/api/v1/search`.
///
/// The app already filtered a *loaded* timeline as you type, which is instant but
/// only ever finds what you had scrolled past. This searches everything.
///
/// Typing is debounced, because every keystroke would otherwise be a request against
/// a shared rate limit, and each distinct query is its own cached provider — so
/// backspacing to a query you just ran costs nothing.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

/// Long enough that a typed word is one request, short enough to feel immediate.
const searchDebounce = Duration(milliseconds: 350);

/// The server's own limit, from `MAX_SEARCH_LENGTH`.
const maxSearchLength = 200;

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final _field = TextEditingController(text: widget.initialQuery ?? '');
  late String _submitted = widget.initialQuery?.trim() ?? '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(searchDebounce, () {
      final query = value.trim();
      if (query == _submitted) return;
      setState(() => _submitted = query);
    });
  }

  void _submit() {
    _debounce?.cancel();
    setState(() => _submitted = _field.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: textlogAppBar(context, path: '/search', showBack: true),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: gutterOf(context), vertical: space3),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.soft)),
            ),
            child: Row(
              children: [
                Text('/', style: theme.bodyMedium!.copyWith(color: palette.accent)),
                const SizedBox(width: space3),
                Expanded(
                  child: TextField(
                    controller: _field,
                    autofocus: widget.initialQuery == null,
                    maxLength: maxSearchLength,
                    textInputAction: TextInputAction.search,
                    onChanged: _onChanged,
                    onSubmitted: (_) => _submit(),
                    style: theme.bodyMedium,
                    cursorColor: palette.accent,
                    decoration: InputDecoration(
                      isDense: true,
                      counterText: '',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'search every note',
                      hintStyle: theme.bodyMedium!.copyWith(color: palette.muted),
                    ),
                  ),
                ),
                if (_field.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _field.clear();
                      _submit();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.only(left: space3),
                      child: Text('clear', style: theme.labelSmall!.asLink(palette)),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _submitted.isEmpty
                ? const StatusMessage(
                    'Search posts by any words in them, a handle, or a #hashtag.',
                  )
                : FeedView(
                    SearchFeed(_submitted),
                    // Server-side search already narrowed this; a second filter on
                    // top of it would only be confusing.
                    allowFilter: false,
                    emptyMessage: 'Nothing matches that.',
                  ),
          ),
        ],
      ),
    );
  }
}
