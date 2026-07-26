import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note_template.dart';

void main() {
  const spec = NoteTemplate.llmDesignSpec;
  const blank = NoteTemplate.blank;

  group('assemble', () {
    test(
      'builds # title + ## sections with italic guidance, dropping empty',
      () {
        final text = assemble(spec, {
          'title': 'Add dark mode',
          'what': 'A theme toggle.',
          'must': '- respects system theme',
          // everything else blank → dropped
        });

        expect(text, contains('# Add dark mode'));
        expect(text, contains('## what'));
        expect(text, contains('_${spec.sections[1].helper}_'));
        expect(text, contains('A theme toggle.'));
        expect(text, contains('## must'));
        // Dropped empty sections leave no heading behind.
        expect(text, isNot(contains('## verify')));
        expect(text, isNot(contains('## read first')));
      },
    );

    test('the multi-word "read first" label round-trips as a heading', () {
      final text = assemble(spec, {
        'title': 'T',
        'refs': '- https://example.com/doc',
      });
      expect(text, contains('## read first'));

      final parsed = parse(spec, text);
      expect(parsed.conforms, isTrue);
      expect(parsed.values['refs'], '- https://example.com/doc');
    });

    test('omits the title line when the title is blank', () {
      final text = assemble(spec, {'what': 'something'});
      // No `# ` title line; the body starts straight at the first section.
      expect(text.startsWith('# '), isFalse);
      expect(text.startsWith('## what'), isTrue);
    });

    test('freeform template returns the trimmed body verbatim', () {
      expect(assemble(blank, {'body': 'just text\n\n'}), 'just text');
      expect(assemble(blank, {}), '');
    });
  });

  group('parse round-trip', () {
    test('assemble(parse(text)) is idempotent for conforming text', () {
      final text = assemble(spec, {
        'title': 'Title here',
        'what': 'The what.',
        'done': 'I can X and Y happens',
      });

      final parsed = parse(spec, text);
      expect(parsed.conforms, isTrue);
      expect(parsed.values['title'], 'Title here');
      expect(parsed.values['what'], 'The what.');
      expect(parsed.values['done'], 'I can X and Y happens');
      // Re-assembling the parsed values reproduces the exact text.
      expect(assemble(spec, parsed.values), text);
    });

    test('legacy "what —" notes are reported non-conforming', () {
      const legacy = 'Shutdown timer\n\nwhat — a timer\nwhere — new app';
      final parsed = parse(spec, legacy);
      expect(parsed.conforms, isFalse);
    });

    test('the pre-2026-07 twelve-section spec is non-conforming', () {
      // Notes written before `tech`/`ask`/`nice`/`never`/`depends`/`estimate`
      // were cut must fall back to the raw editor rather than be silently
      // stripped of the sections the template no longer knows about.
      const legacy =
          '# Old note\n\n## what\na thing\n\n## tech\nFlutter 3.32\n\n'
          '## must\n- do it\n\n## estimate\nM';
      final parsed = parse(spec, legacy);
      expect(parsed.conforms, isFalse);
      // The dropped sections are not resurrected as values either.
      expect(parsed.values.containsKey('tech'), isFalse);
      expect(parsed.values.containsKey('estimate'), isFalse);
    });

    test('the section set is the audited seven', () {
      expect(spec.sections.map((s) => s.key), [
        'title',
        'what',
        'where',
        'must',
        'done',
        'verify',
        'refs',
      ]);
    });

    test('out-of-order / duplicate headings are non-conforming', () {
      const text = '# T\n\n## done\nx\n\n## what\ny';
      expect(parse(spec, text).conforms, isFalse);

      const dup = '# T\n\n## what\na\n\n## what\nb';
      expect(parse(spec, dup).conforms, isFalse);
    });

    test('stray content before the first heading is non-conforming', () {
      const text = 'loose line\n\n## what\nv';
      expect(parse(spec, text).conforms, isFalse);
    });

    test('strips leading blank lines before a section value', () {
      // A raw-edited note may put blank lines (and no guidance) under a
      // heading; parsing must skip those blanks to recover the value.
      const text = '# T\n\n## what\n\n\nthe value';
      final parsed = parse(spec, text);
      expect(parsed.conforms, isTrue);
      expect(parsed.values['what'], 'the value');
    });

    test('a ## subheading inside a value is kept, not split out', () {
      final text = assemble(spec, {
        'title': 'T',
        'what': 'intro\n## not a real section\nmore',
      });
      final parsed = parse(spec, text);
      expect(parsed.conforms, isTrue);
      expect(parsed.values['what'], contains('## not a real section'));
    });

    test('freeform template always conforms with the whole text as body', () {
      final parsed = parse(blank, 'anything goes\nline two');
      expect(parsed.conforms, isTrue);
      expect(parsed.values['body'], 'anything goes\nline two');
    });
  });

  group('noteTitle', () {
    test('strips the leading # from a heading', () {
      expect(noteTitle('# My title\n\n## what\nx'), 'My title');
    });

    test('uses the first non-empty line for freeform notes', () {
      expect(noteTitle('\n\nfirst real line\nsecond'), 'first real line');
    });

    test('returns empty string for blank text', () {
      expect(noteTitle('   \n  '), '');
    });
  });
}
