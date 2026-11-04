# 154 — Recent sessions before workspace groups

Superseded by [158](158-filter-hides-recents.md) for workspace-filter behavior.

## Background

At `f4f2e40`, the session list sorts each workspace by latest update, but
finding active conversations across projects still requires navigating
several groups. This is a session-list UI concern: the host cache already
contains the timestamps and workspace membership needed for a shortcut view.

## Decision

Add a leading Recents group in `dsh-emacs-session.el`, showing the 15 most
recently updated visible root sessions. Keep their original workspace rows.
The `dsh-emacs-session-recents-limit` option changes the count; zero disables
the group. Apply the existing visibility and workspace-filter rules before
ranking. Recents starts expanded, with ordinary group folding thereafter.

## Why

Using the host's update time gives one consistent ordering across clients
without a new visit-history store or activity scoring policy. Keeping the
workspace rows preserves complete project navigation. A separate shortcut
group also remains useful when workspaces start collapsed.

The same conversation now has two row occurrences. Recents scopes each
subtree row identity, including child notices, while command properties keep
the real session, direct parent and workspace. This preserves the row-local
reconciliation and marker guarantees from [078](078-session-list-row-updates.md)
and the focus policy from [082](082-session-list-focus.md). Visual strings
can be reused within a render; command metadata is still applied afresh.

Activity must update the cached timestamp, not just the cache's list order:
sorting by the unchanged time discards the live event's promotion. The session
notice decoder therefore retains the activity timestamp, and events applies
it monotonically and records it for refresh replay. This supersedes the unused
timestamp policy in [130](130-host-event-decoding-boundaries.md) and prevents a
late list snapshot or older event from undoing recent activity.

## Consequence

Opening the list from a chat prefers its Recents occurrence when present.
Refreshes retain the chosen occurrence in each window; losing a shortcut
uses the existing neighboring-row policy. Subagent expansion remains session
state shared by both occurrences. Transport subscriptions stay unchanged;
the existing activity event now carries its timestamp through decoding.
Tests cover ranking, filtering, folding, command context, duplicate child
rows, markers, rank eviction and live activity during nested or cold refreshes.
This record describes the uncommitted change
after `f4f2e40`; README, customization docs and CHANGELOG document the workflow.

## Known limitations

Latest update is a recency measure, not a count of visits or messages. The
limit counts root sessions; expanding their children can show more rows.
Recents reflects the cached host list and updates through its existing refresh
path. Fold and child-expansion choices last for the list buffer's lifetime.
