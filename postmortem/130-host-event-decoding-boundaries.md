# 130 — Decode host events at their application boundaries

Activity timestamp policy superseded by [154](154-session-recents.md).

## Background

At `3c4f069`, core event dispatch reads `$events` fields through the renderer,
including positional session-notice arguments and interaction requests.
[129](129-core-workspace-boundary.md) introduced a core item view but left these
frames raw. This records the ninth refactoring batch based on the
same commit, preserving the interaction ownership in
[124](124-shared-interaction-owner.md).

## Decision

Extend core decoding with scalar ready/cancel ids, a session-notice view and a
waterfall envelope. Decode an approval or question-request payload only after
routing it to a live chat. Keep added-session summaries raw until cache
application, and individual questions raw until the existing Plan/readers.

## Why

Named session-notice fields remove positional interpretation from events;
running flags now cross the protocol boundary as booleans. Activity only
bumps a cached row to the front, so its unused timestamp argument is removed.
Events retains cache mutation, refresh recording and notification order.

Eagerly decoding every nested payload would change two ownership boundaries.
A foreign waterfall must be handed on even if its request is malformed or
unknown. A live cached session is mutable, while a refresh record must retain
the original added-summary facts. Reusing one decoded session for both would
allow subsequent cache updates to alter a later replay. Keeping the raw summary
and decoding at each application preserves that separation without copying
mutable structs or adding a second snapshot model.

The small question-request view owns only the array and optional timed wait.
Question validation, Plan intent selection, localized approval selection and
timed claim lifetimes keep their current phases; see
[073](073-timed-question-answers.md) and [074](074-localized-approval-reasons.md).

## Consequence

The core consumer no longer reads wire fields through the renderer. Generation
retirement still precedes installing the new client id. Cancellation still
visits questions before approvals. Unknown local requests remain ignored;
foreign requests with an event id and client id still receive `next`.
No commands, defaults, reader behavior or repaint policy change.

Behavior tests cover refresh replay after cache mutation, activity ordering
without timestamp mutation, raw/typed routing and foreign malformed requests.
Protocol tests cover named arguments, booleans, envelope identity and deferred
question decoding; existing interaction tests protect decisions and cleanup.

## Known limitations

Durable event bodies remain a separate migration. Raw summaries and requests
here are deliberate phase boundaries, not permission for consumers to parse
their fields outside protocol. Individual question objects keep their existing
symbol-keyed contract. The Emacs 27.1 baseline is unchanged.
