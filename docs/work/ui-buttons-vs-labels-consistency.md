# UI pass: buttons look like buttons, labels look like labels (consistent + clear)

## Problem
The **"Spectating" status pill** is styled like the Join/Leave **buttons** (same rounded fill + stroke), so
it reads as a clickable button — but it's just a non-interactive STATUS LABEL. Scott wants a clear visual
language: actual buttons look tappable, status/labels look static, and the HUD is consistent + easy to
understand.

## What to do
- **Restyle the "Spectating / #N in line / NEXT UP" pill as a LABEL, not a button:** drop the button look
  (the filled, stroked, rounded "tappable" pill that matches Join/Leave). Make it visually clearly
  NON-interactive — e.g. a flat/subtle text banner or plain text (transparent or low-opacity background, no
  button-style stroke/AutoButtonColor, lighter weight), distinct from the buttons. It just reports state.
- **Keep/Make the real BUTTONS clearly button-like:** Join Game + Leave/Spectate should read as tappable —
  a solid filled colour, consistent button shape/size, `AutoButtonColor`, a clear label. Join (enter) and
  Leave (exit) can share the button style (maybe different accent colours: green = go/join, neutral/red =
  leave); the disabled "In queue (#N)" state should look visibly disabled (greyed, non-tappable).
- **Consistency / clarity pass across the HUD** — audit every on-screen element and make the language
  coherent (interactive vs informational clearly distinguished, consistent corner radius / padding / font
  scale / colour roles):
  - Buttons: Join Game, Leave/Spectate, the mobile camera-mode toggle.
  - Labels / status (NON-interactive): the Spectating/queue pill, the rank pill ("Rank N" / "KING"), the
    stats panel (Best / King Turns / Turns), the event toasts.
  - Make sure nothing non-interactive looks tappable, and nothing tappable looks like a static label.
  - Group related UI sensibly (the right-side lobby column under the scoreboard from the last task — keep
    that placement; just fix the button-vs-label styling within it).
- Centralise the shared style values (button colour/size/corner, label style) in `GridConfig` (or a small
  client style table) so it's consistent + tweakable.

## Acceptance criteria
- The Spectating/queue status reads as a **label** (clearly not a button); Join Game + Leave read as
  **buttons** (clearly tappable); the disabled queued state looks disabled. No non-interactive element looks
  clickable, and vice versa.
- The HUD is visually **consistent** (shared button style; shared label style; coherent radius/padding/
  fonts/colour roles) and easy to understand at a glance.
- Verified via `screen_capture` in the lobby/spectating state AND a seated state, on desktop and a phone
  aspect. No functional/behaviour change (buttons still do what they did; the leave/join/queue logic,
  cameras, gameplay are unchanged). Studio left in Edit.

## Relevant files
- `src/client/NineSquareClient.client.luau` — the lobby UI column (Join Game / Leave / Spectating pill) +
  the mobile camera toggle button styling.
- `src/client/RankHud.client.luau` — the rank pill, the mobile stats panel, the event toasts (label styling
  + consistency).
- `src/shared/GridConfig.luau` — shared UI style tunables (button vs label colours/sizes/corner/font) if
  centralising.
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; client UI on the Client
  datamodel in Play; standalone `require` STALE — verify via `script_read`/`get_console_output`;
  `screen_capture` lobby + seated, desktop + phone aspect, to confirm buttons-vs-labels read correctly.
  Leave Studio in Edit.)

## Constraints
- Visual/UI styling ONLY — don't change behaviour (Join/Leave/queue logic, cameras, occupancy, gameplay),
  the right-side placement from the previous task, or what each element DOES. Keep it consistent + legible
  on mobile + desktop. Tunables in `GridConfig`.
