# 154 — Plugin bridge client

_Status: Superseded in part by 155 (HTTP route proxy)._

## Background

`dsh-plugins-bridge` is a dsh Web plugin that projects selected plugins'
unary Remote APIs onto a loopback HTTP API. Before this change dsh-emacs could
only operate plugins by opening the Web UI or by hand-crafting requests; the
bridge had no Emacs client. The client could not reuse the dsh RPC transport:
the bridge answers its own `{ok, result, error}` envelopes under
`/plugins-bridge/v1` with a separate bearer token, and it reports failures in
JSON bodies on HTTP 4xx/5xx. Existing `dsh-emacs--http-post` discarded those
bodies and was tied to DSH authentication.

## Decision

Add `dsh-emacs-plugin.el` and one command, `M-x dsh-emacs-plugins`. It reads
`GET /v1/plugins`, then `GET /v1/plugin?package=…`, prompts for one endpoint's
arguments, posts `POST /v1/invoke`, and displays the result in a read-only
buffer. Catalog and detail reads are bounded synchronous GETs because the
command needs them before it can prompt. Invocation is asynchronous because a
Remote call may run for the bridge's two-minute limit.

Add two generic transport primitives to `dsh-emacs-server.el`:
`dsh-emacs--http-json` (asynchronous) and `dsh-emacs--http-json-sync`. They
accept method, URL, headers and an encoded body and return a plist with
`:status`, `:value`, `:error` and `:parse-error`. HTTP error bodies remain
decoded. `dsh-emacs--http-post` now applies DSH authentication, status policy
and stale-cookie recovery on top of the asynchronous primitive; the bridge
client supplies its own bearer token on the same primitive. The bridge JSON
views live in `dsh-emacs-protocol.el` as `dsh-protocol-bridge-*` structs.

Required arguments are prompted by JSON Schema type; a live `agentId` is
completed from `/v1/agents`. Optional arguments are one JSON object, and a
prefix argument replaces all argument prompts with one JSON object. The base
URL derives from `dsh-emacs-base-url`, the token comes from
`dsh-emacs-plugin-bridge-token` or `DSH_BRIDGE_TOKEN`, and the result opens in
`*dsh-plugin: PACKAGE#ENDPOINT*`.

## Why

The bridge is an HTTP API, not a dsh RPC namespace: forcing it through
`dsh-emacs--rpc-async` would require inventing an envelope and would hide the
bridge's error object. A generic HTTP/JSON primitive keeps framing, UTF-8 and
JSON decoding in the transport owner while letting each API own its
authentication and status policy. Keeping the error body is necessary for
actionable `package-not-exposed`, `unknown-endpoint` and `bridge-disabled`
messages.

Synchronous catalog reads keep the command linear: the next minibuffer prompt
does not exist until the previous response arrives, and the payloads are
small. Making invocation asynchronous avoids blocking Emacs for up to two
minutes. Prompting declared arguments by type is usable without requiring JSON
for every call; the all-JSON prefix path keeps nested and unusual arguments
expressible. Agent ids are read from the bridge rather than guessed from the
chat, so the command works outside a chat and does not submit a session-scoped
call with a stale id.

Only the plugin API surface is covered. The bridge's HTTP route proxy and
agent-tool surface have different response shapes, authorization and streaming
semantics; folding them into this command would make its argument and result
contract ambiguous. They remain candidates for separate clients.

## Consequence

Users configure the bridge once and can discover and invoke exposed plugin
APIs from Emacs. The bridge's plugin selection remains the authorization
boundary; a destructive Remote method still runs with the bridge's `owner`
authority. `dsh-emacs--http-post` behavior and callers are unchanged. Tests
cover the bridge structs, argument readers, request shape, result rendering,
command wiring, and both HTTP primitives.

Docs: [Plugin bridge](../docs/plugins.md), the module map and transport notes
in [architecture](../docs/architecture.md), and the `0.8.0` CHANGELOG entry.

## Known limitations

Catalog and detail reads block briefly (bounded by
`dsh-emacs-plugin-bridge-timeout`). Streaming endpoints are listed but the
bridge returns `501`; the result buffer is not a live log. The shared JSON
reader maps an empty object and `null` to nil, so an empty object can display
as `null`. Optional arguments are entered as raw JSON rather than individual
prompts. Route proxying and agent tools are not exposed. The bridge must be
installed, enabled and configured to expose the package; dsh-emacs does not
manage those settings.
