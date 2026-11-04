# 159 — Turn-trigger notices for waking host messages

## Background

dsh web paints a non-human `user/message` that opens a Turn as a turn-trigger
notice (`TurnTriggerNodeView`, `turn-trigger.ts`): a source-family title, the
event clock and the recorded notice body behind a chevron.  The notice is a
turn *input*, not process content, so it stays visible above the turn's
**Completed in …** summary while the work folds away.  A turn whose only
visible content is that input therefore reads as attribution followed by a
disabled Completed row and the answer.

`dsh-emacs-render--user-authored-p` hides every host-injected copy, with one
exception: the goal round continuation rendered the **Continuing goal**
notice (postmortem/099).  A background child Agent that reported to its
parent was not covered.  Each `send_message` or settlement notice woke a new
parent turn; because the message itself was hidden, the transcript showed a
bare **Completed in 10s** row glued under the previous answer, with no sign
of what had started it.  A real recorded session (neomacs review, 2026-10-26)
had exactly four such rows, only the first with a disclosure.

## Decision

Replay `agent/inbox/spliced` in the renderer as display-only attribution
state and paint dsh web's trigger row for the messages the latest claim
admits.  `dsh-emacs-render--note-inbox-splice` materializes each target's
pending queue, records the latest claim's ids and whether it claimed human
input, and drops a requeued id from the claim.  A non-user, non-goal message
renders `dsh-emacs-render--turn-trigger-block` when:

- the next-turn claim contains its id, or
- it is the idle steer dsh web recognizes: step 1 of a turn that started
  after the next-step claim, with no next-turn claim in that turn and no
  human input in the same batch.

The row reuses the goal trigger's collapsed minimal fragment (icon, title,
event clock, folded body) through `dsh-emacs-render--trigger-block`.  It is
inserted where the message would have rendered; the work-details skip loop
treats `turn-trigger` like `goal-trigger`, so the row stays outside both the
outer turn fold and the activity groups.  Canceled and requeued claims, a
missing claim, a non-step-1 next-step admission, and messages without a
recorded location stay hidden.

A history page can begin at a `turn/start`, keeping the claim but losing the
inbox insertion that queued its message.  Such a claim is recorded as
truncated; a source in one of the known waking families (`agent-message`,
`team-message`, `subagent-settled`, `webhook`, `schedule`, `tool-jobs`,
`cordis-host-runner`) still gets the row from the turn's opening batch.  The
opening batch is the set of non-canceled claims
logged before the first `step/start`; every rendered `user/message` spends
one slot, so a hidden injection that precedes the wake in the same batch
does not steal attribution, while a later step's notice is outside the batch
and stays hidden.  A complete claim that does not name the message never
falls back, so the recovery cannot turn a mid-turn injection into
attribution.  History prepends scope a fresh attribution state and discard
it, so an older page cannot disturb the live tail; an opening snapshot is
anchor-gated, so it keeps the state already built and replays only new
records, while a full transcript reload clears it.

## Why

The alternative sources were guesses, not evidence.  Classifying by
`source.kind` or by "the first user message of a turn" would have shown
mid-turn child updates as if they had woken the turn, or missed the idle
case entirely — which is exactly what the recorded session used for two of
its three orphan rows.  The inbox claim is the host's own record of
admission, and dsh web's waking test is defined on it.  Reusing the goal
trigger's minimal row keeps one transcript idiom for "a host message opened
this turn": no card chrome, no new face, and the existing fold/keymap code
already gives RET, click and isearch behavior.

Rejected alternatives:

- **Infer a trigger from `source.kind`, `form: "notice"` or the summary
  text** — hides the difference between a waking input and a mid-turn
  context injection, and invents attribution the log did not record.
- **Render every wake as a separate turn boundary or merge child-driven
  turns into the preceding human turn** — contradicts dsh web, where each
  waking message opens its own Turn with its own Completed summary.
- **Show the full context-injection row for every hidden copy (web parity)**
  — still out of scope; workspace instructions, runtime snapshots and
  catalogs would surface as transcript walls.  dsh web hides ordinary
  context rows too and only reveals tool add/remove rows, which Emacs does
  not consume.

## Consequence

A child-driven turn now has a visible, expandable attribution row above its
Completed summary, live and in replayed history; the four-row transcript
from the report renders three trigger rows (**Task message received** twice,
**Subtask status updated** once).  This extends postmortem/099, whose goal
round keeps its unconditional notice.  The protocol module exposes `dsh-protocol-inbox-splice` and adds `id` and
`source-provider` to `dsh-protocol-message`; `dsh-emacs-render.el` owns the
buffer-local queue/claim/turn-batch state.  An older-page prepend scopes
that state, a full transcript reload clears it, and a reconnect keeps it:
the snapshot is anchor-gated, so already-processed claims are not replayed.
`docs/architecture.md`, `docs/subagents.md` and the changelog record the
behavior.

## Known limitations

- The Emacs row uses one paper-plane trigger glyph where dsh web tints a
  source-family icon, and its clock is the transcript's existing HH:MM:SS
  rather than web's HH:MM.  The title names the family.
- dsh web's explanatory body line ("This notification triggered this
  response.") is omitted, matching the goal trigger's earlier decision.
- A page that starts mid-turn without its `turn/start` (losing both the
  claim and the opener location) still hides the trigger; web has the same
  partial-window behavior.  Only a known waking source can use the opener
  fallback, so an unknown custom source stays hidden in that case.
- The trigger is painted when its message renders.  A chat buffer rendered
  before this change keeps the old rows until it is killed and reopened;
  refresh is anchor-gated and does not repaint history.
- `agent/inbox/spliced` replay is not a general inbox mirror; the pending
  queue exists only to materialize claim membership.  Queue UI still reads
  the `inbox` projection.
- Only the latest claim per target is retained, matching web's
  `currentClaimed`.  Older claims are not needed for classification but are
  not inspectable.

Web source reference: `deepseek-harness` commit `687f282e86`,
`packages/client/ui-chat/src/client/{conversation-nodes/message.ts,
conversation-nodes/inbox.ts,chat/TurnTriggerNodeView.tsx,chat/turn-trigger.ts,
chat/ChatNodeSeat.tsx}`.  This records uncommitted work based on `15a6f01`.
