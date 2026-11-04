# 160 — History rounds are user-authored rounds

## Background

`C-c C-o` paged by `turn/start` via `session/page`'s `turnWindow`: a round was
any turn, including a child message, a settled subagent, or a goal
continuation.  Those turns have no user prompt.  A three-round load could
therefore start at such a turn, topping the transcript with a trigger plus an
assistant answer whose user message was still one page away.  A reported
session showed exactly that: the loaded range began with **Task message
received** and only then reached the human "subagent 卡死了吗?" round.  The
reader's unit is user + assistant, not every host-driven turn.  The automatic
opening load had the same boundary: a snapshot starting at a waking turn did
not complete the user prompt that preceded it.

## Decision

Count **human rounds** instead of turns.  A human round is a turn containing a
user-authored `user/message` (`source.kind` is `user` or absent); child, goal
and other host wakes belong to the human round that preceded them.
`dsh-protocol-history-human-rounds` classifies the accumulated records;
[dsh-emacs-history.el](../dsh-emacs-history.el) keeps at most the requested
number of human rounds and starts the page at the oldest kept human round's
`turn/start`, deferring any leading non-human turns to the previous page.  The
`turnWindow` request still asks for the remaining human-round count, and the
loader repeats while the staged count is short because the server counts
turns.  The follow snapshot exposes `human-round-count`, so the opening
auto-load backs up one human round when the snapshot starts at a wake.

The protocol page decoder no longer classifies rounds; the loader supplies the
page's human rounds.  Scanning the accumulated records rather than each page
matters: a message-aligned page can split a turn's `turn/start` from its user
message.

## Why

The server's pagination is turn-based and cannot know the reader's unit.  The
client already owns transcript grouping, so classifying rounds there is exact
and keeps wire field names inside the protocol module.  Paging by human rounds
makes "load N rounds" mean N user+assistant exchanges and guarantees that the
top of a loaded range is a user message rather than an orphan answer.  The
same definition is needed for the opening auto-load, otherwise a session whose
latest turn was child-woken still opens on a trigger.

Rejected alternatives:

- **Count only `source.kind` at render time** — the page boundary would still
  start at a child turn; the reader would see an incomplete round until the
  next load.
- **Request extra turns and hope a human turn is included** — a run of child
  turns can still lead, so the range is not deterministic.
- **Treat any user-authored message as a round marker** — unchanged here for
  mid-turn steering: a human steer marks that turn as a human round, but its
  `turn/start` is still the host wake.  This is recorded as a limitation.

## Consequence

`C-c C-o` now loads complete user+assistant ranges.  A leading child or goal
turn is no longer the top of a loaded page; it is loaded with the human round
it belongs to.  `Loaded rounds X–Y (N rounds)` counts human rounds, and a page
with no human rounds reports `Beginning of history`.  Opening a fresh chat
with a snapshot that starts at a wake completes the preceding human round.
[dsh-emacs-history-rounds](../dsh-emacs-history.el) now names human rounds;
README, customization, architecture and the history tests use that definition.
The protocol adds `dsh-protocol-history-human-rounds` and the follow
snapshot's `human-round-count`; the wire page itself carries no round
classification.

## Known limitations

- A turn containing any user-authored message counts as a human round,
  including a human steer into a host-woken turn; the round's `turn/start` can
  then be the host wake.
- A page with no human rounds (for example only child turns at the session
  start) is published as an event page and reports `Beginning of history`;
  there is no human round to use as the boundary.
- `Loaded rounds X–Y` prints turn numbers, so host-woken turns inside the
  range are not counted in the round total and the numeric range can be wider
  than the count.
- The request's `turnWindow` still counts turns; a long run of host-woken
  turns may require extra round trips before enough human rounds are staged.

The reported session is recorded uncommitted on top of `15a6f01`.
