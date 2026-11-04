# 158 - Hide Recents while filtering a workspace

## Background

At `0e51b13`, the session-list UI narrows Recents to the selected workspace
alongside its canonical group. The original policy is recorded in
[154](154-session-recents.md). The requested workflow is a focused workspace
view without the duplicate shortcut section.

Commits: pending for this change.

## Decision

Hide Recents whenever `w` selects a workspace. Clearing the filter restores
the normal global Recents group, with its existing size and visibility rules.

## Why

A filtered view should show only the selected workspace, once. An initial
uncommitted interpretation kept Recents global under filtering; that approach
was rejected because unrelated shortcuts distract from the focused view.
Filtering Recents to the workspace also duplicates the same session rows.
No additional option or cache is needed.

## Consequence

Workspace filtering suppresses both Recents and Ungrouped. Clearing it makes
Recents available again. Tests cover group membership, rendered absence and
restoration. The [changelog](../CHANGELOG.md#080---unreleased) and customization
guide describe the behavior; the README needs no extra feature paragraph.

## Known limitations

Explicit navigation retains its existing filter-clearing behavior. Clearing
a filter restores Recents subject to its configured limit, visibility rules
and existing fold state; this change does not reset folding preferences.
