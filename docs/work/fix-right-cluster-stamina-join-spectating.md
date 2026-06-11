# Polish the top-right cluster: readable stamina, less-bold Join, Spectating-as-label

## Problem (from Scott's screenshot of the top-right HUD)
1. **STAMINA caption is unreadable** — the "STAMINA" text sits on the light-blue bar fill, too low-contrast
   / small to read.
2. **"Join Game" is too bold** — the button text is too heavy/loud.
3. **"Spectating" still looks like a button** — the dark rounded "Spectating" status pill reads as a second
   clickable button; it's a non-interactive STATUS label and should read that way.

## What to do (right-side lobby/stamina cluster; shared `GridConfig.uiStyle`)
- **Stamina label readable:** make "STAMINA" legible — bump contrast (dark/da rker text or an outline), and/or
  move the caption OFF the colored fill (e.g. a small label above/beside the bar), and/or just drop the word
  and let the bar speak for itself. Goal: you can clearly read/identify the stamina bar. Keep it slim + in
  the right cluster.
- **"Join Game" less bold:** lighter font weight (e.g. GothamMedium instead of GothamBold/Black) and/or
  slightly smaller — calmer, not a shouting CTA. It's still a clear green button, just not heavy.
- **"Spectating" → clear LABEL, not a button:** remove the button-pill look (no filled rounded "tappable"
  pill matching Join Game) — make it flat / subtle (transparent or very low-opacity bg, no button-style
  stroke, lighter text), visually distinct from the Join/Spectate BUTTONS. It only reports state. (Re-apply
  the buttons-vs-labels language from the earlier UI pass — it still reads as a button in this cluster.)
- General: tidy the corner so the three elements (stamina, Join button, Spectating status) read clean +
  consistent, with consistent spacing/sizing and the shared style.

## Acceptance criteria
- The stamina bar's identity is clearly READABLE (the caption legible, or cleanly dropped) — verified via
  `screen_capture` of the corner.
- "Join Game" is noticeably less bold/loud but still clearly a tappable green button.
- "Spectating" reads as a non-interactive LABEL (flat/subtle), NOT a button — clearly different from the
  Join/Spectate buttons.
- The top-right cluster looks clean + consistent (shared `uiStyle`); desktop AND a phone aspect. Behaviour
  unchanged. Studio left in Edit.

## Relevant files
- `src/client/Movement.client.luau` — the stamina bar UI (caption contrast/placement).
- `src/client/NineSquareClient.client.luau` — the lobby cluster: "Join Game" button weight/size + the
  "Spectating" status styling (make it a label, not a button).
- `src/shared/GridConfig.luau` — `uiStyle` (label vs button fonts/weights/fills) + any stamina/lobby tunables.
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; client UI on the Client
  datamodel in Play; standalone `require` STALE — verify via `script_read`/`get_console_output`;
  `screen_capture` the top-right corner in the lobby/watching state, desktop + phone aspect. Leave Studio in
  Edit.)

## Constraints
- UI styling ONLY — don't change behaviour (stamina logic, Join/leave flow), placement cluster (stays
  top-right), gameplay, or other HUD. Keep ONE consistent style (`uiStyle`): buttons look tappable, the
  Spectating status looks like a static label, text is legible. Tunables in `GridConfig`.
