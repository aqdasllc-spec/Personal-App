import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/library_controller.dart';
import '../domain_tag_colors.dart';

/// A small round dot in the tag's colour (nothing when the tag has none).
class TagDot extends ConsumerWidget {
  const TagDot(this.tag, {super.key, this.size = 10, this.outlineIfNone = false});
  final String tag;
  final double size;

  /// Show an empty ring when the tag has no colour (used where the colour can be chosen).
  final bool outlineIfNone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(tagColorsProvider);
    final c = colorOfTag(colors, tag);
    if (c == null) {
      if (!outlineIfNone) return const SizedBox.shrink();
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Theme.of(context).colorScheme.outline, width: 2),
        ),
      );
    }
    return Semantics(
      label: '${colorNameOfTag(colors, tag)} tag',
      child: Container(
        key: Key('tag-dot-${tagKey(tag)}'),
        width: size,
        height: size,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      ),
    );
  }
}

/// Asks which colour a tag should have. Returns the palette index, -1 for "no colour", null when dismissed.
Future<int?> pickTagColor(BuildContext context, String tag, int? current) =>
    showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Colour for #$tag'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (var i = 0; i < tagPalette.length; i++)
              Semantics(
                button: true,
                selected: current == i,
                label: tagPalette[i].$1,
                child: InkResponse(
                  key: Key('tag-color-$i'),
                  onTap: () => Navigator.pop(ctx, i),
                  radius: 28,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: tagPalette[i].$2,
                      shape: BoxShape.circle,
                      border: current == i
                          ? Border.all(
                              color: Theme.of(ctx).colorScheme.onSurface,
                              width: 3,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('tag-color-none'),
            onPressed: () => Navigator.pop(ctx, -1),
            child: const Text('No colour'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
