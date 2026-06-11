# Sun directly overhead (centered) so shadows fall straight down over the play area

## Goal
Move the sun to be **directly over the building, centered**, so shadows fall **straight down** — the
overhead frame's shadow (and the building's) lands symmetric/centered on the play area instead of skewed off
to one side. Keep it a clear day; keep interior gym lighting working.

## Approach (Roblox sun = ClockTime + GeographicLatitude)
- Sun elevation/azimuth is driven by `Lighting.ClockTime` (time of day) and `Lighting.GeographicLatitude`
  (path tilt). For the sun at the **zenith** (straight up at solar noon): set **`ClockTime = 12`** and
  **`GeographicLatitude = 0`** so the sun passes directly overhead — `Lighting:GetSunDirection()` should be
  ≈ `(0, 1, 0)` (pointing straight up), giving straight-down shadows centered under objects.
- The current `setupLighting` (NineSquareServer) uses `GeographicLatitude = 23.5` + `ClockTime =
  outdoorClockTime (~14)`, which puts the sun off-zenith → angled shadows. Adjust those (tune empirically)
  until the sun reads vertical and the frame shadow lands centered over the court. Put the final values in
  `GridConfig` (e.g. `outdoorClockTime`, a `sunLatitude`).
- The court has a CEILING with an opening over the play area — a zenith sun shines straight down through the
  opening, so the overhead frame casts its shadow squarely onto the grid. (If real-time shadows are faint in
  the engine, that's fine — the painted GridLines remain; this is about the sun being centered/vertical.)

## Gotcha (apply-once lighting)
`setupLighting` is now behind a `Lighting:GetAttribute("NineSquareLit")` sentinel (the build-once /
tweakable-world change) so it doesn't clobber manual tweaks. To make the new sun take effect: update the
code values AND ensure they actually re-apply — on the current place, clear/reset the sentinel (or set the
sun values directly) so the change shows now; and confirm a FRESH place gets the new sun on first run. Don't
remove the sentinel mechanism (kids should still be able to tweak lighting afterward).

## Acceptance criteria
- The sun is directly overhead / centered: `Lighting:GetSunDirection()` ≈ vertical `(0, ~1, 0)`; shadows
  fall straight down, centered on the play area (not angled off to a side).
- Still a bright clear day; the clear-day sky, atmosphere, and interior gym lighting are intact (no
  over-darkening / no broken sky).
- The new values are the default for a fresh place AND applied to the current place; the apply-once sentinel
  still lets manual lighting tweaks persist afterward.
- Verified via the MCP (assert `GetSunDirection` ≈ vertical; a `screen_capture` from above showing the
  shadow centered over the court). Studio left in Edit.

## Relevant files
- `src/server/NineSquareServer.server.luau` — `setupLighting`: set `ClockTime`/`GeographicLatitude` for a
  zenith sun; re-apply respecting the `NineSquareLit` sentinel.
- `src/shared/GridConfig.luau` — sun tunables (`outdoorClockTime`, a `sunLatitude`/equivalent).
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; standalone `require`
  is STALE — verify via `script_read`/`get_console_output` + `Lighting:GetSunDirection()`; `screen_capture`
  works. Leave Studio in Edit.)

## Constraints
- Lighting only — don't change gameplay, the court, the build geometry, or the wall-fade. Keep the clear-day
  look + interior lighting. Respect the apply-once sentinel (kids can still tweak). Tunables in `GridConfig`.
