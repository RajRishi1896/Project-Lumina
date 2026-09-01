import 'package:flutter/material.dart';
import 'package:edumesh_android/core/navigation/lumina_transitions.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:edumesh_android/core/constants/app_spacing.dart';
import 'package:edumesh_android/core/models/flashcard_models.dart';
import 'package:edumesh_android/core/services/flashcard_service.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

import 'flashcard_study_page.dart';

/// Deck details (stats, actions, card previews) and the deck editor (title,
/// category, front/back cards), as two modes of one page. A null [deckId]
/// opens straight into the editor for a new deck.
class FlashcardEditPage extends StatefulWidget {
  /// The deck to show/edit; null creates a new deck.
  final String? deckId;

  /// Creates the deck page for [deckId], or a new-deck editor when null.
  const FlashcardEditPage({super.key, this.deckId});

  @override
  State<FlashcardEditPage> createState() => _FlashcardEditPageState();
}

class _FlashcardEditPageState extends State<FlashcardEditPage> {
  static const int _maxCards = 40;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _subjectController = TextEditingController();
  List<({TextEditingController front, TextEditingController back})> _cardControllers = [];

  bool _loading = true;
  bool _editorMode = false;
  bool _saving = false;
  bool _savedOnce = false;
  bool _syncing = false;
  bool _synced = false;
  FlashcardDeck? _deck;

  bool get _isNew => widget.deckId == null;

  @override
  void initState() {
    super.initState();
    _editorMode = _isNew;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _titleController.dispose();
    _subjectController.dispose();
    for (final c in _cardControllers) {
      c.front.dispose();
      c.back.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final id = widget.deckId;
    if (id == null) {
      _cardControllers = [
        (front: TextEditingController(), back: TextEditingController()),
      ];
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    final deck = await FlashcardService().getDeck(id);
    if (!mounted) return;
    if (deck == null) {
      Navigator.pop(context);
      return;
    }
    _titleController.text = deck.title;
    _subjectController.text = deck.subject;
    _cardControllers = [
      for (final c in deck.cards)
        (
          front: TextEditingController(text: c.front),
          back: TextEditingController(text: c.back),
        ),
    ];
    setState(() {
      _deck = deck;
      _loading = false;
    });
  }

  void _addCard() {
    if (_cardControllers.length >= _maxCards) return;
    setState(() {
      _cardControllers = [
        ..._cardControllers,
        (front: TextEditingController(), back: TextEditingController()),
      ];
    });
  }

  void _removeCard(int index) {
    final pair = _cardControllers[index];
    pair.front.dispose();
    pair.back.dispose();
    setState(() {
      _cardControllers.removeAt(index);
    });
  }

  Future<void> _saveDeck() async {
    if (_saving) return;
    if (_cardControllers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.flashcardNoCards)),
      );
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // Form.validate() only reaches rows the list has built; sweep every
    // controller so offscreen cards are covered too.
    final hasBlank = _cardControllers.any(
        (c) => c.front.text.trim().isEmpty || c.back.text.trim().isEmpty);
    if (hasBlank) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.errorFillAllFields)),
      );
      return;
    }
    setState(() => _saving = true);
    final title = _titleController.text.trim();
    final subject = _subjectController.text.trim();
    final cards = [
      for (final c in _cardControllers)
        (front: c.front.text.trim(), back: c.back.text.trim()),
    ];
    try {
      final id = widget.deckId;
      if (id == null) {
        await FlashcardService().createDeck(title, subject, cards);
      } else {
        await FlashcardService().updateDeck(id, title, subject, cards);
      }
    } catch (e) {
      debugPrint('Save deck failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      return;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _savedOnce = true;
    });
  }

  Future<void> _previewDeck() async {
    final id = widget.deckId;
    if (id == null) return;
    await Navigator.push<void>(
      context,
      luminaRoute(builder: (_) => FlashcardStudyPage(deckId: id)),
    );
    if (mounted) await _load();
  }

  Future<void> _downloadDeck() async {
    if (_syncing || _synced) return;
    setState(() => _syncing = true);
    await FlashcardService().syncClassDecks();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _synced = true;
    });
    final deck = widget.deckId == null
        ? null
        : await FlashcardService().getDeck(widget.deckId!);
    if (deck != null && mounted) {
      _titleController.text = deck.title;
      _subjectController.text = deck.subject;
    }
  }

  Future<void> _deleteDeck() async {
    final l10n = AppLocalizations.of(context)!;
    final id = widget.deckId;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.flashcardDeleteDeck),
        content: Text(l10n.flashcardDeleteDeck),
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
    await FlashcardService().deleteDeck(id);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _sendToTeacher() async {
    final id = widget.deckId;
    if (id == null) return;
    final l10n = AppLocalizations.of(context)!;
    await FlashcardService().submitDeck(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.flashcardDeckSent)),
    );
  }

  Future<void> _resetProgress() async {
    final id = widget.deckId;
    if (id == null) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.flashcardResetProgress),
        content: Text(l10n.flashcardResetProgressConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.buttonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.flashcardResetProgress),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await FlashcardService().resetDeckProgress(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.flashcardProgressReset)),
    );
    await _load();
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
          _editorMode
              ? (_isNew ? l10n.flashcardNewDeck : l10n.flashcardEditDeck)
              : l10n.flashcardMyDecks,
          style: tt.titleMedium?.copyWith(color: cs.onSurface),
        ),
        actions: [
          if (!_editorMode && !_isNew && !_loading)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete') _deleteDeck();
                if (value == 'send') _sendToTeacher();
                if (value == 'reset') _resetProgress();
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(value: 'send', child: Text(l10n.flashcardDeckSent)),
                PopupMenuItem(value: 'reset', child: Text(l10n.flashcardResetProgress)),
                PopupMenuItem(
                    value: 'delete', child: Text(l10n.flashcardDeleteDeck)),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: _editorMode
                  ? _buildEditor(cs, tt, l10n)
                  : _buildDetails(cs, tt, l10n),
            ),
    );
  }

  // --- Details mode -------------------------------------------------------

  Widget _buildDetails(ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    final deck = _deck;
    if (deck == null) return const SizedBox.shrink();
    final isHub = deck.source == 'hub';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView(
          padding: EdgeInsets.all(AppSpacing.lg.w),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    deck.title,
                    style: tt.headlineSmall?.copyWith(
                      color: cs.onSurface,
                      fontWeight: AppSpacing.weightDisplay,
                    ),
                  ),
                ),
                if (isHub) ...[
                  SizedBox(width: AppSpacing.sm.w),
                  _OfficialBadge(cs: cs, tt: tt, label: l10n.flashcardOfficial),
                ],
              ],
            ),
            if (deck.subject.isNotEmpty) ...[
              SizedBox(height: AppSpacing.xs.h),
              Text(
                deck.subject,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
            SizedBox(height: AppSpacing.md.h),
            _StatsBento(deck: deck),
            SizedBox(height: AppSpacing.lg.h),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                minimumSize: Size.fromHeight(AppSpacing.touchTarget.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
              ),
              onPressed: () async {
                await Navigator.push<void>(
                  context,
                  luminaRoute(
                      builder: (_) => FlashcardStudyPage(deckId: deck.id)),
                );
                if (mounted) await _load();
              },
              icon: const Icon(Icons.play_arrow),
              label: Text(l10n.flashcardStudyNow),
            ),
            SizedBox(height: AppSpacing.sm.h),
            Row(
              children: [
                Expanded(
                  child: _OutlinedAction(
                    icon: Icons.edit_outlined,
                    label: l10n.flashcardEditDeck,
                    onTap: () => setState(() => _editorMode = true),
                  ),
                ),
                SizedBox(width: AppSpacing.sm.w),
                if (isHub)
                  Expanded(
                    child: _OutlinedAction(
                      icon: _synced
                          ? Icons.offline_pin
                          : Icons.download_outlined,
                      label: _syncing
                          ? l10n.flashcardDownloading
                          : (_synced
                              ? l10n.flashcardDownloaded
                              : l10n.flashcardDownload),
                      onTap: _downloadDeck,
                    ),
                  ),
              ],
            ),
            SizedBox(height: AppSpacing.section.h),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.flashcardCardPreview,
                    style: tt.titleMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: AppSpacing.weightDisplay,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: AppSpacing.md.h),
            for (final card in deck.cards)
              Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.sm.h),
                child: _PreviewCard(card: card),
              ),
            SizedBox(height: AppSpacing.touchTarget.h),
          ],
        ),
      ),
    );
  }

  // --- Editor mode --------------------------------------------------------

  Widget _buildEditor(ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
                child: ListView(
                  padding: EdgeInsets.all(AppSpacing.lg.w),
                  children: [
                    Text(
                      l10n.flashcardDeckTitle,
                      style: tt.labelLarge?.copyWith(color: cs.onSurface),
                    ),
                    SizedBox(height: AppSpacing.xs.h),
                    TextFormField(
                      controller: _titleController,
                      maxLength: 80,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: cs.surface,
                        suffixIcon: _savedOnce
                            ? Padding(
                                padding:
                                    EdgeInsets.only(right: AppSpacing.sm.w),
                                child: Chip(
                                  label: Text(l10n.flashcardSavedChip),
                                  labelStyle: tt.labelSmall?.copyWith(
                                      color: cs.onTertiaryContainer),
                                  backgroundColor: cs.tertiary.withValues(
                                      alpha: 0.18),
                                  visualDensity: VisualDensity.compact,
                                ),
                              )
                            : null,
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusLg),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusLg),
                          borderSide:
                              BorderSide(color: cs.tertiary, width: 2),
                        ),
                      ),
                      style: tt.bodyLarge?.copyWith(color: cs.onSurface),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? l10n.flashcardTitleRequired
                          : null,
                    ),
                    SizedBox(height: AppSpacing.lg.h),
                    Text(
                      l10n.flashcardCategory,
                      style: tt.labelLarge?.copyWith(color: cs.onSurface),
                    ),
                    SizedBox(height: AppSpacing.xs.h),
                    TextFormField(
                      controller: _subjectController,
                      maxLength: 40,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: cs.surface,
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusLg),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusLg),
                          borderSide:
                              BorderSide(color: cs.tertiary, width: 2),
                        ),
                      ),
                      style: tt.bodyLarge?.copyWith(color: cs.onSurface),
                    ),
                    Divider(
                        height: AppSpacing.section.h,
                        color: cs.outlineVariant),
                    Row(
                      children: [
                        Text(
                          l10n.flashcardCardPreview,
                          style: tt.titleMedium?.copyWith(
                            color: cs.onSurface,
                            fontWeight: AppSpacing.weightDisplay,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          l10n.flashcardCardsCount(_cardControllers.length),
                          style: tt.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                    SizedBox(height: AppSpacing.md.h),
                    for (var i = 0; i < _cardControllers.length; i++)
                      Padding(
                        padding: EdgeInsets.only(bottom: AppSpacing.md.h),
                        child: _EditorCardRow(
                          index: i,
                          frontController: _cardControllers[i].front,
                          backController: _cardControllers[i].back,
                          onDelete: () => _removeCard(i),
                        ),
                      ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: Size.fromHeight(AppSpacing.touchTarget.h),
                        side: BorderSide(color: cs.outlineVariant, width: 2),
                        foregroundColor: cs.onSurfaceVariant,
                      ),
                      onPressed: _addCard,
                      icon: const Icon(Icons.add),
                      label: Text(l10n.flashcardAddCard),
                    ),
                    SizedBox(height: AppSpacing.touchTarget.h),
                  ],
                ),
              ),
            ),
          ),
          _EditorBottomBar(
            onPreview: _isNew ? null : _previewDeck,
            onSave: _saveDeck,
            saving: _saving,
          ),
        ],
      ),
    );
  }
}

/// Teal "Official" badge for hub-published decks.
class _OfficialBadge extends StatelessWidget {
  const _OfficialBadge({required this.cs, required this.tt, required this.label});

  final ColorScheme cs;
  final TextTheme tt;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.sm.w, vertical: AppSpacing.xs.h),
      decoration: BoxDecoration(
        color: cs.secondary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: cs.secondary),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_outlined, size: 14.sp, color: cs.secondary),
          SizedBox(width: AppSpacing.xs.w),
          Text(
            label,
            style: tt.labelSmall?.copyWith(color: cs.secondary),
          ),
        ],
      ),
    );
  }
}

/// Details stats bento: total cards, mastered, mastery progress bar.
class _StatsBento extends StatelessWidget {
  const _StatsBento({required this.deck});

  final FlashcardDeck deck;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    final daysSinceStudied = deck.lastStudiedAt <= 0
        ? null
        : DateTime.now()
                .difference(DateTime.fromMillisecondsSinceEpoch(deck.lastStudiedAt))
                .inDays;

    return Container(
      padding: EdgeInsets.all(AppSpacing.lg.w),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _StatCell(
                  icon: Icons.style_outlined,
                  iconColor: cs.primary,
                  value: '${deck.cards.length}',
                  label: l10n.flashcardTotalCards,
                ),
              ),
              Expanded(
                child: _StatCell(
                  icon: Icons.school_outlined,
                  iconColor: cs.secondary,
                  value: '${deck.masteredCount}',
                  label: l10n.flashcardMastered,
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.md.h),
          Row(
            children: [
              Text(
                l10n.flashcardMasteryProgress.toUpperCase(),
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              Text(
                '${deck.progressPercent}%',
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.xs.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            child: LinearProgressIndicator(
              value: deck.progressPercent / 100,
              minHeight: 8.h,
              backgroundColor: cs.primaryContainer,
              valueColor: AlwaysStoppedAnimation(cs.tertiary),
            ),
          ),
          if (daysSinceStudied != null) ...[
            SizedBox(height: AppSpacing.sm.h),
            Row(
              children: [
                Icon(Icons.history,
                    size: 16.sp, color: cs.onSurfaceVariant),
                SizedBox(width: AppSpacing.xs.w),
                Text(
                  l10n.flashcardLastStudied(daysSinceStudied),
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One stat cell: icon, big number, caps label.
class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 24.sp, color: iconColor),
        SizedBox(height: AppSpacing.xs.h),
        Text(
          value,
          style: tt.headlineSmall?.copyWith(
            color: cs.onSurface,
            fontWeight: AppSpacing.weightDisplay,
          ),
        ),
        Text(
          label.toUpperCase(),
          style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Outlined pill action button (Edit Deck / Download).
class _OutlinedAction extends StatelessWidget {
  const _OutlinedAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: cs.onSurface,
        side: BorderSide(color: cs.outlineVariant),
        minimumSize: Size.fromHeight(AppSpacing.touchTarget.h),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        ),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 20.sp),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tt.labelLarge?.copyWith(color: cs.onSurface),
      ),
    );
  }
}

/// Front/back preview card on the details screen.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.card});

  final FlashcardCard card;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSpacing.lg.w),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.flashcardFront,
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          SizedBox(height: AppSpacing.xs.h),
          Text(
            card.front,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tt.bodyLarge?.copyWith(color: cs.onSurface),
          ),
          Divider(height: AppSpacing.lg.h, color: cs.outlineVariant),
          Text(
            l10n.flashcardBack,
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          SizedBox(height: AppSpacing.xs.h),
          Text(
            card.back,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// One editor card: FRONT and BACK labelled text areas with a delete action.
class _EditorCardRow extends StatelessWidget {
  const _EditorCardRow({
    required this.index,
    required this.frontController,
    required this.backController,
    required this.onDelete,
  });

  final int index;
  final TextEditingController frontController;
  final TextEditingController backController;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSpacing.lg.w),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l10n.flashcardFront.toUpperCase(),
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              IconButton(
                tooltip: l10n.flashcardDeleteCard,
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline,
                    size: 20.sp, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          TextFormField(
            controller: frontController,
            maxLines: 2,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: _editorFieldDecoration(cs),
            style: tt.bodyMedium?.copyWith(color: cs.onSurface),
          ),
          SizedBox(height: AppSpacing.md.h),
          Text(
            l10n.flashcardBack.toUpperCase(),
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          SizedBox(height: AppSpacing.xs.h),
          TextFormField(
            controller: backController,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: _editorFieldDecoration(cs),
            style: tt.bodyMedium?.copyWith(color: cs.onSurface),
          ),
        ],
      ),
    );
  }

  /// Shared grey filled-field decoration for the front/back editors.
  InputDecoration _editorFieldDecoration(ColorScheme cs) {
    return InputDecoration(
      filled: true,
      fillColor: cs.surfaceContainerLow,
      contentPadding:
          EdgeInsets.symmetric(horizontal: AppSpacing.md.w, vertical: AppSpacing.sm.h),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        borderSide: BorderSide(color: cs.tertiary, width: 2),
      ),
    );
  }
}

/// Pinned editor bottom bar: Preview | Save Deck.
class _EditorBottomBar extends StatelessWidget {
  const _EditorBottomBar({
    required this.onPreview,
    required this.onSave,
    required this.saving,
  });

  final VoidCallback? onPreview;
  final VoidCallback onSave;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      padding: EdgeInsets.all(AppSpacing.lg.w),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.primary,
                side: BorderSide(color: cs.primary, width: 2),
                minimumSize: Size.fromHeight(AppSpacing.touchTarget.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                ),
              ),
              onPressed: onPreview,
              child: Text(l10n.flashcardPreview),
            ),
          ),
          SizedBox(width: AppSpacing.md.w),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: cs.secondary,
                foregroundColor: cs.onSecondary,
                minimumSize: Size.fromHeight(AppSpacing.touchTarget.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                ),
              ),
              onPressed: saving ? null : onSave,
              icon: saving
                  ? SizedBox(
                      width: 16.sp,
                      height: 16.sp,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(l10n.flashcardSaveDeck),
            ),
          ),
        ],
      ),
    );
  }
}
