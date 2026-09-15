// Regression tests for the Saved-bookmarks converge/tombstone decisions.
//
// These cover BookmarkSync's pure seam only: no SQLite, no network. The
// DB/network halves (push, convergeAfterLogin, catalog freshness) have no
// injectable seam (DBHelper/ApiClient/ConnectivityService are singletons),
// so they are verified by dart analyze + manual pass, not unit tests.
import 'package:flutter_test/flutter_test.dart';

import 'package:edumesh_android/core/services/bookmark_sync.dart';

void main() {
  group('BookmarkSync.isCatalogBacked', () {
    test('zim and course rows never live in the catalog', () {
      expect(BookmarkSync.isCatalogBacked('kiwix'), isFalse);
      expect(BookmarkSync.isCatalogBacked('course'), isFalse);
      expect(BookmarkSync.isCatalogBacked(''), isFalse);
    });

    test('catalog resource types are backed', () {
      for (final t in ['textbook', 'videos', 'video', 'pyq', 'pastPaper', 'quiz', 'notes']) {
        expect(BookmarkSync.isCatalogBacked(t), isTrue, reason: t);
      }
    });

    test('matching is case-insensitive and trims', () {
      expect(BookmarkSync.isCatalogBacked('KIWIX'), isFalse);
      expect(BookmarkSync.isCatalogBacked(' Course '), isFalse);
      expect(BookmarkSync.isCatalogBacked('Textbook'), isTrue);
    });
  });

  group('BookmarkSync.localOnlyIds (push-back decision)', () {
    test('empty when server already holds every local id', () {
      expect(
        BookmarkSync.localOnlyIds({'1', '2'}, {'1', '2', '3'}),
        isEmpty,
      );
    });

    test('returns exactly the offline-created ids', () {
      expect(
        BookmarkSync.localOnlyIds({'1', '2', '9'}, {'1', '2'}),
        {'9'},
      );
    });

    test('empty local list never pushes', () {
      expect(BookmarkSync.localOnlyIds({}, {'1'}), isEmpty);
    });
  });

  group('BookmarkSync.missingForInsert (pull decision)', () {
    Map<String, dynamic> row(String id, [String title = 't']) => {
          'resource_id': id,
          'title': title,
          'subject': 's',
          'grade': '9',
          'resource_type': 'textbook',
        };

    test('inserts only ids absent locally; never touches existing rows', () {
      final missing = BookmarkSync.missingForInsert(
        [row('1', 'server-title'), row('2'), row('3')],
        {'1', '3'},
      );
      expect(missing.map((b) => b['resource_id']), ['2']);
      // The existing row keeps its local title: converge must not overwrite.
      expect(missing.any((b) => b['resource_id'] == '1'), isFalse);
    });

    test('empty server list inserts nothing', () {
      expect(BookmarkSync.missingForInsert([], {'1'}), isEmpty);
    });

    test('fresh profile inserts the whole server list', () {
      final missing = BookmarkSync.missingForInsert([row('1'), row('2')], {});
      expect(missing.map((b) => b['resource_id']), ['1', '2']);
    });
  });

  group('BookmarkSync.isTombstoneEligible', () {
    test('online + fresh + absent catalog-backed type renders tombstone', () {
      expect(
        BookmarkSync.isTombstoneEligible(
          isOnline: true,
          catalogFresh: true,
          inCatalog: false,
          rawType: 'textbook',
        ),
        isTrue,
      );
    });

    test('never flags while offline', () {
      expect(
        BookmarkSync.isTombstoneEligible(
          isOnline: false,
          catalogFresh: true,
          inCatalog: false,
          rawType: 'textbook',
        ),
        isFalse,
      );
    });

    test('never flags on a stale cache', () {
      expect(
        BookmarkSync.isTombstoneEligible(
          isOnline: true,
          catalogFresh: false,
          inCatalog: false,
          rawType: 'videos',
        ),
        isFalse,
      );
    });

    test('never flags ids still in the catalog', () {
      expect(
        BookmarkSync.isTombstoneEligible(
          isOnline: true,
          catalogFresh: true,
          inCatalog: true,
          rawType: 'notes',
        ),
        isFalse,
      );
    });

    test('never flags zim or course rows (catalog never holds them)', () {
      for (final t in ['kiwix', 'course']) {
        expect(
          BookmarkSync.isTombstoneEligible(
            isOnline: true,
            catalogFresh: true,
            inCatalog: false,
            rawType: t,
          ),
          isFalse,
          reason: t,
        );
      }
    });
  });
}
