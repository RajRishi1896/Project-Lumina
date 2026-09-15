// Regression test for grouped course-download notifications: one verdict per
// group when its last task settles (pure seam in
// lib/shared/services/download_queue.dart: no SQLite, no notifications).
import 'package:flutter_test/flutter_test.dart';

import 'package:edumesh_android/shared/services/download_queue.dart';

void main() {
  group('DownloadGroupTracker verdicts', () {
    test('all-success settles to complete with the group title', () {
      final t = DownloadGroupTracker();
      t.add('c1', 'Fractions');
      t.add('c1', 'Fractions');
      expect(t.pendingGroupCount, 1);
      expect(t.settle('c1', success: true), isNull);
      expect(t.settle('c1', success: true),
          (GroupVerdict.complete, 'Fractions'));
      expect(t.pendingGroupCount, 0);
    });

    test('any failure settles to failed', () {
      final t = DownloadGroupTracker();
      t.add('c1', 'Fractions');
      t.add('c1', 'Fractions');
      t.add('c1', 'Fractions');
      expect(t.settle('c1', success: true), isNull);
      expect(t.settle('c1', success: false), isNull);
      expect(t.settle('c1', success: false),
          (GroupVerdict.failed, 'Fractions'));
    });

    test('tasks added while draining grow the total', () {
      final t = DownloadGroupTracker();
      t.add('c1', 'Fractions');
      t.add('c1', 'Fractions');
      expect(t.settle('c1', success: true), isNull);
      t.add('c1', 'Fractions'); // late enqueue mid-drain
      expect(t.settle('c1', success: true), isNull);
      expect(t.settle('c1', success: true),
          (GroupVerdict.complete, 'Fractions'));
    });

    test('verdict fires exactly once; late settles are null', () {
      final t = DownloadGroupTracker();
      t.add('c1', 'Fractions');
      expect(t.settle('c1', success: true),
          (GroupVerdict.complete, 'Fractions'));
      expect(t.settle('c1', success: true), isNull);
      expect(t.settle('c1', success: false), isNull);
    });

    test('unknown group settles to null', () {
      final t = DownloadGroupTracker();
      expect(t.settle('ghost', success: true), isNull);
      expect(t.discard('ghost'), isNull);
    });

    test('groups are independent', () {
      final t = DownloadGroupTracker();
      t.add('c1', 'Fractions');
      t.add('c2', 'Photosynthesis');
      t.add('c2', 'Photosynthesis');
      expect(t.settle('c1', success: false),
          (GroupVerdict.failed, 'Fractions'));
      expect(t.settle('c2', success: true), isNull);
      expect(t.settle('c2', success: true),
          (GroupVerdict.complete, 'Photosynthesis'));
    });

    test('discard of an unsettled-only group stays silent', () {
      final t = DownloadGroupTracker();
      t.add('c1', 'Fractions');
      expect(t.discard('c1'), isNull);
      expect(t.pendingGroupCount, 0);
    });

    test('discard fires the verdict when the rest already settled', () {
      final t = DownloadGroupTracker();
      t.add('c1', 'Fractions');
      t.add('c1', 'Fractions');
      t.add('c1', 'Fractions');
      expect(t.settle('c1', success: true), isNull);
      expect(t.settle('c1', success: true), isNull);
      expect(t.discard('c1'), (GroupVerdict.complete, 'Fractions'));
    });

    test('first non-empty title wins', () {
      final t = DownloadGroupTracker();
      t.add('c1', '');
      t.add('c1', 'Fractions');
      expect(t.settle('c1', success: true), isNull);
      expect(t.settle('c1', success: true),
          (GroupVerdict.complete, 'Fractions'));
    });

    test('clear drops groups without verdicts', () {
      final t = DownloadGroupTracker();
      t.add('c1', 'Fractions');
      t.clear();
      expect(t.pendingGroupCount, 0);
      expect(t.settle('c1', success: true), isNull);
    });
  });
}
