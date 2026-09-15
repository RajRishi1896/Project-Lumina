// Regression test for chapter-grouped course locks (pure-function seam in
// lib/core/models/course.dart: no SQLite, no widgets).
import 'package:flutter_test/flutter_test.dart';

import 'package:edumesh_android/core/models/course.dart';

CourseResource _res(String id, String topicId, int position,
    {CourseType type = CourseType.textbook}) {
  return CourseResource(
    id: id,
    courseId: 'c1',
    resourceType: type,
    title: id,
    fileSize: 0,
    position: position,
    topicId: topicId,
  );
}

void main() {
  // Fixture: two chapters (t1 sequential, t2 all) + one ungrouped resource.
  final topics = [
    const CourseTopic(id: 't1', title: 'Chapter 1', position: 0, unlockMode: 'sequential'),
    const CourseTopic(id: 't2', title: 'Chapter 2', position: 1, unlockMode: 'all'),
  ];
  final resources = [
    _res('r1', 't1', 0),
    _res('r2', 't1', 1),
    _res('r3', 't2', 0),
    _res('r4', 't2', 1),
    _res('r5', '', 2),
  ];

  Set<String> unlocked(Set<String> done) => computeUnlockedResourceIds(
        topics: topics,
        resources: resources,
        completedIds: done,
      );

  group('computeUnlockedResourceIds (chapter locks)', () {
    test('fresh progress: first sequential item + ungrouped unlocked only', () {
      expect(unlocked({}), {'r1', 'r5'});
    });

    test('sequential chapter opens resource-by-resource', () {
      expect(unlocked({'r1'}), {'r1', 'r2', 'r5'});
      // Chapter 2 stays locked while chapter 1 has incomplete work.
      expect(unlocked({'r1'}).contains('r3'), isFalse);
    });

    test('chapter N unlocks when chapter N-1 fully completes', () {
      // t2 uses unlock_mode 'all': everything opens at once.
      expect(unlocked({'r1', 'r2'}), {'r1', 'r2', 'r3', 'r4', 'r5'});
    });

    test('locks recompute after every completion', () {
      var done = <String>{};
      expect(unlocked(done).contains('r2'), isFalse);
      done = {...done, 'r1'};
      expect(unlocked(done).contains('r2'), isTrue);
      expect(unlocked(done).contains('r3'), isFalse);
      done = {...done, 'r2'};
      expect(unlocked(done).contains('r3'), isTrue);
    });

    test('unknown topic_id is treated as always-unlocked ungrouped', () {
      final extra = [...resources, _res('rx', 'ghost-topic', 0)];
      final open = computeUnlockedResourceIds(
          topics: topics, resources: extra, completedIds: {});
      expect(open.contains('rx'), isTrue);
    });

    test('no topics: everything is ungrouped and unlocked', () {
      final open = computeUnlockedResourceIds(
          topics: const [], resources: resources, completedIds: {});
      expect(open, {'r1', 'r2', 'r3', 'r4', 'r5'});
    });

    test('unknown unlock_mode falls back to all', () {
      const t = CourseTopic(id: 't', title: 'X', unlockMode: 'weird');
      expect(t.isSequential, isFalse);
      final open = computeUnlockedResourceIds(
        topics: const [t],
        resources: [_res('a', 't', 0), _res('b', 't', 1)],
        completedIds: const {},
      );
      expect(open, {'a', 'b'});
    });
  });

  group('groupResourcesByTopic', () {
    test('chapters run in position order with ungrouped last', () {
      final sections = groupResourcesByTopic(topics, resources);
      expect(sections.map((s) => s.topic?.id), ['t1', 't2', null]);
      expect(sections[0].resources.map((r) => r.id), ['r1', 'r2']);
      expect(sections[1].resources.map((r) => r.id), ['r3', 'r4']);
      expect(sections[2].resources.map((r) => r.id), ['r5']);
    });
  });

  group('quiz version helpers', () {
    test('quizVersionOf reads nested and flat forms', () {
      expect(quizVersionOf(const {'quiz': {'quiz_version': 3}}), 3);
      expect(quizVersionOf(const {'quiz_version': 2}), 2);
      expect(quizVersionOf(const {}), 1);
    });

    test('isQuizCacheStale fires only on a served bump', () {
      expect(
          isQuizCacheStale(
              cachedQuiz: const {'quiz': {'quiz_version': 2}},
              servedVersion: 3),
          isTrue);
      expect(
          isQuizCacheStale(
              cachedQuiz: const {'quiz': {'quiz_version': 3}},
              servedVersion: 3),
          isFalse);
      expect(isQuizCacheStale(cachedQuiz: null, servedVersion: 9), isFalse);
    });
  });
}
