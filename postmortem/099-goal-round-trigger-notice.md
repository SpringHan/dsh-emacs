# 099 — Goal round trigger notice in the transcript

_Status: partly superseded by [159](159-turn-trigger-notices.md) — the
transcript now replays inbox claims for non-goal wake notices; the goal
round keeps this unconditional notice._

## Background

A goal that stays active continues itself: `goal-round-driver` appends one
`user/message` per automatic round to the same conversation surface the human
uses, naming its origin `source = {kind: "goal", goalId, revision, round}` and
carrying the model-facing `<goal_round>` prompt (`packages/goal/goal-round-driver/
src/index.ts`, `prompt.ts`).  dsh web paints that message as a turn-trigger
notice (`packages/client/ui-chat/src/client/chat/TurnTriggerNodeView.tsx`):
goal glyph, `Continuing goal`, clock, and an expandable body.

dsh-emacs classified every non-`user` source as a hidden host injection
(`dsh-emacs-render--user-authored-p`) — correct for workspace instructions and
compaction checkpoints, whose goal was keeping system-reminder walls out of
`M-p` recall, but it also hid the round that actually opened the turn.  A
user watching a self-continuing goal saw a new reply with no attribution and
no way to read the prompt that drove it.

## Decision

Render a `user/message` whose `source.kind` is `goal` as a collapsed **minimal
fragment** notice instead of hiding it.  `dsh-emacs-render-user-message`
routes it to `dsh-emacs-render--goal-trigger-block` before the author filter;
the row reuses the Composer Goal Row's dsh-web dartboard
(`dsh-emacs-composer--goal-icon`, declared forward across the lazy
render → composer boundary), shows `Continuing goal` plus the event clock as
its right label, and folds the injected prompt into the body so the
`<goal_round>` instruction stays out of the way until RET or a click expands
it.  Every other host injection keeps the old hidden path, and the trigger is
still not recallable.

## Why

The web's turn-trigger card exists exactly because a non-human message that
opens a turn is worth attributing without becoming conversation.  Hiding it
made self-continuation indistinguishable from an unprompted reply; showing
the raw prompt inline would have dumped a model-facing instruction into the
transcript.  A folded fragment is the existing transcript idiom for that split
(user messages, tool cards and reply footers are all fragments), so the notice
needs no new rendering machinery.  Reusing the Goal Row icon keeps one goal
identity across the composer and the transcript instead of a second SVG copy;
the timestamp face (previously defined and unused) carries the web clock.

Rejected alternatives:
- **Render the goal round as an ordinary user block** — it would put words the
  user never wrote behind the `❯ ` prompt and make `M-p` recall offer the
  prompt back.
- **Move the goal SVG into `dsh-emacs-render.el` and have Composer call it** —
  a 45-line relocation whose only gain is reversing one declared call; it
  churns the Goal Row's tested icon width and reserved-column geometry for no
  behavior change.
- **Render every injected source as a context row (full web parity)** —
  broader than the reported gap, and it would surface instruction/runtime
  walls the transcript deliberately hides.

## Consequence

A self-continuing goal now has a visible, expandable attribution row in the
transcript, live and in replayed history.  Tests cover the collapsed default,
the expanded body and the unchanged hiding of other injections.  The author
filter's contract changed from "only `user` renders" to "only `user` renders
as conversation"; the docstring and `docs/architecture.md` event-rendering
flow record it.  `dsh-emacs-render.el` now declares
`dsh-emacs-composer--goal-icon` as a runtime-only forward reference — that
declaration must stay lazy, since Composer still loads after render.

## Known limitations

The notice shows every goal-sourced message, including round 0 and replays
that dsh web might classify as context rather than a waking trigger; the
transcript has no inbox-state projection to copy that waking test.  The web's
explanatory body line is omitted — the label and the round prompt are enough.
Round number and objective are not summarized in the collapsed row; expand to
read them.

This records uncommitted work based on `e4b1841`.  Web source reference:
`deepseek-harness` commit `5badb15009`,
`packages/client/ui-chat/src/client/chat/TurnTriggerNodeView.tsx` and
`turn-trigger.ts`.