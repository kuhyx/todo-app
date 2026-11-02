# Fit every main screen on one phone screen

## what
Todo's main screen is the notes list (ListView.separated). Convert it to a dense note-tile grid that fits the screen, paged by swipe.

## where
/home/kuhy/src/todo; screens to convert:
- lib/ui/notes_list_screen.dart: Notes — ListView.separated of notes -> 2-column title tiles with priority/status color, filter chips, paged; body/meta in long-press sheet (note_actions_sheet.dart)
Exempt: note editor and capture form (free-text editor), settings, GitHub mirror and cloud-image settings (settings)

## must
- no vertical scrolling on converted screens at 1080x2400 with status bar + nav inset
- secondary metadata/actions behind long-press or a tap sheet, not dropped
- must not: change data/sync/storage code
- optional: reuse `FitGrid` from ~/src/utils/design_system (first tag after design_system-v0.2.1); bump the app's design_system pin to that tag

## done
A widget test per converted screen at Pixel 6a geometry (`physicalSize = Size(1080, 2400)`, `devicePixelRatio = 2.625`, `padding = FakeViewPadding(top: 132, bottom: 63)`, real nav bar + mini-player/bottom chrome pumped) asserts no vertical Scrollable has maxScrollExtent > 0 and the primary actions are hit-testable; `flutter test --reporter=compact` exits 0.

## verify
Pixel 6a 23181JEGR08034, release build via ~/.claude/scripts/phone_deploy.sh, screenshot from phone_vd.sh per converted screen.

## read first
- ~/.claude/skills/build-mobile-app/SKILL.md (R7)
- ~/src/tunedeck Home tab implementation (reference pattern)

REMOVE ME AFTER FINISH
