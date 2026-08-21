import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:path_provider/path_provider.dart';

import 'package:edumesh_android/core/constants/app_spacing.dart';
import 'package:edumesh_android/core/models/flashcard_models.dart';
import 'package:edumesh_android/core/services/flashcard_service.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

import 'flashcard_edit_page.dart';
import 'flashcard_study_page.dart';

/// Lists the student's flashcard decks with due counts, submission status,
/// and the overflow actions (edit, send, export, delete).
class FlashcardDeckListPage extends StatefulWidget {
  /// Creates the flashcard deck list page.
  const FlashcardDeckListPage({super.key});

  @override
  State<FlashcardDeckListPage> createState() => _FlashcardDeckListPageState();
}

class _FlashcardDeckListPageState extends State<FlashcardDeckListPage> {
  List<FlashcardDeck> _decks = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      await FlashcardService().syncClassDecks();
      await FlashcardService().refreshSubmissions();
    } catch (_) {
      // Best effort: local decks must still load when the hub is offline.
    }
    final decks = await FlashcardService().listDecks();
    if (!mounted) return;
    setState(() {
      _decks = decks;
      _loading = false;
    });
  }

  Future<void> _openDeck(FlashcardDeck deck) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => FlashcardStudyPage(deckId: deck.id)),
    );
    if (mounted) await _load();
  }

  Future<void> _createDeck() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const FlashcardEditPage()),
    );
    if (mounted) await _load();
  }

  Future<void> _editDeck(FlashcardDeck deck) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => FlashcardEditPage(deckId: deck.id)),
    );
    if (mounted) await _load();
  }

  Future<void> _sendToTeacher(FlashcardDeck deck) async {
    await FlashcardService().submitDeck(deck.id);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.flashcardDeckSent)),
    );
    await _load();
  }

  Future<void> _exportDeck(FlashcardDeck deck) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/flashcards_${deck.id}.json');
      await file.writeAsString(FlashcardService().exportDeckJson(deck));
    } catch (e) {
      debugPrint('Flashcard export failed: $e');
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.flashcardDeckExported)),
    );
  }

  Future<void> _confirmDeleteDeck(FlashcardDeck deck) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.flashcardDeleteDeck),
        content: Text(deck.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.buttonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.flashcardDeleteDeck),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await FlashcardService().deleteDeck(deck.id);
    if (mounted) await _load();
  }

  Future<void> _onMenuSelected(FlashcardDeck deck, String value) async {
    switch (value) {
      case 'edit':
        await _editDeck(deck);
      case 'send':
        await _sendToTeacher(deck);
      case 'export':
        await _exportDeck(deck);
      case 'delete':
        await _confirmDeleteDeck(deck);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        title: Text(
          l10n.flashcardMyDecks,
          style: tt.titleMedium?.copyWith(color: cs.onSurface),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.flashcardNewDeck,
        onPressed: _createDeck,
        child: const Icon(Icons.add),
      ),
      body: _buildBody(cs, tt, l10n),
    );
  }

  Widget _buildBody(ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_decks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.style_outlined, size: 64.sp, color: cs.onSurfaceVariant),
            SizedBox(height: AppSpacing.md.h),
            Text(
              l10n.flashcardNoDecks,
              style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView.builder(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm.h),
      itemCount: _decks.length,
      itemBuilder: (ctx, index) {
        final deck = _decks[index];
        return _DeckCard(
          deck: deck,
          onTap: () => unawaited(_openDeck(deck)),
          onMenuSelected: (value) => unawaited(_onMenuSelected(deck, value)),
        );
      },
        ),
      ),
    );
  }
}

/// A single deck row with due chip, submission status, and overflow menu.
class _DeckCard extends StatelessWidget {
  const _DeckCard({
    required this.deck,
    required this.onTap,
    required this.onMenuSelected,
  });

  final FlashcardDeck deck;
  final VoidCallback onTap;
  final ValueChanged<String> onMenuSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    return Card(
      margin: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.xs.h),
      child: ListTile(
        onTap: onTap,
        title: Text(
          deck.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tt.titleMedium?.copyWith(
            color: cs.onSurface,
            fontWeight: AppSpacing.weightStrong,
          ),
        ),
        subtitle: _buildSubtitle(cs, tt, l10n),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (deck.dueCount > 0) ...[
              Tooltip(
                message: l10n.flashcardDueToday,
                child: _DueChip(count: deck.dueCount),
              ),
              SizedBox(width: AppSpacing.sm.w),
            ],
            PopupMenuButton<String>(
              onSelected: onMenuSelected,
              itemBuilder: (ctx) => [
                PopupMenuItem(value: 'edit', child: Text(l10n.flashcardEditDeck)),
                if (deck.source == 'local' && deck.submissionStatus != 'pending')
                  PopupMenuItem(value: 'send', child: Text(l10n.flashcardSendToTeacher)),
                PopupMenuItem(value: 'export', child: Text(l10n.flashcardExportDeck)),
                PopupMenuItem(value: 'delete', child: Text(l10n.flashcardDeleteDeck)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildSubtitle(ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    final List<Widget> children = [];
    if (deck.source == 'hub') {
      children.add(_StatusChip(
        label: l10n.flashcardStatusApproved,
        foreground: cs.primary,
        background: cs.primaryContainer,
      ));
    } else if (deck.submissionStatus.isNotEmpty) {
      switch (deck.submissionStatus) {
        case 'pending':
          children.add(_StatusChip(
            label: l10n.flashcardStatusPending,
            foreground: cs.tertiary,
            background: cs.tertiaryContainer,
          ));
          break;
        case 'approved':
          children.add(_StatusChip(
            label: l10n.flashcardStatusApproved,
            foreground: cs.primary,
            background: cs.primaryContainer,
          ));
          break;
        case 'rejected':
          children.add(_StatusChip(
            label: l10n.flashcardStatusRejected,
            foreground: cs.error,
            background: cs.errorContainer,
          ));
          break;
      }
      if (deck.submissionStatus == 'rejected' && deck.submissionReason.isNotEmpty) {
        children.add(
          Padding(
            padding: EdgeInsets.only(top: AppSpacing.xs.h),
            child: Text(
              l10n.flashcardRejectedReason(deck.submissionReason),
              style: tt.bodySmall?.copyWith(color: cs.error),
            ),
          ),
        );
      }
    }
    if (children.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

/// The count of cards due today for a deck.
class _DueChip extends StatelessWidget {
  const _DueChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm.w, vertical: AppSpacing.xs.h),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        '$count',
        style: tt.labelMedium?.copyWith(
          color: cs.onPrimary,
          fontWeight: AppSpacing.weightStrong,
        ),
      ),
    );
  }
}

/// A small rounded badge showing a submission or source status.
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(top: AppSpacing.xs.h),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm.w, vertical: AppSpacing.xs.h),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        ),
        child: Text(
          label,
          style: tt.labelSmall?.copyWith(
            color: foreground,
            fontWeight: AppSpacing.weightStrong,
          ),
        ),
      ),
    );
  }
}