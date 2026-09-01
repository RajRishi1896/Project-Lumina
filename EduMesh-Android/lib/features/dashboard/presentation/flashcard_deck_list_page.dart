import 'package:flutter/material.dart';
import 'package:edumesh_android/core/navigation/lumina_transitions.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:edumesh_android/core/constants/app_spacing.dart';
import 'package:edumesh_android/core/models/flashcard_models.dart';
import 'package:edumesh_android/core/services/flashcard_service.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

import 'flashcard_edit_page.dart';
import 'flashcard_study_page.dart';

/// The flashcard deck library: hub-published decks under Recommended, the
/// student's own decks with mastery progress under My Decks, plus search and
/// the create-deck FAB.
class FlashcardDeckListPage extends StatefulWidget {
  /// Creates the flashcard deck list page.
  const FlashcardDeckListPage({super.key});

  @override
  State<FlashcardDeckListPage> createState() => _FlashcardDeckListPageState();
}

class _FlashcardDeckListPageState extends State<FlashcardDeckListPage> {
  List<FlashcardDeck> _decks = const [];
  bool _loading = true;
  String _query = '';

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

  Future<void> _startStudy(FlashcardDeck deck) async {
    await Navigator.push<void>(
      context,
      luminaRoute(
        builder: (_) => FlashcardStudyPage(deckId: deck.id),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openEdit(FlashcardDeck deck) async {
    await Navigator.push<void>(
      context,
      luminaRoute(builder: (_) => FlashcardEditPage(deckId: deck.id)),
    );
    if (mounted) await _load();
  }

  Future<void> _createDeck() async {
    await Navigator.push<bool>(
      context,
      luminaRoute(builder: (_) => const FlashcardEditPage()),
    );
    if (mounted) await _load();
  }

  Future<void> _confirmRestartAll() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.flashcardRestartAll),
        content: Text(l10n.flashcardRestartAllConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.buttonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.flashcardRestartAll),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await FlashcardService().resetAllProgress();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.flashcardProgressReset)),
    );
    await _load();
  }

  List<FlashcardDeck> _filtered(Iterable<FlashcardDeck> decks) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return decks.toList();
    return decks
        .where((d) =>
            d.title.toLowerCase().contains(q) ||
            d.subject.toLowerCase().contains(q))
        .toList();
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
      floatingActionButton: _CreateFab(onTap: _createDeck),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
                  child: ListView(
                    padding: EdgeInsets.all(AppSpacing.lg.w),
                    children: [
                      _SearchField(
                        onChanged: (v) => setState(() => _query = v),
                      ),
                      SizedBox(height: AppSpacing.section.h),
                      ..._buildRecommended(cs, tt, l10n),
                      ..._buildMyDecks(cs, tt, l10n),
                      SizedBox(height: AppSpacing.touchTarget.h),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  List<Widget> _buildRecommended(
      ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    final hubDecks =
        _filtered(_decks.where((d) => d.source == 'hub'));
    if (hubDecks.isEmpty) return const [];
    return [
      Text(
        l10n.flashcardRecommended,
        style: tt.titleMedium?.copyWith(
          color: cs.onSurface,
          fontWeight: AppSpacing.weightDisplay,
        ),
      ),
      SizedBox(height: AppSpacing.md.h),
      for (final deck in hubDecks)
        Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.sm.h),
          child: _RecommendedCard(
            deck: deck,
            onTap: () => _startStudy(deck),
            onEdit: () => _openEdit(deck),
          ),
        ),
      SizedBox(height: AppSpacing.section.h),
    ];
  }

  List<Widget> _buildMyDecks(
      ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    final localDecks =
        _filtered(_decks.where((d) => d.source != 'hub'));
    if (localDecks.isEmpty && _query.isEmpty) {
      return [
        Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.section.h),
            child: Column(
              children: [
                Icon(Icons.style_outlined,
                    size: 64.sp, color: cs.onSurfaceVariant),
                SizedBox(height: AppSpacing.md.h),
                Text(
                  l10n.flashcardNoDecks,
                  style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    if (localDecks.isEmpty) return const [];
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              l10n.flashcardMyDecks,
              style: tt.titleMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: AppSpacing.weightDisplay,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _query = ''),
            child: Text(
              l10n.flashcardViewAll,
              style: tt.labelLarge?.copyWith(color: cs.secondary),
            ),
          ),
          if (localDecks.any((d) => d.dueCount < d.cards.length)) ...[
            SizedBox(width: AppSpacing.md.w),
            GestureDetector(
              onTap: _confirmRestartAll,
              child: Text(
                l10n.flashcardRestartAll,
                style: tt.labelLarge?.copyWith(color: cs.error),
              ),
            ),
          ],
        ],
      ),
      SizedBox(height: AppSpacing.md.h),
      for (final deck in localDecks)
        Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.sm.h),
          child: _MyDeckCard(
            deck: deck,
            onTap: () => _startStudy(deck),
            onEdit: () => _openEdit(deck),
          ),
        ),
    ];
  }
}

/// Rounded-square dark create-deck FAB from the mockup.
class _CreateFab extends StatelessWidget {
  const _CreateFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      button: true,
      label: l10n.flashcardNewDeck,
      child: Material(
        color: cs.primary,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          child: SizedBox(
            width: 56.w,
            height: 56.w,
            child: Icon(Icons.add, color: cs.onPrimary, size: 24.sp),
          ),
        ),
      ),
    );
  }
}

/// Search input styled per the library mockup.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: l10n.flashcardSearchHint,
        prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant),
        filled: true,
        fillColor: cs.surface,
        contentPadding: EdgeInsets.symmetric(vertical: AppSpacing.md.h),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
      ),
      style: tt.bodyLarge?.copyWith(color: cs.onSurface),
    );
  }
}

/// Teacher-published deck card: subject label, title, estimated time.
class _RecommendedCard extends StatelessWidget {
  const _RecommendedCard({required this.deck, required this.onTap, required this.onEdit});

  final FlashcardDeck deck;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    // ponytail: ~20 s per card is a rough estimate; the model has no duration.
    final mins = (deck.cards.length * 20 / 60).ceil();

    return _DeckCardShell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  deck.subject,
                  style: tt.labelLarge?.copyWith(color: cs.primary),
                ),
              ),
              Icon(Icons.cloud_done_outlined,
                  size: 16.sp, color: cs.secondary),
              SizedBox(width: AppSpacing.xs.w),
              GestureDetector(
                onTap: onEdit,
                child: Icon(Icons.edit_outlined,
                    size: 16.sp, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.xs.h),
          Text(
            deck.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tt.titleMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: AppSpacing.weightDisplay,
            ),
          ),
          SizedBox(height: AppSpacing.sm.h),
          Text(
            l10n.flashcardCardCountMinutes(deck.cards.length, mins),
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Student deck card: title, saffron mastery bar with %, due count.
class _MyDeckCard extends StatelessWidget {
  const _MyDeckCard({required this.deck, required this.onTap, required this.onEdit});

  final FlashcardDeck deck;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    return _DeckCardShell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  deck.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: AppSpacing.weightDisplay,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onEdit,
                child: Icon(Icons.edit_outlined,
                    size: 16.sp, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.sm.h),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  child: LinearProgressIndicator(
                    value: deck.progressPercent / 100,
                    minHeight: 8.h,
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(cs.tertiary),
                  ),
                ),
              ),
              SizedBox(width: AppSpacing.sm.w),
              SizedBox(
                width: 40.w,
                child: Text(
                  '${deck.progressPercent}%',
                  textAlign: TextAlign.end,
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.xs.h),
          Text(
            l10n.flashcardDueToday(deck.dueCount),
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Shared white bordered card shell for library entries.
class _DeckCardShell extends StatelessWidget {
  const _DeckCardShell({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(AppSpacing.lg.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: child,
        ),
      ),
    );
  }
}
