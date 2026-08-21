import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../shared/services/connectivity_service.dart';
import '../models/flashcard_models.dart';
import '../network/api_client.dart';
import '../services/flashcard_scheduler.dart';
import '../services/mutation_queue.dart';
import '../storage/db_helper.dart';

/// Singleton service for flashcards: local deck CRUD, SM-2 review state, and
/// hub sync (download published decks, submit decks for teacher approval).
///
/// All decks and review state live in local SQLite so studying works fully
/// offline. Syncing with the hub only happens on explicit calls from the UI
/// or on connectivity restore.
class FlashcardService {
  static final FlashcardService _instance = FlashcardService._internal();
  factory FlashcardService() => _instance;
  FlashcardService._internal();

  /// Lists all decks stored locally, newest first, with cards and review state.
  Future<List<FlashcardDeck>> listDecks() async {
    final db = await DBHelper().database;
    final deckRows = await db.query('flashcard_decks_local', orderBy: 'updated_at DESC');
    if (deckRows.isEmpty) return const [];
    final deckIds = [for (final row in deckRows) row['id'] as String];

    final placeholders = List.filled(deckIds.length, '?').join(',');
    final cardRows = await db.rawQuery(
      'SELECT c.id, c.deck_id, c.front, c.back, '
      'r.ease, r.interval_days, r.due_at '
      'FROM flashcard_cards_local c '
      'LEFT JOIN flashcard_reviews_local r ON r.card_id = c.id '
      'WHERE c.deck_id IN ($placeholders) '
      'ORDER BY c.deck_id, c.position ASC',
      deckIds,
    );
    final cardsByDeck = <String, List<FlashcardCard>>{};
    for (final c in cardRows) {
      final deckId = c['deck_id'] as String;
      (cardsByDeck[deckId] ??= []).add(FlashcardCard(
        id: c['id'] as String,
        deckId: deckId,
        front: (c['front'] ?? '').toString(),
        back: (c['back'] ?? '').toString(),
        ease: ((c['ease'] as num?)?.toDouble() ?? 2.5),
        intervalDays: ((c['interval_days'] as num?)?.toInt() ?? 0),
        dueAt: ((c['due_at'] as num?)?.toInt() ?? 0),
      ));
    }

    final submissions = <String, Map<String, Object?>>{};
    for (final s in await db.query('flashcard_submissions_local', orderBy: 'submitted_at DESC')) {
      submissions.putIfAbsent(s['deck_id'] as String, () => s);
    }

    return [
      for (final row in deckRows)
        _assembleDeck(
          row,
          cardsByDeck[row['id'] as String] ?? const [],
          submissions[row['id'] as String],
        ),
    ];
  }

  /// Adds the optional `subject` column to the decks table if it is missing.
  ///
  /// ponytail: lives here because db_helper.dart's onCreate schema does not
  /// include `subject` yet; move the column into that CREATE TABLE and drop
  /// this helper when db_helper.dart is next editable.
  Future<void> _ensureSubjectColumn(Database db) async {
    try {
      await db.execute(
        "ALTER TABLE flashcard_decks_local ADD COLUMN subject TEXT NOT NULL DEFAULT ''",
      );
    } catch (_) {
      // Column already exists: nothing to do.
    }
  }

  FlashcardDeck _assembleDeck(
      Map<String, Object?> row, List<FlashcardCard> cards, Map<String, Object?>? submission) {
    return FlashcardDeck(
      id: row['id'] as String,
      title: (row['title'] ?? '').toString(),
      subject: (row['subject'] ?? '').toString(),
      source: (row['source'] ?? 'local').toString(),
      cards: cards,
      submissionStatus: submission == null ? '' : (submission['status'] ?? '').toString(),
      submissionReason: submission == null ? '' : (submission['reason'] ?? '').toString(),
    );
  }

  /// Returns the deck with [deckId], or `null` if it does not exist.
  Future<FlashcardDeck?> getDeck(String deckId) async {
    final db = await DBHelper().database;
    final rows = await db.query('flashcard_decks_local', where: 'id = ?', whereArgs: [deckId]);
    if (rows.isEmpty) return null;
    return _deckFromRow(db, rows.first, deckId);
  }

  Future<FlashcardDeck> _deckFromRow(Database db, Map<String, Object?> row, String deckId) async {
    final cardRows = await db.query(
      'flashcard_cards_local c LEFT JOIN flashcard_reviews_local r ON r.card_id = c.id',
      where: 'c.deck_id = ?',
      whereArgs: [deckId],
      orderBy: 'c.position ASC',
    );
    final cards = <FlashcardCard>[];
    for (final c in cardRows) {
      cards.add(FlashcardCard(
        id: c['id'] as String,
        deckId: deckId,
        front: (c['front'] ?? '').toString(),
        back: (c['back'] ?? '').toString(),
        ease: ((c['ease'] as num?)?.toDouble() ?? 2.5),
        intervalDays: ((c['interval_days'] as num?)?.toInt() ?? 0),
        dueAt: ((c['due_at'] as num?)?.toInt() ?? 0),
      ));
    }
    String submissionStatus = '';
    String submissionReason = '';
    final subRows = await db.query('flashcard_submissions_local',
        where: 'deck_id = ?', whereArgs: [deckId], orderBy: 'submitted_at DESC', limit: 1);
    if (subRows.isNotEmpty) {
      submissionStatus = (subRows.first['status'] ?? '').toString();
      submissionReason = (subRows.first['reason'] ?? '').toString();
    }
    return FlashcardDeck(
      id: deckId,
      title: (row['title'] ?? '').toString(),
      subject: (row['subject'] ?? '').toString(),
      source: (row['source'] ?? 'local').toString(),
      cards: cards,
      submissionStatus: submissionStatus,
      submissionReason: submissionReason,
    );
  }

  Future<String> createDeck(String title, String subject, List<({String front, String back})> cards) async {
    final db = await DBHelper().database;
    await _ensureSubjectColumn(db);
    final now = DateTime.now().millisecondsSinceEpoch;
    final deckId = _newId();
    await db.transaction((txn) async {
      await txn.insert('flashcard_decks_local', {
        'id': deckId,
        'title': title,
        'subject': subject,
        'source': 'local',
        'created_at': now,
        'updated_at': now,
      });
      await _insertCards(txn, deckId, cards, now);
    });
    return deckId;
  }

  /// Replaces a deck's cards (keeps review state for matching card ids only
  /// if ids were kept: we always re-issue ids, so reviews are reset).
  Future<void> updateDeck(String deckId, String title, String subject, List<({String front, String back})> cards) async {
    final db = await DBHelper().database;
    await _ensureSubjectColumn(db);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.update('flashcard_decks_local', {'title': title, 'subject': subject, 'updated_at': now},
          where: 'id = ?', whereArgs: [deckId]);
      // Reviews first: the delete subquery reads flashcard_cards_local.
      await txn.delete('flashcard_reviews_local', where: 'card_id IN (SELECT id FROM flashcard_cards_local WHERE deck_id = ?)', whereArgs: [deckId]);
      await txn.delete('flashcard_cards_local', where: 'deck_id = ?', whereArgs: [deckId]);
      await _insertCards(txn, deckId, cards, now);
    });
  }

  Future<void> _insertCards(DatabaseExecutor txn, String deckId, List<({String front, String back})> cards, int now) async {
    var position = 0;
    for (final c in cards) {
      final cardId = _newId();
      await txn.insert('flashcard_cards_local', {
        'id': cardId,
        'deck_id': deckId,
        'front': c.front,
        'back': c.back,
        'position': position++,
      });
      // ponytail: new cards are due immediately
      await txn.insert('flashcard_reviews_local', {
        'card_id': cardId,
        'ease': 2.5,
        'interval_days': 0,
        'due_at': now,
        'reviews_count': 0,
        'last_reviewed_at': 0,
      });
    }
  }

  /// Deletes a deck and all its cards + review state.
  Future<void> deleteDeck(String deckId) async {
    final db = await DBHelper().database;
    await db.transaction((txn) async {
      await txn.delete('flashcard_cards_local', where: 'deck_id = ?', whereArgs: [deckId]);
      await txn.delete('flashcard_reviews_local', where: 'card_id NOT IN (SELECT id FROM flashcard_cards_local)');
      await txn.delete('flashcard_decks_local', where: 'id = ?', whereArgs: [deckId]);
      await txn.delete('flashcard_submissions_local', where: 'deck_id = ?', whereArgs: [deckId]);
    });
  }

  /// Number of cards due right now across all decks (dashboard chip).
  Future<int> dueCount() async {
    final db = await DBHelper().database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM flashcard_reviews_local r '
      'JOIN flashcard_cards_local c ON c.id = r.card_id WHERE r.due_at <= ?',
      [now],
    );
    return (rows.first['n'] as int?) ?? 0;
  }

  /// Records a self-graded review using SM-2 and returns the updated card.
  Future<void> reviewCard(String cardId, ReviewGrade grade) async {
    final db = await DBHelper().database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await db.query('flashcard_reviews_local', where: 'card_id = ?', whereArgs: [cardId]);
    if (rows.isEmpty) return;
    final ease = ((rows.first['ease'] as num?)?.toDouble() ?? 2.5);
    final interval = ((rows.first['interval_days'] as num?)?.toInt() ?? 0);
    final next = scheduleNext(grade, ease, interval, now);
    await db.update('flashcard_reviews_local', {
      'ease': next.ease,
      'interval_days': next.intervalDays,
      'due_at': next.dueAt,
      'reviews_count': ((rows.first['reviews_count'] as num?)?.toInt() ?? 0) + 1,
      'last_reviewed_at': now,
    }, where: 'card_id = ?', whereArgs: [cardId]);
  }

  /// Fetches published decks from the hub and merges them in as hub-sourced
  /// decks (source = 'hub'). Existing hub decks with the same id are refreshed.
  ///
  /// Cards whose (front, back) already exist locally keep their id and SM-2
  /// review state; only new cards get fresh ids and a new review schedule.
  Future<void> syncClassDecks() async {
    if (!ConnectivityService().isOnline) return;
    try {
      final resp = await ApiClient.get('/api/flashcards/decks').timeout(const Duration(seconds: 15));
      final data = resp.data;
      if (data is! List) return;
      final db = await DBHelper().database;
      await db.transaction((txn) async {
        for (final item in data) {
          if (item is! Map) continue;
          final deckId = 'hub_${item['id']}';
          final title = (item['title'] ?? '').toString();
          final now = DateTime.now().millisecondsSinceEpoch;
          final exists = await txn.query('flashcard_decks_local',
              where: 'id = ?', whereArgs: [deckId], limit: 1);
          if (exists.isEmpty) {
            await txn.insert('flashcard_decks_local', {
              'id': deckId,
              'title': title,
              'source': 'hub',
              'created_at': now,
              'updated_at': now,
            });
          } else {
            await txn.update('flashcard_decks_local', {'title': title, 'updated_at': now},
                where: 'id = ?', whereArgs: [deckId]);
          }

          final existingRows = await txn.query('flashcard_cards_local',
              where: 'deck_id = ?', whereArgs: [deckId]);
          final freeCards = {for (final e in existingRows) e['id'] as String: e};
          final staleIds = <String>[];
          var position = 0;
          for (final c in (item['cards'] as List?) ?? const []) {
            if (c is! Map) continue;
            final front = (c['front'] ?? '').toString();
            final back = (c['back'] ?? '').toString();
            String? keepId;
            for (final entry in freeCards.entries) {
              if (entry.value['front'] == front && entry.value['back'] == back) {
                keepId = entry.key;
                break;
              }
            }
            if (keepId != null) {
              freeCards.remove(keepId);
              await txn.update('flashcard_cards_local', {'position': position},
                  where: 'id = ?', whereArgs: [keepId]);
              position++;
            } else {
              final cardId = _newId();
              await txn.insert('flashcard_cards_local', {
                'id': cardId,
                'deck_id': deckId,
                'front': front,
                'back': back,
                'position': position++,
              });
              await txn.insert('flashcard_reviews_local', {
                'card_id': cardId,
                'ease': 2.5,
                'interval_days': 0,
                'due_at': now,
                'reviews_count': 0,
                'last_reviewed_at': 0,
              });
            }
          }
          staleIds.addAll(freeCards.keys);
          for (final id in staleIds) {
            // Locally-reviewed cards (reviews_count > 0) carry student edits
            // and SM-2 scheduling: keep them instead of deleting on sync.
            final reviewRows = await txn.query('flashcard_reviews_local',
                where: 'card_id = ?', whereArgs: [id],
                columns: ['reviews_count'], limit: 1);
            if (reviewRows.isNotEmpty &&
                ((reviewRows.first['reviews_count'] as num?)?.toInt() ?? 0) > 0) {
              continue;
            }
            await txn.delete('flashcard_cards_local', where: 'id = ?', whereArgs: [id]);
            await txn.delete('flashcard_reviews_local', where: 'card_id = ?', whereArgs: [id]);
          }
        }
        await txn.delete('flashcard_reviews_local',
            where: 'card_id NOT IN (SELECT id FROM flashcard_cards_local)');
      });
    } catch (e) {
      debugPrint('FlashcardService: sync failed; $e');
    }
  }

  /// Submits a deck to the teacher for approval. Queues when offline.
  Future<void> submitDeck(String deckId) async {
    final deck = await getDeck(deckId);
    if (deck == null || deck.cards.isEmpty) return;
    await MutationQueue().enqueue(
      '/api/flashcards/submit',
      method: 'POST',
      body: {
        'title': deck.title,
        'deck_id': deckId,
        'cards': deck.cards.map((c) => {'front': c.front, 'back': c.back}).toList(),
      },
    );
    final db = await DBHelper().database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('flashcard_submissions_local', {
      'id': _newId(),
      'deck_id': deckId,
      'status': 'pending',
      'reason': '',
      'submitted_at': now,
    });
  }

  /// Refreshes submission statuses from the hub (best effort).
  Future<void> refreshSubmissions() async {
    if (!ConnectivityService().isOnline) return;
    try {
      final resp = await ApiClient.get('/api/flashcards/my-submissions').timeout(const Duration(seconds: 15));
      final data = resp.data;
      if (data is! List) return;
      final db = await DBHelper().database;
      for (final item in data) {
        if (item is! Map) continue;
        final deckId = (item['deck_id'] ?? '').toString();
        if (deckId.isEmpty) continue;
        await db.update('flashcard_submissions_local', {
          'status': (item['status'] ?? 'pending').toString(),
          'reason': (item['reason'] ?? '').toString(),
        }, where: 'deck_id = ?', whereArgs: [deckId]);
      }
    } catch (e) {
      debugPrint('FlashcardService: refresh submissions failed; $e');
    }
  }

  /// Exports a deck as a JSON string (for the share/export action).
  String exportDeckJson(FlashcardDeck deck) {
    return jsonEncode({
      'format': 'lumina-flashcards-v1',
      'title': deck.title,
      'cards': deck.cards.map((c) => {'front': c.front, 'back': c.back}).toList(),
    });
  }

  static int _idCounter = 0;

  String _newId() {
    _idCounter += 1;
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}${_idCounter.toRadixString(16)}';
  }
}
