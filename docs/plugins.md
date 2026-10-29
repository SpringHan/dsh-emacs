# dsh plugin bridge

The bridge exposes two plugin surfaces to Emacs:

- `M-x dsh-emacs-plugins` — a plugin's generated **Typert Remote API**
  (`/v1/plugins`, `/v1/invoke`).
- `M-x dsh-emacs-plugin-routes` — a plugin's **HTTP routes** registered directly
  on the dsh web server (`/v1/routes`, `/v1/http`), for plugins that do not
  produce a Typert API.

Both work from any buffer, not only a chat: the bridge has its own loopback HTTP
API and does not use the dsh RPC transport.

## Requirements

1. Run `dsh web` with the `dsh-plugins-bridge` plugin installed and enabled.
2. In dsh **Settings → Plugins Bridge**, select the packages to expose in the
   plugin list and/or the route groups to expose under **Plugin HTTP routes**.
   The two allowlists are independent; an empty selection means that surface is
   empty.
3. Copy the bearer token from the same settings page.

The bridge is loopback-only. dsh-emacs reaches it at the same origin as
`dsh-emacs-base-url`, under `/plugins-bridge/v1`.

## Configuration

```emacs-lisp
(setq dsh-emacs-plugin-bridge-token "the token from Settings → Plugins Bridge")
;; Optional: a different loopback address or proxy for the bridge.
;; nil (the default) derives <dsh-emacs-base-url>/plugins-bridge/v1.
(setq dsh-emacs-plugin-bridge-base-url nil)
;; Catalog/detail/route-list and synchronous route-call timeout, in seconds.
(setq dsh-emacs-plugin-bridge-timeout 10)
;; Maximum characters of an HTTP route response shown in its buffer.
(setq dsh-emacs-plugin-route-max-output 50000)
;; Forward the current same-origin DSH session Cookie on route calls.
(setq dsh-emacs-plugin-route-forward-dsh-auth t)
```

The token may also come from the `DSH_BRIDGE_TOKEN` environment variable. It is
separate from `dsh-emacs-server-auth-token` (the dsh launch token) and is sent
only to the bridge's `/v1` routes. The token is never placed in a URL.

## Invoking a plugin API

Run `M-x dsh-emacs-plugins`:

1. Pick an exposed package. The completion row shows its title and endpoint
   count.
2. Pick an endpoint. Its description and `[stream]` marker, when present, are
   shown; streaming endpoints are not callable through the bridge.
3. Answer the argument prompts:
   - **Required arguments** are read one by one. String, number, boolean, enum,
     object and array schemas get matching readers; an `agentId` argument
     offers live session ids, defaulting to the current chat's session.
   - **Optional arguments** are one JSON object. Press `RET` to skip them; the
     prompt lists the accepted keys.
4. The call runs asynchronously. Its result opens in a read-only
   `*dsh-plugin: PACKAGE#ENDPOINT*` buffer; `q` closes it.

With a prefix argument (`C-u M-x dsh-emacs-plugins`), all arguments are read as
one JSON object instead. Use this for nested arguments or when a descriptor's
optional keys are easier to type directly:

```json
{"agentId": "session-…", "query": "src/"}
```

The bridge's own error object (`code`, `message`, `field`) is shown in the
result buffer, including on HTTP 4xx/5xx responses.

## Calling a plugin HTTP route

Run `M-x dsh-emacs-plugin-routes`:

1. Pick a route group from `/v1/routes`. The row shows its route count and
   `[not exposed]` when the group is not selected; choosing such a group stops
   with a Settings hint.
2. Pick a target path. Exact groups offer their registered paths; prefix groups
   accept a path below the group's prefix. A relative path is prefixed with
   `/<group-id>` automatically.
3. Pick an HTTP method. For `POST`, `PUT`, `PATCH` and `DELETE`, Emacs also asks
   for an optional request body; a nonempty body asks for `Content-Type`
   (default `application/json`).
4. The request runs asynchronously through `/v1/http/<target-path>`. The result
   opens in a read-only `*dsh-plugin-route: METHOD PATH*` buffer; `q` closes it.

JSON responses are pretty-printed, text responses are inserted as-is, and
binary bodies (images, audio, PDF, octet-stream, or a body containing NUL
bytes) are summarized with their byte count. Long text is capped by
`dsh-emacs-plugin-route-max-output`.

For example, choose the `dsh-session-manager` group, path
`/dsh-session-manager/trash`, method `POST`, body `{}` and Content-Type
`application/json` to list trashed sessions.

### Programmatic calls and generated code

`dsh-emacs-plugin-routes` accepts optional `GROUP`, `METHOD`, `PATH` and
`BODY` arguments. When `GROUP` and `METHOD` are both non-nil, neither is read
through completion and `PATH` replaces the target-path prompt. The request
then runs synchronously and its decoded JSON body is returned; no result
buffer opens:

```elisp
(dsh-emacs-plugin-routes "dsh-whale" "GET" "/dsh-whale/size.json")
```

A non-nil `BODY` replaces the body prompt and is sent with Content-Type
`application/json`:

```elisp
(dsh-emacs-plugin-routes "dsh-session-manager" "POST"
                         "/dsh-session-manager/trash" "{}")
```

Without `BODY`, a body-bearing method still reads its optional body and
Content-Type. A synchronous call is bounded by
`dsh-emacs-plugin-bridge-timeout` and signals a `user-error` for a transport
failure, a non-2xx status or a non-JSON body; `204`/`205` responses return
nil, as does a JSON `null`. Passing only one of `GROUP` and `METHOD` skips
that one prompt and keeps the usual asynchronous result buffer.

`M-x dsh-emacs-plugin-insert-route-call` walks the same group, path, method
and body prompts and inserts the matching call at point:

```elisp
(dsh-emacs-plugin-routes "dsh-session-manager" "POST"
                         "/dsh-session-manager/trash" "{}")
```

The generated call uses `application/json` for a nonempty body. If no body
is entered, the call omits the argument and asks for the body when it runs;
edit the inserted form or bind it to a key. A programmatic `BODY` always uses
`application/json`; use the interactive path for other content types.

The target route's own loopback, method, body and browser-session checks still
run. When the bridge base URL and `dsh-emacs-base-url` share an origin,
dsh-emacs also forwards the current signed DSH session Cookie
(`dsh-emacs-plugin-route-forward-dsh-auth`, default t). That is what lets a
route such as `/dsh-whale/size.json`, whose handler calls
`connection.requestRejection`, accept the request: the target sees the same
session Emacs already uses, and its auth is not bypassed.

If the route still returns 401, either Emacs has no valid DSH session (set
`dsh-emacs-server-auth-token`, or open the launch URL once) or the bridge is
configured on a different origin, in which case only the bridge token is sent.
Routes that only require loopback (the common case for management plugins)
work with the bridge token alone.

## Scope and limitations

- The agent-tool surface (`/v1/tools`) is not exposed. Use the dsh chat or the
  Web UI for model-facing tools.
- A package or route group must be selected in Settings; the bridge checks the
  allowlist on every call.
- Streaming Remote methods are listed by the bridge but return
  `501 stream-unsupported`.
- The HTTP route proxy is not a streaming client: an SSE or long-lived route
  holds the request until it completes or the connection closes. Binary bodies
  are summarized rather than displayed or saved.
- Route method metadata is not published by the bridge, so Emacs asks for the
  method instead of inferring it.
- A programmatic `BODY` always sends `application/json`; use the interactive
  route flow for text or form bodies.
- The plugin API catalog/detail and route list reads are synchronous (bounded
  by `dsh-emacs-plugin-bridge-timeout`); asynchronous calls have no client
  timeout, while a synchronous route call uses that same bound.
- The plugin result buffer displays pretty-printed JSON. An empty JSON object
  and `null` both decode to `nil` in the shared reader, so an empty object can
  display as `null`.
- Remote invocations run with the bridge's `owner` authority; HTTP routes keep
  the target route's own checks. Either can be destructive, just as in the dsh
  Web UI.
