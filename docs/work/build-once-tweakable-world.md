# Make the world build-once / self-heal so Studio tweaks persist (kids can adjust parts)

## Problem
Scott changed the `GridLines` parts to solid white in Studio, but on the next Play they reverted — because
`MatchService.buildArena` **destroys and rebuilds the entire `workspace.NineSquare` folder every Play**
(`local old = workspace:FindFirstChild("NineSquare"); if old then old:Destroy() end`), regenerating Floors /
FloorNumbers / Frame / FrameLegs / GridLines / SaveHighlight / CourtSpawn from code. `setupLighting`
(NineSquareServer) likewise re-applies Lighting and **replaces the Sky** every Play. So any manual tweak in
the standard Studio interface gets clobbered. Goal: let Scott + his kids tweak the physical objects (and
lighting) in Studio and have those tweaks **persist** — the scripts should only build what's MISSING.

## Goal / principle
Flip the world build from "rebuild every Play" to **build-once / self-heal**, matching what `buildGym` /
`buildOutdoors` already do (`if workspace:FindFirstChild(...) then return end`). After this, the **saved
place (.rbxl) is the source of truth for appearance**; the scripts only (re)build a piece when it's ABSENT
(fresh/empty place or a deleted part). Manual color/size/position/material tweaks in Studio survive Play.

## Changes
### 1. `MatchService.buildArena` → build-once / self-heal (the main fix)
- **Always** set runtime state the rest of the game needs, even when not rebuilding: `G.origin = origin`
  (cellCenter / cellAtPosition / ball + bot + player positioning all read `G.origin` at runtime — this MUST
  be set every Play; origin is the stable hardcoded `(0,0,200)`).
- Then **do NOT destroy `NineSquare` if it already exists.** Remove the `old:Destroy()` wipe. If the folder
  is present, LEAVE all its children alone (so tweaks persist) and return it.
- **Self-heal a fresh/empty place:** if `NineSquare` (or a critical sub-folder) is MISSING, build just the
  missing piece(s) from code as today. Recommended granularity: ensure each critical sub-group exists —
  `Floors` (flash targets), `Frame` (the ball collides against these — see BallController._surfaces),
  `FloorNumbers`, `GridLines`, `FrameLegs`, `SaveHighlight`, and `CourtSpawn` — building only the ones that
  are absent, never overwriting ones that are present. (Folder-level "build the whole thing only if
  NineSquare is absent" is acceptable if cleaner, as long as a totally fresh place still self-builds.)
- Keep the idempotent, non-clobbering housekeeping running each Play (it doesn't fight tweaks): dropping the
  Baseplate out of view and disabling stray `SpawnLocation`s. Ensure CourtSpawn still exists (self-heal if
  absent).

### 2. `setupLighting` (NineSquareServer) → apply-once, don't clobber manual lighting/sky
- Stop replacing the `Sky` and re-stamping Lighting properties on every Play. Guard with a sentinel so it
  applies ONCE on a fresh place, then leaves Lighting / Sky / Atmosphere alone so they're tweakable: e.g.
  `if Lighting:GetAttribute("NineSquareLit") then return end` … set everything … then
  `Lighting:SetAttribute("NineSquareLit", true)`. Self-heal only if the Sky/Atmosphere is missing.
  (Lighting.Technology still can't be set by script — leave the existing note.)

### 3. Functional safety (don't break the game)
- Runtime code already looks parts up by name (`flashCell`→`Floor_<cell>`, `highlightSavedCell`/
  `clearSaveHighlight`→`SaveHighlight/Seg_*`, `BallController._surfaces`→parts under `NineSquare.Frame`,
  FloorNumbers, `CourtSpawn`). With build-once these persist. Verify these lookups stay correct whether the
  parts were script-built OR hand-tweaked, and that a MISSING part degrades gracefully (already guarded with
  `if not … then return`) — ideally self-healed by the build so deleting a part doesn't permanently break a
  feature. The deterministic ball physics is UNCHANGED — it just now collides against the persisted Frame.

### 4. README
- Document the new model: "The arena/gym/gallery/outdoors are **built once** — the saved place is the
  source of truth for how everything LOOKS. Tweak any part in Studio (color, size, material, position) and
  **Publish/Save** the place; the scripts won't overwrite it. They only rebuild a piece that's missing
  (fresh place / deleted part). Lighting + sky are applied once (sentinel `Lighting.NineSquareLit`) and are
  likewise tweakable." Note kids can freely re-color/move parts; they should avoid DELETING the functional
  ones (Frame beams, Floor_ markers) — but those self-heal if removed.

## Acceptance criteria
- Tweak a part in Studio (e.g. set `GridLines` parts to solid white — Scott's case — or recolor a wall),
  Save, then Play: the tweak **PERSISTS** (no script reverts it). Confirmed specifically for GridLines→white.
- Lighting / Sky tweaks in Studio also persist across Play (apply-once sentinel).
- A FRESH / empty place (no `NineSquare`/`Gym`/Sky) still **self-builds** the full world on Play (the game
  is not broken for a clean bootstrap).
- The full game still works on the persisted world: ball collides off the Frame, fault flash, save-pipe
  highlight, floor numbers, court spawn, rotation, serve, bots — all intact (no regression).
- Verified via the MCP: tweak a GridLines part white in Edit → Play → assert it's still white (not reverted)
  and gameplay runs; then delete `NineSquare` (or a sub-folder) → Play → assert it self-heals. Studio left
  in Edit.

## Relevant files
- `src/server/MatchService.luau` — `buildArena` build-once/self-heal (always set `G.origin`; stop the
  `NineSquare` wipe; build only missing pieces). `buildGym`/`buildGallery`/`buildOutdoors` already build-once
  — leave them (confirm they don't clobber tweaks).
- `src/server/NineSquareServer.server.luau` — `setupLighting` apply-once sentinel; the build call order
  (`setupLighting` / `buildGym` / `buildArena`) stays, but each is now non-clobbering.
- `README.md` — document the build-once / tweak-and-save model.
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; standalone `require`
  is STALE — verify via `script_read`/`get_console_output` + the persistence test above; `screen_capture`
  works now if you want a visual confirm. Leave Studio in Edit.)

## Constraints
- Build-lifecycle change ONLY — do NOT change gameplay, physics, the strike/collision, rotation, seating,
  queue, or stats. Origin stays the hardcoded `(0,0,200)` so persisted geometry always matches runtime
  positioning. A fresh place MUST still self-build (don't break clean bootstraps). Deterministic +
  server-authoritative preserved. The whole point: physical objects (and lighting) become tweakable through
  the standard Studio interface and survive Play.
