# 156 — A create with an unusable preset falls back to the host default

## Background

`session/create` rejects an unknown or non-composable `agentPreset` with
`agent-preset/not-found` / `agent-preset/invalid`; the error names the rejected
id and, for `not-found`, the ids the server still provides. The Emacs client
carries one preset on every create: `dsh-emacs-default-preset`, an interactive
picker choice, or the argument given by a caller. A draft is only a buffer
(there is no persisted draft-restoration path), so a stale configured preset or
a roster entry that disappeared between the picker and the RPC left the user
with a draft that could not be created; the only recovery was to kill it and
start over, possibly after discovering the bad setting.

The dsh web has the same wire errors. Its `restoreBlank` reloads a saved blank
Session's projections and, when that recorded preset no longer activates,
retries `createNamed` once without `agentPreset`. Its interactive
`startSession` does not retry.

## Decision

In `dsh-emacs-retry-session-creation`, a failed `session/create` response whose
code is `agent-preset/not-found` or `agent-preset/invalid`, and whose request
carried a preset, is followed by exactly one retry with `agentPreset` removed.
The fallback announces itself (`Preset X unavailable; using the host default`),
rewrites the draft's `dsh-emacs--creation-context` to the preset-less form, and
keeps the draft text. A manual retry (`C-c C-c`) therefore uses the host
default rather than replaying the unusable id; a second failure reports the new
error normally. Other failures never retry.

## Why

The server is the source of truth for preset availability; once it refuses the
id there is no draft UI for choosing another preset (the picker runs before the
draft exists), so failing the create leaves no action except killing the
buffer. Matching the web's `restoreBlank` recovery keeps a stale
`dsh-emacs-default-preset` from blocking every new session.

The fallback is applied to all creates, not only configuration-derived ones,
because Emacs has no saved-draft restore path and cannot distinguish a restored
preset from a just-picked one after the RPC has been sent. The message makes the
substitution visible, and the retry is limited to the two codes that mean the
preset itself is unusable.

Alternatives rejected: prompting for another preset inside the RPC callback
(the async callback is a process filter and has no roster/UI context), leaving
the draft failed (the reported case this change fixes), and retrying
indefinitely (a default that is also broken would loop).

## Consequence

A draft created with a removed/renamed preset (including a stale
`dsh-emacs-default-preset`, or a picker entry the server dropped) completes
under the host default after one extra round trip. The session's actual
`agentPreset` comes from the create response and is cached normally. Docs:
`docs/rpc.md` §session/create; CHANGELOG 0.8.0. This record describes the
uncommitted change after `b051c27`.

## Known limitations

If the host default is also unavailable, the retry fails and the draft reports
the second error; the user still cannot choose another preset without closing
the draft. Interactive create now recovers where the web's `startSession`
would surface the error; this is deliberate (there is no Emacs saved-draft
path to scope the recovery to) but a visible client divergence.
