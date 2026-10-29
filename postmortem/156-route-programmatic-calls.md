# 156 — Programmatic route calls and generated code

## Background

`M-x dsh-emacs-plugin-routes` (record [155](155-http-route-proxy.md)) always
prompted for the route group, target path and method, then delivered the raw
response into a read-only buffer asynchronously. That is right for exploring a
route, but useless when a user writes their own command around one route:
there was no way to skip the prompts, and the result was only displayable, not
returned.

Writing such a command also required looking up the route group id and target
path by hand. The discovery data already lived in `/v1/routes`, so the command
should be able to turn the same selection into the Lisp call that repeats it.

## Decision

`dsh-emacs-plugin-routes` gains optional `GROUP`, `METHOD`, `PATH` and `BODY`
arguments. `dsh-emacs-plugin--select-route` owns the shared selection:
a supplied group id is resolved against `/v1/routes` instead of read through
completion, a supplied method is upper-cased instead of prompted, and a
supplied path is normalized under the group instead of read. The group must
still be exposed under **Plugin HTTP routes**.

When both `GROUP` and `METHOD` are supplied, the command treats the call as
programmatic: it uses `dsh-emacs--http-json-sync`, returns the decoded JSON
body and opens no buffer. Transport failures, non-2xx statuses and non-JSON
bodies signal `user-error`. A supplied `BODY` replaces the body prompt and is
sent as `application/json`, so a POST call with data is fully non-interactive.
Without `BODY`, a body-bearing method still reads its optional body and
Content-Type; that keeps the interactive path able to send text or form
bodies. Supplying only one of `GROUP`/`METHOD` skips that one prompt and keeps
the asynchronous buffer.

`M-x dsh-emacs-plugin-insert-route-call` runs the same selection, reads a
nonempty body for a body-bearing method and inserts
`(dsh-emacs-plugin-routes "GROUP" "METHOD" "PATH" "BODY")` at point. The
inserted call therefore performs the same synchronous JSON request, and the
user can edit it or bind it to a key.

The synchronous path reuses the existing bounded JSON transport
(`dsh-emacs-plugin-bridge-timeout`) rather than adding a second raw HTTP
primitive: the programmatic contract is JSON, while the interactive command
keeps `dsh-emacs--http-request` for arbitrary response bodies.

## Why

`GROUP`, `METHOD`, `PATH` and `BODY` are the minimum needed for generated code
to repeat a selected request without another prompt; `PATH` and `BODY` stay
optional because a caller may still want to choose them interactively.
`GROUP` and `METHOD` together are the signal for "return data, do not display
it", matching the requested API.

A body argument without a Content-Type argument would otherwise prompt on every
programmatic POST, so a supplied body fixes the content type to
`application/json` — the prompt's default and the common bridge route format.
The interactive path keeps the prompt for text, form and other bodies. Adding a
fifth Content-Type argument would make the programmatic call fully expressive;
it is deliberately left out until a caller needs it.

A distinct sync path is preferable to making the command always synchronous:
route handlers may be slow, and the existing buffer keeps streaming-style
exploration in the UI. Errors signal instead of returning a response envelope
so a Lisp caller can use `condition-case` and cannot mistake an HTTP failure
for a successful JSON value. JSON `null` returns nil, which the caller can
distinguish from an error by the absence of a signal.

## Consequence

Users can call one route from Lisp, receive its decoded JSON, and generate the
call from the same completion UI. Interactive behavior is unchanged when no
arguments are passed. The command's result contract now depends on whether
`GROUP` and `METHOD` were supplied; docs and the CHANGELOG state that split.

Tests cover prompt-free programmatic calls, method normalization and path
normalization, supplied and interactive bodies, Content-Type selection,
synchronous failures, unknown groups and inserted-code text.

## Known limitations

The programmatic form returns JSON only; a route that returns text or binary
still needs the interactive buffer. A programmatic `BODY` always uses
`application/json`; other content types require the interactive route flow. A
body-bearing method without a supplied `BODY` still prompts, so only calls
that pass `BODY` are fully non-interactive. The generated call omits an empty
body, so it asks for the body when it runs. The sync request is bounded by
`dsh-emacs-plugin-bridge-timeout`, so a slow route can time out even though
the asynchronous path has no client-side timeout.
