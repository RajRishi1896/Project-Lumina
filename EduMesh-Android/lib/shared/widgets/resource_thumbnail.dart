import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/lumina_colors.dart';
import '../../core/models/resource_model.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/file_utils.dart';

/// A thumbnail image for a [ResourceModel].
///
/// Fetches the thumbnail from the server via `/api/thumbnail/{id}` and
/// falls back to a coloured icon (or a "WIKI" label for kiwix resources)
/// when the image is unavailable.
class ResourceThumbnail extends StatelessWidget {
  /// The resource whose thumbnail should be displayed.
  final ResourceModel resource;

  /// The width and height of the thumbnail widget.
  final double size;

  const ResourceThumbnail({super.key, required this.resource, this.size = 56});

  /// A thumbnail for a bare resource id/title/type pair, without a full
  /// [ResourceModel] -- used by [ResourceCard]. Not const because it builds
  /// a non-const [ResourceModel] internally.
  ResourceThumbnail.forCard({
    super.key,
    required String id,
    required String title,
    required ResourceType type,
    this.size = 80,
  }) : resource = ResourceModel(id: id, title: title, type: type, subject: '', grade: '');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8.r),
      child: SizedBox(
        width: size.w,
        height: size.h,
        child: _buildContent(context, cs),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ColorScheme cs) {
    final l10n = AppLocalizations.of(context)!;
    final fallback = _buildFallbackIcon(context, cs, l10n);
    if (resource.id.isEmpty) return fallback;
    final thumbUrl = '${ApiClient.baseUrl}/api/thumbnail/${resource.id}';
    return Image.network(
      thumbUrl,
      fit: BoxFit.cover,
      semanticLabel: resource.title,
      cacheWidth: (size * MediaQuery.of(context).devicePixelRatio).round(),
      cacheHeight: (size * MediaQuery.of(context).devicePixelRatio).round(),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: cs.surfaceContainerHighest,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }

  Widget _buildFallbackIcon(BuildContext context, ColorScheme cs, AppLocalizations l10n) {
    final tt = Theme.of(context).textTheme;
    final icon = iconForType(resource.type);
    final label = resource.type == ResourceType.kiwix ? l10n.thumbnailWikiLabel : null;
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: label != null
            ? Text(label, style: tt.labelSmall?.copyWith(fontWeight: AppSpacing.weightStrong, color: cs.onSurfaceVariant, letterSpacing: 1))
            : Icon(icon, size: size * 0.45, color: cs.onSurfaceVariant),
      ),
    );
  }

}

/// A card showing a resource with a large thumbnail, a type badge overlay, a
/// metadata row (size / duration / pages), and an optional "Ready" chip.
///
/// The card is const-friendly and receives its data as primitives so both
/// [ResourceModel] and [CourseResource] callers can use it. Tapping calls
/// [onTap]; pass `null` to disable.
class ResourceCard extends StatelessWidget {
  /// The resource id, used for the thumbnail URL and the Ready check.
  final String resourceId;

  final String title;

  /// The resource type, which drives the badge and metadata fields shown.
  final ResourceType type;

  /// The file size in bytes (0 hides the size segment).
  final int fileSize;

  /// The page count for PDFs (0 hides the pages segment).
  final int pageCount;

  /// The duration in seconds for videos (0 hides the duration segment).
  final int durationSeconds;

  final bool isReady;

  /// An optional subtitle shown under the title (e.g. course progress state).
  final String? subtitle;

  /// An optional trailing widget (e.g. download/bookmark actions).
  final Widget? trailing;

  /// The card background colour; defaults to the theme card colour.
  final Color? backgroundColor;

  /// An opacity applied to the whole card (e.g. dimmed while locked).
  final double opacity;

  /// Called when the card is tapped; `null` disables the tap.
  final VoidCallback? onTap;

  const ResourceCard({
    super.key,
    required this.resourceId,
    required this.title,
    required this.type,
    this.fileSize = 0,
    this.pageCount = 0,
    this.durationSeconds = 0,
    this.isReady = false,
    this.subtitle,
    this.trailing,
    this.backgroundColor,
    this.opacity = 1,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: backgroundColor,
      clipBehavior: Clip.antiAlias,
      child: Opacity(
        opacity: opacity,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildThumbnailWithBadge(),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: tt.titleSmall?.copyWith(color: cs.onSurface)),
                      if (subtitle != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      _buildMetadataRow(tt, cs, l10n),
                      if (isReady) ...[
                        const SizedBox(height: AppSpacing.sm),
                        _buildReadyChip(tt, l10n),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnailWithBadge() {
    return Stack(
      children: [
        ResourceThumbnail.forCard(
          id: resourceId,
          title: title,
          type: type,
        ),
        if (_badgeLabel(type) != null)
          Positioned(
            top: AppSpacing.xs,
            left: AppSpacing.xs,
            child: _TypeBadge(label: _badgeLabel(type)!, type: type),
          ),
      ],
    );
  }

  /// Returns the badge label for [type], or `null` for kiwix (no coloured
  /// badge -- the thumbnail already shows the "WIKI" fallback label).
  /// Labels are English type markers by design, not translatable strings.
  static String? _badgeLabel(ResourceType type) {
    switch (type) {
      case ResourceType.videos:
        return 'VIDEO';
      case ResourceType.textbook:
      case ResourceType.notes:
      case ResourceType.pyq:
      case ResourceType.pastPaper:
        return 'PDF';
      case ResourceType.quiz:
        return 'INTERACTIVE';
      case ResourceType.kiwix:
        return null;
    }
  }

  Widget _buildMetadataRow(TextTheme tt, ColorScheme cs, AppLocalizations l10n) {
    final parts = <String>[
      if (fileSize > 0) _formatBytes(fileSize, l10n),
      if (type == ResourceType.videos && durationSeconds > 0)
        _formatDuration(durationSeconds),
      if (_isPdfType(type) && pageCount > 0) l10n.cardPages(pageCount),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(parts.join(' \u00B7 '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant));
  }

  bool _isPdfType(ResourceType type) {
    switch (type) {
      case ResourceType.textbook:
      case ResourceType.notes:
      case ResourceType.pyq:
      case ResourceType.pastPaper:
        return true;
      case ResourceType.videos:
      case ResourceType.quiz:
      case ResourceType.kiwix:
        return false;
    }
  }

  Widget _buildReadyChip(TextTheme tt, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: LuminaColors.badgeInteractiveBg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded, size: 14, color: LuminaColors.badgeInteractive),
          const SizedBox(width: AppSpacing.xs),
          Text(l10n.cardReady,
              style: tt.labelSmall?.copyWith(
                  color: LuminaColors.badgeInteractive,
                  fontWeight: AppSpacing.weightStrong)),
        ],
      ),
    );
  }
}

/// The small coloured type-marker chip overlaid on a [ResourceCard] thumbnail.
class _TypeBadge extends StatelessWidget {
  final String label;
  final ResourceType type;

  const _TypeBadge({required this.label, required this.type});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final (bg, fg) = switch (type) {
      ResourceType.videos => (LuminaColors.badgeVideoBg, LuminaColors.badgeVideo),
      ResourceType.quiz => (LuminaColors.badgeInteractiveBg, LuminaColors.badgeInteractive),
      _ => (LuminaColors.badgePdfBg, LuminaColors.badgePdf),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(label,
          style: tt.labelSmall?.copyWith(
              color: fg,
              fontWeight: AppSpacing.weightStrong,
              letterSpacing: 1)),
    );
  }
}

/// Formats [bytes] as a human-readable size string ("12.5 MB", "1.2 GB").
/// Unit ARB keys carry a leading space, so no literal separator is added.
String _formatBytes(int bytes, AppLocalizations l10n) {
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)}${l10n.unitKilobytes}';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}${l10n.unitMegabytes}';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}${l10n.unitGigabytes}';
}

/// Formats [seconds] as "4:32" or "1:02:05".
String _formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}
