# 152 - Complete only the latest round on opening

_Round definition and the opening auto-load are refined by
[160](160-history-human-rounds.md): a round is a turn with a user-authored
message._

## Background

Commit `3812271` and [148](148-open-complete-rounds.md) reused the manual
complete-round target for opening. This removed the old total message budget:
30 messages bounded each response, not the automatically requested range.
The history controller stages all pages and publishes them in one synchronous
prepend. Long rounds therefore multiply network, memory and main-thread work.
This is an opening-policy problem in Events, not an RPC page-size violation.

## Decision

Opening targets one round, independently of `dsh-emacs-history-rounds`.
Follow requests one turn start within the existing message cap. If the initial
snapshot contains no start and older history remains, complete one round using
the existing cancelable loader. If a start is already present, fetch nothing
more. Manual `C-c C-o` keeps its configurable default of three rounds.

## Why

The user accepted completing one round as the performance/completeness
tradeoff. It retains the latest question and available work without silently
loading two additional rounds. Lowering the shared option would also change
manual browsing; raising the GC threshold would not reduce the requested work.
No new option, timer queue or transport path is necessary for this change.

## Consequence

Draft and reading positions, subagent addressing, live sequence anchors,
cancellation and reconnect behavior are unchanged. Regression tests distinguish
opening from manual targets and verify that an overfetched older round is not
published. README, customization docs and the changelog describe the separate
automatic and manual targets. This change is not yet committed.

## Known limitations

One round is not a hard byte, message or time budget. A long round can still
require many pages and an expensive synchronous prepend; history without turn
boundaries can still be read to exhaustion. Cancellation works between
responses, not during publication. Lazy rendering of folded tool details is
addressed by [153](153-lazy-tool-bodies.md); bounded, resumable publication
remains a separate potential improvement, not a claim made by this narrower
policy fix.
