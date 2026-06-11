# Sound effect on any player impact (human + bot strikes)

## Problem
Ball↔player contact is silent — a strike has no audio feedback, which makes hits feel weightless.
Add a satisfying "bump/pop" sound effect on **every player strike** (the local human AND all 8 bots)
so each volley reads with impact.

## Decisions (from the user)
- **Trigger scope:** every player STRIKE — any ball↔player contact resolved by the strike collision,
  human and bots alike (NOT floor/wall bounces for now). One sound per strike.
- **Sound source:** pick a **fitting Roblox SFX** — a short volleyball-ish bump/pop/thump. Source it from
  the Roblox creator store / audio library (use the `robloxstudio` MCP `search_creator_store` /
  `insert_from_creator_store`, or a known free rbxassetid). Pick something punchy and short (not a long
  tail); confirm it actually loads/plays in Play.

## Approach
- The strike already has a single server-side hook that fires for **both** human and bot hits (they go
  through the same `BallController` collision): `onPlayerHit(struckCell, targetCell, wasServe)`. Play the
  SFX there (covers human + bots automatically). Do NOT play on serves if it feels off — but a serve is a
  strike too, so default to playing on serves as well unless it sounds wrong.
- Make it **3D/positional** so it emits from the ball: parent a `Sound` to the Ball part (or an Attachment
  at the contact point) and play it **server-side** so every client hears it (replicates). Use a small
  pool / `:Clone()` per hit (or check `IsPlaying`) so rapid rallies don't cut the previous sound off
  abruptly. Optional polish: small random-ish pitch variance per hit for liveliness (deterministic-friendly
  — e.g. seed from a hit counter, since `Math.random` is discouraged in the hot server loop; a tiny
  `PlaybackSpeed` jitter is fine).
- Keep `Volume`, `RollOffMaxDistance`/range, and the asset id as **tunables in `GridConfig`**
  (e.g. `impactSoundId`, `impactSoundVolume`, `impactSoundRange`, `impactPitchJitter`).

## Acceptance criteria
- A short bump/pop sound plays on **every** human strike AND every bot strike, emitted from the ball's
  position (audible/positional), one per hit — verified in Play (listen through a few rallies: human hits
  and bot volleys both sound; no silence, no error spam in the console, no harsh cutoffs during fast
  rallies).
- The asset id loads (no "failed to load asset" warnings); volume is reasonable (not blown out).
- Doesn't change the strike physics, collision, aim, save/fault, or rotation — audio only. Tunables live
  in `GridConfig`.

## Relevant files
- `src/server/BallController.luau` — the strike collision + the `onPlayerHit` hook fired for human & bot
  contacts (the trigger point); ball part reference for the positional Sound.
- `src/server/NineSquareServer.server.luau` — where `onPlayerHit` is wired; create/parent the Sound + the
  pool there, or in BallController — keep it server-authoritative so it replicates to all clients.
- `src/shared/GridConfig.luau` — `impactSoundId` + volume/range/pitch tunables.
- Use the `robloxstudio` MCP to find + insert the sound and to verify in Play (mode flip-flops —
  `get_studio_state` first; standalone `require` reads a STALE module — verify via `script_read` /
  `get_console_output`; leave Studio in **Edit**).

## Constraints
- Audio only — don't touch the strike formula, swept collision, `botJumpVelocity`, aim, save/fault, or
  rotation. One sound per strike; pool/clone so overlapping rapid hits don't cut off. Keep the asset id +
  volume/range in `GridConfig`. Server-side play so all clients (human + spectating) hear it.
