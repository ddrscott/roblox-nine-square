# M4 step 2: bot bodies + difficulty tune + acceptance (close out M4)

See the M4 design spec `docs/superpowers/specs/2026-06-10-nine-square-m4-bots-design.md` (§4, §6 step 2).
Step 1 makes bots volley/miss (the loop is a real game). This step adds the look + tuning + closeout.

## Build
### A. Bot bodies (leverage Roblox Humanoid)
- Upgrade the cosmetic dummy cylinders into believable **bot avatars**: either a Roblox `Humanoid` NPC rig
  (so they read as players) or a stylised body — your call, keep it cheap. They stand in their square and
  are re-placed by `RotationService.placeAll` on rotation (unchanged).
- On a volley, play a quick **hop / jump** (animation or a short tween) so the hit reads visually. Optional:
  `Humanoid:MoveTo` the ball's predicted landing XZ within the square just before the volley for
  believability (don't over-engineer pathfinding — bots don't leave their square).
- Keep bot bodies **out of `BallController._surfaces`** and `CanCollide = false` so the ball never collides
  with them (the hit stays server-resolved).

### B. Difficulty tune
- Tune `GridConfig.botMissChance` so the rotation rate feels good — frequent enough that the human climbs
  and rallies end, not so frequent that nobody volleys. (A single "Normal" value is fine for M4; the
  difficulty enum + per-difficulty curves can be a later refinement.)
- Sanity-check the bot volley speed/arc so bot→center→bot rallies are returnable and read well.

### C. Acceptance + docs (close out M4)
- Run the solo loop and confirm the §1 M4 criteria: bots serve + volley with the aim rule, miss at the
  tuned rate, real rallies happen, the human climbs and can reach **King**, and a **bot-King fault fires
  the dethrone**.
- Append a **"## M4 Acceptance"** section to the M4 design spec (date 2026-06-10, pass/fail per §1 criterion
  with console/screenshot evidence, final tuned bot values).
- Update the **README** Status + milestone list to mark **M4 done** and **M5 next**; add the M4 spec to the
  Docs index if not already; refresh the Layout list if you added `BotController`.

## Acceptance criteria
- Bots have visible bodies that hop/animate on a volley; they sit one-per-square and re-place on rotation.
- `botMissChance` tuned so the loop rotates at a fun cadence and the human can realistically climb to King.
- A bot-King fault triggers the dethrone emphasis (from M3). Full solo game is playable.
- M4 Acceptance recorded in the spec; README marks M4 done / M5 next. Verified in Play (screenshots/console).

## Relevant files
- `src/server/RotationService.luau` / `src/server/MatchService.luau` — bot body build/placement (wherever
  the dummies are currently created).
- `src/server/BotController.luau` — trigger the volley hop animation (server-driven).
- `src/shared/GridConfig.luau` — `botMissChance` (+ body/anim tunables).
- `docs/superpowers/specs/2026-06-10-nine-square-m4-bots-design.md` — M4 Acceptance section.
- `README.md` — Status + milestone list (M4 done, M5 next) + Docs/Layout.
- Deploy via the `robloxstudio` MCP; verify in Play (mode flip-flops; leave Studio in **Edit**).

## Constraints
- Keep it minimal/cheap — M4 is "bots that play," not full polish (full VFX/leaderboard/reign timer = M6).
- Server-authoritative; bot bodies cosmetic + non-colliding with the ball. Don't break the M3 loop, the
  human's physical volley, the rank HUD, camera, or the no-trip fix. Tunables in `GridConfig`.
