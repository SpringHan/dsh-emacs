# 183 — HTTP route proxy

## Background

[dsh-plugins-bridge](182-plugin-bridge-client.md) also exposes plugins that
register custom HTTP routes on `dsh-host-webserver` instead of shipping a
generated Typert API. Record 182 deliberately left that surface out, so
`M-x dsh-emacs-plugins` could not operate routes such as
`dsh-session-manager/trash` or `dsh-whale/*`. The bridge's `/v1/routes`
reports the groups, their paths and whether each is selected; `/v1/http`
forwards one request to the target handler with the method, headers and body
unchanged. Responses are arbitrary: JSON, text, HTML, images or other bytes.

The JSON-only `dsh-emacs--http-json` could not serve this: it discards the raw
body and parses every response as JSON. The bridge also performs its own
allowlist check and the target route keeps its own loopback/session/method
checks, so the client must surface HTTP failures and target bodies instead of
assuming the bridge's `{ok, error}` envelope.

## Decision

Add `M-x dsh-emacs-plugin-routes` to `dsh-emacs-plugin.el`. It reads
`/v1/routes`, requires the chosen group to be selected, normalizes the target
path under `/<group-id>`, asks for a method, and for `POST`/`PUT`/`PATCH`/
`DELETE` asks for an optional raw body plus a Content-Type (default
`application/json`). The request goes through
`/plugins-bridge/v1/http/<target-path>` and opens a read-only
`*dsh-plugin-route: METHOD PATH*` buffer.

Split the transport primitive in `dsh-emacs-server.el`:
`dsh-emacs--http-request` now dispatches raw `:status`, `:headers`, `:body`
and `:error`; `dsh-emacs--http-json` wraps it with UTF-8 JSON decoding and
`:value`/`:parse-error`. `dsh-emacs--http-post` and the plugin API client keep
using the JSON wrapper. The route client uses the raw form and renders JSON
pretty, text as-is, and binary types as a byte-count summary. New option
`dsh-emacs-plugin-route-max-output` bounds displayed text.

Route requests also forward the current signed DSH session Cookie when the
bridge base URL and `dsh-emacs-base-url` share an origin; the new option
`dsh-emacs-plugin-route-forward-dsh-auth` (default t) controls it. The target
route's `connection.requestRejection` therefore sees the same session Emacs
already uses. A bridge on another origin receives only the bridge token.

Add `dsh-protocol-bridge-route-list` and
`dsh-protocol-bridge-route-group` for `/v1/routes`; wire names stay in the
protocol constructor. A non-object response declines to an empty view.

## Why

The route proxy and the plugin API share a token, base URL and loopback
transport, so they belong in the same bridge module; but they do not share a
response contract. Keeping JSON parsing in a wrapper makes the raw/JSON split
explicit and avoids buffering every RPC response twice.

The selected-group check uses the bridge's own `/v1/routes` fact, so an
unselected group fails with a Settings instruction instead of an opaque 403.
Path normalization accepts both full target paths (the listed candidates) and
short paths below a prefix group, which is how `/v1/http` actually addresses
targets: the request URL is `/http` plus the absolute target path.

Method is prompted because the bridge publishes groups, paths and counts, not
methods. The Content-Type prompt keeps JSON as the common default while
allowing text or form bodies. Binary response display is deliberately a
summary: decoding arbitrary bytes as text or trying to save them to an
unspecified file would be misleading.

The bridge token is not a target-route credential. Route handlers such as
`dsh-whale` call `connection.requestRejection`, whose `admit` requires a
signed `dsh-auth-*` browser Cookie; a Bearer bridge token is ignored there.
Sending the same-origin DSH Cookie is the minimal fix that preserves the
target's authorization instead of bypassing it in the bridge. The origin
guard avoids leaking the Cookie to a bridge proxy or another host. When Emacs
has no session, the request still returns 401 and the user must authenticate
the Emacs client.

## Consequence

Users can operate route-only plugins from Emacs without the Web UI. Target
routes still enforce their own authorization. The plugin API flow, RPC
transport and `dsh-emacs--http-post` behavior are unchanged; the RPC and HTTP
unit suites cover the refactor. Tests cover route structs, path normalization,
group selection, request shape, JSON/text/binary/error rendering, truncation,
same-origin Cookie forwarding and command wiring.

Docs: [Plugin bridge](../docs/plugins.md), the module/transport notes in
[architecture](../docs/architecture.md), and the `0.9.0` CHANGELOG entry.
The route-scope limitation in [182](182-plugin-bridge-client.md) is
superseded; the rest of that record still applies.

## Known limitations

No SSE or other streaming route support: the request completes (or the
connection closes) as one response, with no client-side timeout. Binary bodies
are summarized, not displayed or saved. The method is user-selected rather
than inferred, and the body is raw text (no multipart or file upload UI).
Session forwarding requires both a same-origin bridge and a valid Emacs DSH
session; a different origin or a missing session still yields 401. The
agent-tool surface remains unexposed.
