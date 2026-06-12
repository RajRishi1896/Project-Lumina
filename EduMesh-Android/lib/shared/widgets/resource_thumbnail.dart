import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/models/resource_model.dart';
import '../../core/network/api_client.dart';

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
    final icon = _iconForType(resource.type);
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

  IconData _iconForType(ResourceType type) {
    switch (type) {
      case ResourceType.textbook:
        return Icons.menu_book_rounded;
      case ResourceType.videos:
        return Icons.play_circle_rounded;
      case ResourceType.pyq:
        return Icons.assignment_rounded;
      case ResourceType.notes:
        return Icons.note_rounded;
      case ResourceType.kiwix:
        return Icons.language_rounded;
      case ResourceType.pastPaper:
        return Icons.assignment_rounded;
    }
  }
}
