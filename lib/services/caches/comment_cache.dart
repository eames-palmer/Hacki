import 'dart:collection';

import 'package:hacki/models/models.dart' show Comment;

class CommentCache {
  static const int _maxCachedComments = 1000;
  static final LinkedHashMap<int, Comment> _comments =
      LinkedHashMap<int, Comment>();

  void cacheComment(Comment comment) {
    final bool isDelayed = comment.text.trim() == '[delayed]';
    if (!isDelayed) {
      _comments.remove(comment.id);
      _comments[comment.id] = comment.copyWithoutCollapseState();
    } else {
      return;
    }

    /// Comments fetched from `HackerNewsWebRepository` doesn't have populated
    /// `kids` field, this is why we need to update that of the parent
    /// comment here.
    final int parentId = comment.parent;
    final Comment? parent = _comments[parentId];
    if (parent != null && !parent.kids.contains(comment.id)) {
      _comments.remove(parentId);
      _comments[parentId] = parent.copyWith(kid: comment.id);
    }

    while (_comments.length > _maxCachedComments) {
      _comments.remove(_comments.keys.first);
    }
  }

  Comment? getComment(int id) {
    final Comment? comment = _comments.remove(id);
    if (comment != null) {
      _comments[id] = comment;
    }
    return comment;
  }

  Stream<Comment> getCommentsStream({
    required List<int> ids,
    int level = 0,
  }) async* {
    for (final int id in ids) {
      final Comment? comment = getComment(id);

      if (comment != null) {
        yield comment.copyWith(level: level);
        yield* getCommentsStream(ids: comment.kids, level: level + 1);
      }
    }
  }
}
