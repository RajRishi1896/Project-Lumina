import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:edumesh_android/core/constants/app_spacing.dart';
import 'package:edumesh_android/core/services/flashcard_service.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

/// Creates or edits a flashcard deck: a title plus an ordered list of
/// front/back card rows. A null [deckId] creates a new deck.
class FlashcardEditPage extends StatefulWidget {
  /// The deck to edit; null creates a new deck.
  final String? deckId;

  /// Creates the flashcard editor for [deckId], or a new deck when null.
  const FlashcardEditPage({super.key, this.deckId});

  @override
  State<FlashcardEditPage> createState() => _FlashcardEditPageState();
}

class _FlashcardEditPageState extends State<FlashcardEditPage> {
  static const int _maxCards = 40;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  List<({TextEditingController front, TextEditingController back})> _cardControllers = [];
  bool _loading = false;
  bool _showNoCardsError = false;

  @override
  void initState() {
    super.initState();
    final id = widget.deckId;
    if (id == null) {
      _cardControllers = [
        (front: TextEditingController(), back: TextEditingController()),
      ];
    } else {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(id));
    }
  }

  Future<void> _load(String deckId) async {
    final deck = await FlashcardService().getDeck(deckId);
    if (!mounted) return;
    if (deck == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _titleController.text = deck.title;
      _cardControllers = [
        for (final c in deck.cards)
          (
            front: TextEditingController(text: c.front),
            back: TextEditingController(text: c.back),
          ),
      ];
      _loading = false;
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (final c in _cardControllers) {
      c.front.dispose();
      c.back.dispose();
    }
    super.dispose();
  }

  void _addCard() {
    if (_cardControllers.length >= _maxCards) return;
    setState(() {
      _cardControllers = [
        ..._cardControllers,
        (front: TextEditingController(), back: TextEditingController()),
      ];
      _showNoCardsError = false;
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
    if (_cardControllers.isEmpty) {
      setState(() => _showNoCardsError = true);
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final title = _titleController.text.trim();
    final cards = [
      for (final c in _cardControllers)
        (front: c.front.text.trim(), back: c.back.text.trim()),
    ];
    final id = widget.deckId;
    try {
      if (id == null) {
        await FlashcardService().createDeck(title, cards);
      } else {
        await FlashcardService().updateDeck(id, title, cards);
      }
    } catch (e) {
      debugPrint('Save deck failed: $e');
      return;
    }
    if (!mounted) return;
    Navigator.pop(context, true);
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
          widget.deckId == null ? l10n.flashcardNewDeck : l10n.flashcardEditDeck,
          style: tt.titleMedium?.copyWith(color: cs.onSurface),
        ),
        actions: [
          if (!_loading)
            TextButton(
              onPressed: _saveDeck,
              child: Text(l10n.flashcardSaveDeck),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildForm(cs, tt, l10n),
    );
  }

  Widget _buildForm(ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: Form(
      key: _formKey,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg.w,
              AppSpacing.lg.h,
              AppSpacing.lg.w,
              AppSpacing.sm.h,
            ),
            child: TextFormField(
              controller: _titleController,
              maxLength: 80,
              decoration: InputDecoration(labelText: l10n.flashcardDeckTitle),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? l10n.errorFillAllFields : null,
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w),
              itemCount: _cardControllers.length,
              itemBuilder: (ctx, index) => _CardEditorRow(
                frontController: _cardControllers[index].front,
                backController: _cardControllers[index].back,
                onDelete: () => _removeCard(index),
              ),
            ),
          ),
          if (_showNoCardsError)
            Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.sm.h),
              child: Text(
                l10n.flashcardNoCards,
                style: tt.bodySmall?.copyWith(color: cs.error),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg.w,
              AppSpacing.sm.h,
              AppSpacing.lg.w,
              AppSpacing.lg.h,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: _cardControllers.length >= _maxCards ? null : _addCard,
                icon: const Icon(Icons.add),
                label: Text(l10n.flashcardAddCard),
              ),
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }
}

/// One front/back editor row with a remove-card control.
class _CardEditorRow extends StatelessWidget {
  const _CardEditorRow({
    required this.frontController,
    required this.backController,
    required this.onDelete,
  });

  final TextEditingController frontController;
  final TextEditingController backController;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.md.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: frontController,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: l10n.flashcardFront),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? l10n.errorFillAllFields : null,
          ),
          SizedBox(height: AppSpacing.sm.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: backController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: l10n.flashcardBack),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? l10n.errorFillAllFields : null,
                ),
              ),
              IconButton(
                tooltip: l10n.flashcardDeleteCard,
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline, color: cs.error),
              ),
            ],
          ),
        ],
      ),
    );
  }
}