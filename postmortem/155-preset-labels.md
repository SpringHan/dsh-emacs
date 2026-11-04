# 155 — Preset labels come from the roster, not a client map

## Background

Since `e0b6f62` the new-session picker has offered the four shipped agent
presets under English labels (`Standard mode`, `Minimal mode`, `PTC mode`,
`Creator mode`) from `dsh-emacs--preset-display-name-mapping`. The map was
needed twice: the cached roster names user presets but not shipped ones, and
before the first `agentPresets/list` response the map supplied the only
choices the picker had.

The mapping mirrored the dsh web's `presetDisplayText`, but the web resolves
those labels through its active locale dictionary, while the map hardcoded
one language. It also pre-empted a published `name` on a shipped preset id,
which the web would prefer; the unit fixture even encoded that divergence.

## Decision

Delete `dsh-emacs--preset-display-name-mapping` and
`dsh-emacs--preset-display-name`. `dsh-emacs--preset-choices` now builds each
`(DISPLAY . ID)` choice from the cached roster's published `name`, falling
back to the id, and appends the id when two rows would render identically.
`dsh-emacs--read-preset` refreshes a warm roster in the background and, for a
missing one, ensures the server is ready (`dsh-emacs-server-ensure`) before
fetching it synchronously with `dsh-emacs--rpc-request`, so the picker never
opens without choices; a failed fetch signals `user-error` carrying the
server's reason rather than creating with an unchosen preset. The protocol
struct's `name` slot and its wire decoding are unchanged.

## Why

The server is the source of truth for preset metadata, and it publishes a
`name` only when the declaration supplies one: `agent-preset-registry`'s
roster builder emits `...record.config.name === void 0 ? {} : { name }`, and
the shipped preset YAMLs declare `id` and `order` only. Any built-in label is
therefore client-side copy. Keeping one language in Emacs duplicated the
web's localization without implementing it, and the id is unambiguous.

Alternatives rejected: keeping the English map (the reported duplication this
change removes); translating through the web's locale payload (not exposed to
the client); showing only a hardcoded id list before the roster (still
client-side preset knowledge); skipping the prompt when the roster is cold
(the first version of this change — `C` silently created a session with the
host default instead of the chosen preset).

## Consequence

The picker now shows a user preset's `name` and a shipped preset's id
(`standard`, `minimal`, `ptc`, `cordis`); rows whose labels would collide add
the id in parentheses. `C` in the session list and `C-u M-x
dsh-emacs-new-session` always prompt: a cold roster is fetched first after a
server-readiness check (which can auto-start a stopped local server), and a
failed fetch aborts creation with an error instead of falling back to the
host default. `dsh-emacs-default-preset` is unchanged and still accepts ids.
Tests cover the name-or-id table, duplicate labels, server readiness, the
cold synchronous fetch before prompting, the fetch-failure path, and the
existing preselection and quit behavior. Docs: `docs/rpc.md` §0.5 item 2;
CHANGELOG 0.8.0. This record describes the uncommitted change after
`276e7bd`.

## Known limitations

A cold fetch blocks the interactive prompt for the readiness probe plus one
local HTTP round trip, and on a stopped local server the probe may first
start it; a slow or unreachable server therefore delays or aborts preset
choice instead of silently creating. Emacs no longer shows localized
built-in labels, so a non-English web locale and the Emacs picker differ.
If upstream starts publishing names for shipped presets, the picker will
use them automatically.
