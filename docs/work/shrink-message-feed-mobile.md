# Shrink the in-game message feed (esp. mobile) so it doesn't block the action

## Problem
The in-game messaging — the event/toast feed (join / leave / auto-seat / dethrone / King / rank-change
notes, currently top-LEFT) — takes up **too much space and blocks too much of the play area, especially on
mobile**. Make it smaller / less intrusive, particularly on phones.

## What to do
- Make the toast feed **compact + responsive**, gated on mobile/touch/narrow aspect (reuse the existing
  mobile detection — e.g. `UserInputService.TouchEnabled` and/or the `mobileStatsAspectMax` viewport-aspect
  check the stats panel uses):
  - **Narrower** holder + **smaller font** on mobile (the current ~340px-wide, 340x28 toasts are a big chunk
    of a phone screen) — shrink width and text so it's a small corner feed, not a banner across the view.
  - **Fewer simultaneous lines** on mobile (e.g. cap at ~2 vs the current ~4) so it never stacks tall over
    the court.
  - **Shorter on-screen duration** so messages clear faster (less time blocking the action) — or fade them
    quicker.
  - Keep it readable, top-LEFT (the prior placement), clear of the rank pill (above it) and the play area.
- Desktop can stay as-is or also be trimmed a touch — the priority is mobile. Keep the same events firing;
  this is sizing/duration/line-count only (no behaviour/content change).
- Put the sizes / max-lines / duration in `GridConfig` (mobile vs desktop values) so they're tunable.

## Acceptance criteria
- On a phone aspect: the message feed is noticeably **smaller** (narrower + smaller text + fewer lines +
  shorter duration) and clearly does NOT block the court/action; still legible. Verified via `screen_capture`
  on a phone aspect (trigger a few events — join/rotation — to see toasts).
- On desktop: still readable, not regressed.
- The events still fire and read correctly (content unchanged); doesn't overlap the rank pill or other HUD.
  Studio left in Edit.

## Relevant files
- `src/client/RankHud.client.luau` — the toast feed (`toastHolder` + per-toast size/font/duration + the
  max-visible-lines cap); add the mobile-compact sizing.
- `src/shared/GridConfig.luau` — toast feed tunables (mobile/desktop width, text size, max lines, duration).
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; client UI on the Client
  datamodel in Play; standalone `require` STALE — verify via `script_read`/`get_console_output`;
  `screen_capture` on a phone aspect + desktop with a few toasts visible. Leave Studio in Edit.)

## Constraints
- UI sizing/duration ONLY — don't change what events fire or their text, gameplay, or other HUD elements'
  placement (keep the feed top-left under the rank pill). Responsive: compact on mobile without breaking
  desktop. Tunables in `GridConfig`.
