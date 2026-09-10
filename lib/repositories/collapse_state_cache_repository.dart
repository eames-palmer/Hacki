import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:hacki/extensions/extensions.dart';
import 'package:hacki/extensions/loggable.dart';
import 'package:hacki/models/models.dart';
import 'package:hive/hive.dart';

/// [CollapseStateCacheRepository] is for persisting collapse or hidden states
/// of comments across sessions.
class CollapseStateCacheRepository with Loggable {
  CollapseStateCacheRepository({Future<Box<String>>? commentBox})
    : _box = commentBox ?? Hive.openBox<String>(_boxName) {
    initialize();
  }

  static const String _boxName = 'persistedCollapseStates';
  static const int _maxLength = 5_000;
  static const int _maxStoriesToKeep = 30;
  final Future<Box<String>> _box;
  Status _status = .idle;

  Map<int, Map<int, Comment>> _itemIdToPreviousStates =
      <int, Map<int, Comment>>{};

  Map<int, Map<int, Comment>> get cachedItemIdToPreviousStates =>
      _itemIdToPreviousStates;

  Future<void> initialize() async {
    if (_status == .idle) {
      final Map<int, Map<int, Comment>> itemIdToPreviousStates =
          await loadAll();
      _itemIdToPreviousStates = itemIdToPreviousStates;
      logDebug(
        '''
        retrieved collapse state for stories: ${_itemIdToPreviousStates.keys}''',
      );
      _status = .success;
    }
  }

  Future<void> saveAll(Map<int, Map<int, Comment>> map) async {
    for (final MapEntry<int, Map<int, Comment>> entry in map.entries) {
      await saveStoryStates(entry.key, entry.value);
      logDebug('saved collapse state for story ${entry.key}');
    }
  }

  Future<void> saveStoryStates(
    int storyId,
    Map<int, Comment> commentMap,
  ) async {
    final Box<String> box = await _box;

    logDebug('old keys for $storyId: ${box.keys}');
    final List<String> oldKeys = box.keys
        .cast<String>()
        .where((String k) => k.startsWith('${storyId}_'))
        .toList();
    await box.deleteAll(oldKeys);

    final Map<String, String> entries = commentMap.map(
      (int commentId, Comment comment) => MapEntry<String, String>(
        '${storyId}_$commentId',
        jsonEncode(comment.toJsonWithOnlyCollapseState()),
      ),
    );
    await box.putAll(entries);
    logDebug('all entries: $entries');
    await _pruneBox(box);
  }

  Future<Map<int, Comment>> loadStoryStates(int storyId) async {
    final Box<String> box = await _box;
    final String prefix = '${storyId}_';

    return Map<int, Comment>.fromEntries(
      box.keys.cast<String>().where((String k) => k.startsWith(prefix)).map((
        String k,
      ) {
        final int commentId = int.parse(k.split('_').last);
        final Comment comment = Comment.fromJsonWithCollapsedStateOnly(
          jsonDecode(box.get(k)!) as Map<String, dynamic>,
        );
        return MapEntry<int, Comment>(commentId, comment);
      }),
    );
  }

  Future<Map<int, Map<int, Comment>>> loadAll() async {
    final Box<String> box = await _box;
    await _pruneBox(box);

    final Map<int, Map<int, Comment>> result = <int, Map<int, Comment>>{};
    logDebug('all keys: ${box.keys}');
    for (final String key in box.keys.cast<String>()) {
      logDebug('handling key: $key');
      final List<String> parts = key.split('_');
      final int storyId = int.parse(parts[0]);
      final int commentId = int.parse(parts[1]);
      final String? jsonString = box.get(key);
      if (jsonString != null) {
        final Comment comment = Comment.fromJsonWithCollapsedStateOnly(
          jsonDecode(jsonString) as Map<String, dynamic>,
        );

        result.putIfAbsent(storyId, () => <int, Comment>{})[commentId] =
            comment;
      }
    }

    logInfo('${box.length} keys in preserved collapse states');

    return result;
  }

  Future<void> _pruneBox(Box<String> box) async {
    final List<int> storyIds = box.keys
        .cast<String>()
        .map((String key) => int.tryParse(key.split('_').first) ?? 0)
        .where((int storyId) => storyId > 0)
        .toSet()
        .toList();
    final List<int> deletedStoryIds = <int>[];

    while ((storyIds.length > _maxStoriesToKeep || box.length > _maxLength) &&
        storyIds.length > 1) {
      final int storyId = storyIds.removeAt(0);
      final List<String> keysToDelete = box.keys
          .cast<String>()
          .where((String key) => key.startsWith('${storyId}_'))
          .toList();
      await box.deleteAll(keysToDelete);
      deletedStoryIds.add(storyId);
    }

    if (deletedStoryIds.isNotEmpty) {
      logInfo('deleted collapse state for stories: $deletedStoryIds');
    }
  }

  Future<void> clear() async => (await _box).clear();

  @override
  String get logIdentifier => 'CollapseStateCacheRepository';
}
