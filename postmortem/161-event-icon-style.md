# 161 — Event icon style and dot fallbacks

## Background

Transcript event rows drew dsh-web's SVG icons on displays where Emacs could
create SVG images, and fell back to per-variant emoji or character glyphs
everywhere else (`dsh-emacs--variant-icons` plus the Think, todo, goal and
turn-trigger glyphs in `dsh-emacs-render.el`). Composer goal and queue actions
had their own emoji fallbacks in `dsh-emacs-composer.el`. Emoji rendering
varies by terminal, font and width, so the same transcript could change shape,
baseline and column alignment between GUI Emacs, a text terminal and a frame
without SVG support. There was no way to ask for one uniform leading mark.

Commits: pending (no commit requested for this change).

## Decision

Add `dsh-emacs-render-style` (default `full`, choices `full` / `simple`,
group `dsh-emacs-render`). `full` keeps dsh-web's SVG icons; when Emacs cannot
draw SVG, ordinary tool rows draw one dot in the tool accent while goal tools
and the Think, todo and turn-trigger rows keep their text glyphs. `simple`
leads every transcript event row with one dot whose face carries the meaning
and renders titles/summaries with the muted `dsh-emacs-event-row-face` (labels
add bold), including the Think title, so color is reserved for the row's
leading dot: tool dots follow state
(purple `dsh-emacs-tool-icon-face`, green `dsh-emacs-tool-success-face`, red
`dsh-emacs-tool-error-face`, stopped `dsh-emacs-tool-stopped-face`), and the
Think, todo, goal and turn-trigger dots use `dsh-emacs-thinking-face`,
`dsh-emacs-tool-icon-face`, `dsh-emacs-composer-goal-face` and
`dsh-emacs-meta-face`; the Think label text is deliberately not amber in
`simple`, and its live dot settles to muted grey once the fragment completes
while the streaming dot keeps the thinking accent.

Emoji fallbacks are removed from the event icons. Composer pause and
delete/clear fallbacks become `||` and `✕`; edit and resume keep `✎` and
`▶`. The composer's image helpers now also require a graphical frame, so a
text terminal takes those text fallbacks. Execution-status dots were already
dots and are unchanged; `simple` renders the interrupted tool leading mark as
the stopped-face dot instead of `◐`. Rendering owns the choice in
`dsh-emacs-render.el`, and the option affects newly rendered rows only.

## Why

One fallback glyph cannot match the width, baseline or font of an SVG icon, and
emoji are especially inconsistent across terminals and Emacs builds. A dot is
available everywhere, occupies a predictable width, and still carries state
through its face. Keeping emoji as the non-SVG fallback would preserve the
alignment and font problems and make terminal transcripts diverge from the web
UI; for tool rows, one plain dot glyph was chosen over another symbol font
for the same reason.

`full` stays the default because SVG-capable GUI Emacs is the primary target
and per-tool icons carry useful identity. `simple` is an explicit opt-in for
compact or uniform transcripts. It also mutes row chrome, because a
state-tinted title would repeat what the colored dot already says; the dot is
the only status color, and expanded card bodies keep their own content colors.
The muted tier reuses the reply-metadata palette instead of introducing a
second grey palette, so light and dark themes stay consistent. Making `simple`
the default was rejected because it would remove that identity
for every existing GUI user, and a per-row or per-event switch was rejected as
too fine-grained for a visual preference.

## Consequence

Users get a new option in `M-x customize-group RET dsh-emacs-render`, and
`simple` produces a uniform dot column with state-colored tool dots and muted
row text in `dsh-emacs-event-row-face`. `full` on
a text terminal or SVG-less frame loses per-tool identity: ordinary tool rows
become dots, while goal tools and the other event rows keep their text
glyphs. The behavior is documented in `README.md`,
`docs/customization.md` (Render style), `docs/ui-styling.md`,
`docs/slash-commands.md` and `docs/architecture.md`; `CHANGELOG.md` links here.
Emoji typed by users in chat or Markdown still render.

## Known limitations

- Existing transcript text is not restyled in place; reopen the session or wait
  for newly rendered rows to see the new style.
- `full` on non-SVG displays loses per-tool identity: ordinary tool rows
  become dots. Goal tools and the Think, todo and turn-trigger rows keep their
  text glyphs, so those rows differ from `simple`.
- Emoji in user-authored content and text status marks are untouched.
- `simple` mutes row labels and header chrome, not expanded card bodies; error
  footers, job status tokens, todo checkboxes and diff lines keep their content
  colors.
