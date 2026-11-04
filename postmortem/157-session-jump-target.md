# 157 - Configurable session-list jump target

## Background

The Recents shortcut introduced in [154](154-session-recents.md) gives a
session two row occurrences. Chat-to-list navigation prefers the shortcut,
which is useful for quickly returning to active work but hides the surrounding
project context for users who navigate by workspace. This is a session-list
UI choice, not a transport or session identity problem.

Commits: pending (no commit requested for this change).

## Decision

Add `dsh-emacs-session-jump-target`, owned by `dsh-emacs-session.el`, with
choices `recents` and `workspace`. The default `recents` preserves existing
navigation: select the Recents occurrence when present, otherwise the
canonical workspace or `Ungrouped` session row. `workspace` always selects
that canonical session row. Both `C-c C-l` and `M-x dsh-emacs` from a chat
use this preference; explicit project-root workspace navigation remains
unchanged, and refreshes preserve point rather than reapplying the option.

## Why

A preference separates two useful workflows without making either user
disable Recents or manually find a duplicate row. Changing the default would
surprise existing users; removing the duplicate would sacrifice complete
workspace navigation. Selecting a workspace header instead of the session
row would lose the invoking chat's identity. Applying the preference during
refresh would interrupt deliberate navigation as new activity arrives.

The canonical fallback is an explicit navigation contract, not compensation
for missing data: a bounded or disabled shortcut group cannot contain every
session. No additional visit-history state or navigation command is needed.

## Consequence

Users can keep Recents visible while returning from a chat to its project
context. README, customization documentation and the
[0.8.0 changelog](../CHANGELOG.md#080---unreleased) describe the option and
its default. Future navigation changes must keep explicit session jumps
separate from project-header jumps and point-preserving refreshes.

## Known limitations

The option chooses a row occurrence, not a sort order or visibility policy.
It does not pin a session in Recents or change its size limit. Existing
neighboring-row recovery still applies when a refresh removes the row at
point; preserving point cannot retain a row that no longer exists.
