import 'package:flutter_test/flutter_test.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/core/post_context.dart';

Post post({
  int id = 2,
  String handle = 'alice',
  String body = 'hello',
  int? parentId,
  Post? parent,
  List<String> mentions = const [],
}) => Post(
  id: id,
  body: body,
  createdAt: DateTime(2026, 8, 8),
  parentId: parentId ?? parent?.id,
  replyCount: 0,
  tags: const [],
  mentions: mentions,
  url: Uri.parse('https://textlog.cc/post/$id'),
  author: Author(handle: handle, url: Uri.parse('https://textlog.cc/u/$handle')),
  parent: parent,
);

void main() {
  group('what the meta line says', () {
    test('a top-level post was written', () {
      final relation = postContextOf(post());
      expect(relation.relation, PostRelation.wrote);
      expect(relation.label, 'wrote');
    });

    test('replying to yourself is a continuation', () {
      final relation = postContextOf(
        post(handle: 'alice', parent: post(id: 1, handle: 'alice')),
      );
      expect(relation.relation, PostRelation.continued);
    });

    test('replying to the reader names the reader', () {
      final relation = postContextOf(
        post(handle: 'alice', parent: post(id: 1, handle: 'bob')),
        viewerHandle: 'bob',
      );
      expect(relation.relation, PostRelation.repliedToYou);
      expect(relation.label, 'replied to you');
    });

    test('replying to a third party names them', () {
      final relation = postContextOf(
        post(handle: 'alice', parent: post(id: 1, handle: 'bob')),
        viewerHandle: 'carol',
      );
      expect(relation.relation, PostRelation.repliedTo);
      expect(relation.target!.handle, 'bob');
    });

    test('a poll is announced as a poll, whatever else is true', () {
      final relation = postContextOf(post(body: 'tabs or spaces? #poll\ntabs\nspaces'));
      expect(relation.relation, PostRelation.createdPoll);
      expect(relation.label, 'created a poll');
    });

    test('a reply whose parent is gone says nothing at all', () {
      // The server drops a deleted parent to null. "replied to" with nothing after
      // it would be worse than silence, and the site prints nothing too.
      final relation = postContextOf(post(parentId: 1));
      expect(relation.relation, PostRelation.unknown);
      expect(relation.hasLabel, isFalse);
    });

    test('a mention of the reader is appended', () {
      final relation = postContextOf(
        post(body: 'hi @bob', mentions: const ['bob']),
        viewerHandle: 'bob',
      );
      expect(relation.mentionedYou, isTrue);
      expect(relation.relation, PostRelation.wrote);
    });

    test('a mention of somebody else is not', () {
      final relation = postContextOf(
        post(body: 'hi @carol', mentions: const ['carol']),
        viewerHandle: 'bob',
      );
      expect(relation.mentionedYou, isFalse);
    });

    test('nobody signed in means nothing is about you', () {
      final relation = postContextOf(
        post(handle: 'alice', parent: post(id: 1, handle: 'bob'), mentions: const ['bob']),
      );
      expect(relation.relation, PostRelation.repliedTo);
      expect(relation.mentionedYou, isFalse);
    });
  });

  group('a quoted parent', () {
    test('says less rather than costing a request', () {
      // The API gives a quote no parent of its own, so with nothing cached there is
      // no way to know whether it continued or replied.
      final quote = post(id: 5, handle: 'bob', parentId: 1);
      expect(quotedContextOf(quote).hasLabel, isFalse);
    });

    test('names the grandparent when it happens to be in the cache', () {
      final quote = post(id: 5, handle: 'bob', parentId: 1);
      final relation = quotedContextOf(
        quote,
        lookUp: (id) => id == 1 ? post(id: 1, handle: 'carol') : null,
      );
      expect(relation.relation, PostRelation.repliedTo);
      expect(relation.target!.handle, 'carol');
    });

    test('a cached grandparent by the same author is a continuation', () {
      final quote = post(id: 5, handle: 'bob', parentId: 1);
      final relation = quotedContextOf(
        quote,
        lookUp: (id) => post(id: 1, handle: 'bob'),
      );
      expect(relation.relation, PostRelation.continued);
    });

    test('a top-level quote needs no lookup', () {
      expect(quotedContextOf(post(id: 5)).relation, PostRelation.wrote);
    });
  });

  test('a removed account is recognised by its handle', () {
    expect(isDeletedHandle('deleted-42'), isTrue);
    expect(isDeletedHandle('deleted'), isFalse);
    expect(isDeletedHandle('undeleted-1'), isFalse);
    expect(
      Author(handle: 'deleted-7', url: Uri.parse('https://textlog.cc/u/deleted-7')).isDeleted,
      isTrue,
    );
  });
}
