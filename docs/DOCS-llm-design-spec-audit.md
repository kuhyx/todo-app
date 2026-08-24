# Audit of the `llm-design-spec` note template against 514 real Claude sessions

## Context

`~/todo`'s default note template (`lib/data/note_template.dart`, `NoteTemplate.llmDesignSpec`)
has 12 sections: title, what, where, tech, must, ask, nice, never, done, depends,
estimate, refs. It was designed top-down from the `<work_backlog>` format in
`~/.claude/CLAUDE.md`, never validated against what actually gets written or what
Claude actually reads.

This audit measures it against the real corpus. Everything below is measured, not
estimated. Fill rate alone was deliberately **not** used as the verdict — four
sections say "Leave blank if none" in their own helper, so a low fill rate is the
field working correctly. The discriminating test is outcome-linked: *was the section
read, and did leaving it out cause a failure?*

## Evidence base

| Source | Size |
| --- | --- |
| `~/.claude/projects/**/*.jsonl` | 514 sessions, 495 with real user prompts, **1503 prompts** |
| `~/todo/BACKLOG.md` | 49 notes — **25 structured, 24 freeform** |
| note → session join (title match) | **22 note/session pairs**, 21 of 25 notes traced |
| `~/.claude/memories/mistakes.md` + `projects/-home-kuhy/memory/feedback-*.md` | 13 dated mistakes, 33 feedback memories |

**How you actually prompt** (this frames everything else):
- median prompt **324 chars**; 44% under 200 chars; 26% under 100
- only **21 of 495 sessions (4%)** open with a structured template note
- of the 24 freeform notes, **9 start with a bare URL and 8 are *only* a URL**

Half the backlog bypasses the template entirely. Any recommendation below is
net-subtractive by default; every proposed addition has a named failure behind it.

## What Claude did not use (deterministic tests over the 22 pairs)

| Section | Filled | Provably used | Test |
| --- | ---: | ---: | --- |
| `estimate` | 22 | **1 (4%)** | word "estimate" ever appears in Claude's output |
| `done` | 22 | **4 (18%)** | the done text is quoted back at verification time |
| `refs` | 14 | **5 (35%)** | any listed URL/domain hit by WebFetch/servo-fetch/WebSearch/curl |
| `tech` | 22 | 20 (90%) echoed — but Claude opened `pubspec.yaml`/`pyproject.toml`/`CLAUDE.md` **anyway in 54%** | token overlap + manifest reads |
| `ask` | 9 | 100% asked — **but 92% asked without it too** (median 4 asks vs 5) | AskUserQuestion / ExitPlanMode calls |

The `ask` row is the sharpest result: filling it changes Claude's asking behaviour by
roughly nothing, because `~/.claude/CLAUDE.md`'s "Ask first when unsure" + the
spec-first gate already force it. The section is inert.

`done` at 18% is the most damaging: you write an observable success condition and in
four cases out of five Claude verified against a criterion it invented itself.

## Where Claude went wrong, and what would have prevented it

Hand-read of the corrections inside note-driven sessions plus the sampled corrections
across all 495 sessions. Three recurring classes, all traceable to a template gap:

1. **"Test it yourself, on the device"** — recurs verbatim across wake_alarm,
   diet_guard, screen-locker: *"as I said before, test it yourself pleeease"*,
   *"You did not install this new vesrion on phone, do not bother testing on desktop"*,
   *"isntead of making me test it test it yourself"*. Backed by five separate feedback
   memories (`feedback-device-verification-before-tests`,
   `feedback-verify-real-deployment-path`, `feedback-stop-when-device-disconnected`,
   `feedback-blind-adb-tap-unreliable`, `feedback-flutter-install-uninstalls`).
   **Gap: there is no `verify` section.** `done` conflates *what success looks like*
   with *how and where to check it*, and Claude drops the second half.
   Confirming evidence: 3 of the 7 filled `never` sections are smuggling this in —
   *"test ONLY on the phone, if the phone is NOT connected … STOP AND LET ME KNOW"*,
   *"do NOT work if the phone is NOT connected"*.

2. **Wrong *kind* of fix** — *"you are fixing the problem in a wrong way, instead of
   devising an algorithm to detect if a game is winnable 100% you are playing around
   [with the] number of pieces"*, *"I said make it possible to pass but you made it
   wayyy to easy"*. **Gap: `done` accepts a vague sentence.** This exact failure had
   to be patched globally afterwards ("Algorithmic guarantees over parameter tuning"
   in `workflow-rules.md`) — a note-level threshold would have caught it first.

3. **UI intent mismatch** — *"I was thinking more of an app icon like the one for
   network or nvidia"*, *"both sliders have bad ux"*, *"why is it upside down"*,
   *"this is ugly as it is not symmetrical"*. **Gap: nowhere to attach a visual
   reference.** `refs` is worded as reading material and is ignored 65% of the time.
   This is the same failure as the 2026-07-21 mistake entry (reference image read as
   content instead of format).

**Negative result worth stating plainly:** the other 10 of 13 entries in
`mistakes.md` — git stash, feature-branch-vs-main, killing a running game session,
mid-queue status reports, conftest-before-tests, heredoc escaping, over-claiming a
rollout complete — map to **no template section at all**. They are global process
failures. This is the argument against growing the template to chase them: it would
add fields that cannot work.

## Per-section verdict

| Section | Verdict | Grounds |
| --- | --- | --- |
| `title` | **keep** | 25/25 |
| `what` | **keep** | 25/25 — the load-bearing section |
| `where` | **keep, widen** | 25/25. Widen to allow "the fix belongs in another repo" — two corrections were exactly that (*"our INSTALLER, installing files in a WRONG FOLDER"*, *"The real fix is in ~/screen-locker (a different repo)"*) |
| `tech` | **merge into `where`** | Claude reads the manifest anyway in 54% of sessions. Load-bearing only for `where — new app: <name>`, which is where it should live |
| `must` | **keep** | 25/25 |
| `ask` | **remove** | Provably inert: 92% ask rate without it vs 100% with it. Global rules already own this |
| `nice` | **remove** | 13/25, no evidence of use, and it invites the gold-plating that `never` then has to forbid |
| `never` | **remove as a section** | 2 of 7 literally say "none"; 3 of the rest are verification constraints (→ `verify`); 1 is a `where` constraint; 1 is genuine scope (*"do not touch any other pieces of Todo app"*) → fold that shape into `must` as a "must not" line |
| `done` | **keep, tighten** | 25/25 filled but quoted back only 18%. Helper must demand a threshold or a check command, not a sentence |
| `depends` | **remove** | 13/25, zero evidence of use downstream |
| `estimate` | **remove** | 25/25 filled, referenced once in 22 sessions. Pure write-only metadata |
| `refs` | **keep, rename → `read first`** | Fetched in only 35% of cases. The name reads as "citations"; the helper already says "read first" — make the name match the instruction |
| — | **add `verify`** | See failure class 1. Where and how to check: device, command, deploy path |
| — | **add a visual-reference slot** | See failure class 3 — either a `looks like` section or image support in `read first` |

## What was implemented (2026-07-26)

**12 sections → 7:** `title, what, where, must, done, verify, read first` —
`never` and `nice` became `must not:` / `optional:` line prefixes inside `must`
rather than sections of their own, and `tech` was folded into `where`.

Landed in:
- `lib/data/note_template.dart` — the new section list, plus
  `NoteTemplate.retiredLabels`. The audit turned up a latent bug while testing
  this: `parse()` treats an unknown `## heading` as content (deliberately — users
  write subheadings inside values), which meant a legacy `## tech` block was
  silently folded into the preceding section's value **and the note still
  reported as conforming**. Opening any old note in the stepper would have
  swallowed it on the next save. Retired labels are now explicitly
  non-conforming, so such notes open in the raw editor untouched.
- `tool/migrate_backlog.dart` — export → transform → import migration, with two
  gates that throw rather than warn: every rewritten note must parse as
  conforming, and no source line may vanish except the deliberately dropped
  `ask`/`depends`/`estimate`.
- `CLAUDE.md` (this repo, which was documenting a dead `out` section) and
  `~/.claude/CLAUDE.md`'s `<work_backlog>` format.

## Part 2 — what the opening prompt leaves out, and why more fields won't fix it

The first half of this audit asked "which template sections get read". The more
useful question is "what does the opening prompt *miss*, and what would stop it
being missed". Measured over 246 sessions with a real top-level prompt (sidechain
and subagent turns excluded — they inflate every count roughly 2x).

**Three results, and the third overturns the premise.**

1. **Claude has to ask in 52% of sessions** (129/246), 716 questions total.
2. **The first question arrives at assistant turn 24 (median); only 3% of asking
   sessions ask within the first three turns.** So Claude is almost never asking
   because the prompt was thin. It asks after ~24 turns of reading code and
   hitting a fork that *did not exist* at prompt time. These are discoveries, not
   omissions.
3. **Opening-prompt length does not predict corrections.** Split 123 real
   multi-prompt sessions into thirds by opening length:

   | opening length | n | median | corrections/session |
   | --- | ---: | ---: | ---: |
   | shortest third | 41 | 102 ch | 0.29 |
   | middle third | 41 | 410 ch | 0.41 |
   | longest third | 41 | 2133 ch | 0.22 |

   A 20x longer opening buys a 0.07 reduction, and the middle third is the worst.
   **Writing more upfront does not measurably help.** Any advice of the form
   "fill in more of the template before you start" is unsupported by the corpus.

### What genuinely does arrive late

62% of multi-prompt sessions get a constraint after prompt 1; 56% of opening
prompts carry no constraint at all. Of 152 late-constraint messages:

| what the late constraint is about | n |
| --- | ---: |
| scope limit ("only this", "don't touch X") | 30 |
| behaviour rule ("should always/never …") | 18 |
| device / where to test | 17 |
| visual-UX rule | 17 |
| process/git | 10 |

Only the middle-of-the-road categories are knowable at prompt time. **"Device /
where to test" is the one that is knowable, constant, and still repeated** — for
`todo`, `diet_guard_app`, `workout_app` and `wake_alarm` the answer is always the
phone, and it was still typed out 17 times, plus 5 feedback memories, plus 3 of
the 7 old `never` sections.

### The uncomfortable conclusion

That constant already has a standing rule, a memory (`prefer-mobile-testing`) and
a whole skill (`phone-deploy`) telling the agent mobile is primary — and it was
still violated 17 times. **A constraint that is already written down three times
and still missed is not a prompting defect.** No extra field, longer note, or
stricter capture discipline can fix it, which is why this audit adds `verify` as
the *only* new section and stops there.

The leverage is therefore not at capture time:
- **Capture stays cheap.** The evidence supports fewer fields, not more. Median
  opening prompt is 363 chars and that is fine. Implemented: a draft that is
  nothing but a pasted link now selects the freeform `blank` template
  automatically (`NoteTemplate.forDraft`), so filing a link costs one paste
  instead of a seven-step stepper — a third of the freeform backlog is exactly
  that. Typing any prose alongside the link restores the spec template, and an
  explicit pick from the dropdown or wizard is never overridden.
- **Per-repo constants belong in that repo's `CLAUDE.md`, written once** — never
  re-typed per note. `verify` exists for the exception, not the rule.
- **The real cost centre is the turn-24 fork**, which no prompt could have
  pre-empted. Improving that means better mid-session surfacing of decisions, not
  a better opening prompt.

## Re-running this audit

The measurements are all reproducible from `~/.claude/projects/**/*.jsonl` plus a
fresh `BACKLOG.md` export. The two that matter for judging a section's worth:

- **is it read?** — join a note to the sessions that consumed it (match on the
  note's title), then test the section against the transcript: were the `refs`
  URLs actually fetched, was `done` quoted back at verification time, does
  `estimate` appear anywhere downstream.
- **does it change behaviour?** — compare sessions where the section was filled
  against sessions where it was blank. This is what condemned `ask`: a 100% ask
  rate with it versus 92% without is not an effect.

Fill rate alone proves nothing — four of the removed sections said "Leave blank
if none" in their own helper text, so a low fill rate was them working correctly.
Do not re-add a section on a coverage argument; re-add it when a failure names
it.

