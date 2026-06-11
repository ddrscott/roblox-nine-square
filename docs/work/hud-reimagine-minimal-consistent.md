# Re-imagine the HUD: minimal, consistent, not stats-heavy

## Problem / direction (from Scott)
The HUD is too busy and inconsistent, and the message feed still blocks the court. Re-imagine it for
EFFICIENCY + CONSISTENCY. Specifics Scott called out:
- **Don't announce every rank change** — it's obvious from your starting position (the floor rank numbers +
  where you stand). Drop the rank-change toasts.
- **This isn't a stats-heavy game** — the scoreboard only needs **Turns** and **TAK (Turns as King)**.
- Make it look CONSISTENT (one cohesive visual language) and stop the messaging covering the play area.

## What to build
### 1. Scoreboard = just Turns + TAK
- The stats readout shows only **Turns** (total rallies played = `totalTurns`) and **TAK** = **Turns as
  King** (= `kingTurns`). **Remove "Best"** (best rank) from the display. Keep it compact, top-right,
  consistent with the shared `GridConfig.uiStyle`. (Server-side stat TRACKING can stay as-is — `bestRank`
  can remain in the saved profile, just not shown; only the DISPLAY changes to Turns + TAK. Rename the
  leaderstats accordingly: `Turns`, `TAK`.)

### 2. Kill the rank-change announcements + the redundant rank pill
- REMOVE the rank-change toasts (the "Faulted — back to Rank 9" / "Moved up — now Rank N" notices). Rank is
  obvious from position; don't announce it.
- REMOVE the persistent "Rank N" pill entirely (it's redundant with the floor numbers + your position),
  freeing the left side. (Optional: a small, subtle KING indicator only when you ARE the King — but no
  generic rank pill.)

### 3. Trim the message feed to the bare minimum + make it unobtrusive
- The court fills the screen and the corners are occupied, so keep any remaining notices **transient,
  small, semi-transparent, and auto-fading fast** so they flash briefly and never persistently block the
  play area. Cut chatty events — keep at most the few that matter (e.g. a brief "You're in" on seating, a
  dethrone/new-King moment); drop the rest. Lean toward LESS.

### 4. Consistency / efficiency pass
- Unify the surviving HUD — scoreboard (Turns/TAK), Join/Leave button, Spectating status, stamina meter,
  and any remaining transient notice — into ONE consistent style (shared `GridConfig.uiStyle`: fonts,
  corners, colours, label-vs-button language) and a clean, uncluttered layout. Nothing persistent should sit
  over the court. Responsive (compact on mobile).

## Acceptance criteria
- The scoreboard shows ONLY **Turns** and **TAK** (no Best); leaderstats renamed to match; values still
  update correctly (Turns = rallies played, TAK = rallies as King).
- No rank-change announcements; no persistent "Rank N" pill. The left side is clear of the court.
- Any remaining on-screen notices are minimal + transient + semi-transparent and do NOT block the play area.
- The HUD reads as ONE consistent, efficient design (shared style); uncluttered on desktop AND mobile.
  Verified via `screen_capture` (seated + lobby, desktop + phone aspect; trigger a couple of events).
- Behaviour/gameplay unchanged (stat tracking, seating, cameras intact) — this is HUD presentation only.
  Studio left in Edit.

## Relevant files
- `src/client/RankHud.client.luau` — remove the rank pill + rank-change toasts; trim/transient the message
  feed; the Turns/TAK readout if shown here.
- `src/client/NineSquareClient.client.luau` — the lobby/Join/Leave/Spectating UI + the scoreboard area;
  consistency pass.
- `src/server/StatsService.luau` / `NineSquareServer.server.luau` — leaderstats renamed to `Turns` + `TAK`
  (display only Turns + kingTurns); stop firing the rank-change HUD events (or stop the client rendering
  them). Keep stat tracking working.
- `src/shared/GridConfig.luau` — `uiStyle` + any layout tunables; drop now-unused toast/rank tunables.
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; standalone `require`
  STALE — verify via `script_read`/`get_console_output`; `screen_capture` desktop + phone, seated + lobby.
  Leave Studio in Edit.)

## Constraints
- HUD presentation only — don't change gameplay, the stat TRACKING math (Turns/TAK still increment
  correctly), seating/lobby flow, cameras, or the world. Keep ONE consistent style (`uiStyle`). Minimal +
  transient messaging; nothing persistent over the court. Responsive on mobile. Tunables in `GridConfig`.
