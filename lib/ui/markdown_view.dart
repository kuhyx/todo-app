import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'package:todo/images/image_ref.dart';
import 'package:todo/ui/images/image_embed.dart';

/// Tallest an image is drawn inside a rendered note.
const kInlineImageHeight = 320.0;

/// A lightweight, read-only renderer for the note format.
///
/// The app's notes use a small, known Markdown subset — an `#` title, `##`
/// section headings, italic `_guidance_` lines, `-` bullet lists and plain
/// paragraphs, plus one attached image per line (see `image_ref.dart`) — so a
/// tailored line-based renderer covers everything we emit
/// without pulling in a full Markdown engine. It keeps the quick-capture app
/// lean and is trivial to test.
///
/// The whole rendered note is wrapped in a [SelectionArea] so it can be copied
/// out in one go (the note is meant to be pasted into an LLM).
class MarkdownView extends StatelessWidget {
  /// Creates a [MarkdownView] rendering [text].
  const MarkdownView({required this.text, super.key});

  /// The raw markdown source to render.
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final widgets = <Widget>[];

    for (final line in text.split('\n')) {
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }
      if (imageRefOfLine(trimmed) case final image?) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: kInlineImageHeight),
              child: ImageEmbed(ref: image, fit: BoxFit.contain),
            ),
          ),
        );
        continue;
      }
      if (trimmed.startsWith('## ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              trimmed.substring(3).trim(),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
        continue;
      }
      if (trimmed.startsWith('# ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              trimmed.substring(2).trim(),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
        continue;
      }
      // A whole-line italic marker — used for the section guidance lines.
      if (trimmed.length >= 2 &&
          trimmed.startsWith('_') &&
          trimmed.endsWith('_')) {
        widgets.add(
          Text(
            trimmed.substring(1, trimmed.length - 1),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );
        continue;
      }
      if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: theme.textTheme.bodyLarge),
                Expanded(
                  child: Text(
                    trimmed.substring(2),
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }
      widgets.add(Text(line, style: theme.textTheme.bodyLarge));
    }

    return SelectionArea(
      child: SingleChildScrollView(
        // Caps the reading column at ~70 chars (rule 21) — the desktop
        // build is an arbitrarily wide Chrome `--app` window, so without
        // this, body text runs the full viewport width.
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kProseMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widgets,
            ),
          ),
        ),
      ),
    );
  }
}
