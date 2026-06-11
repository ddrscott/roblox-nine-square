# Play a squeak sound on every player jump (varied playback speed)

## Goal
Play a sound (Scott's `rubber-squeak.wav`) **every time a player jumps**, at a **varied playback speed**
each jump (like the impact SFX pitch jitter). Heard by everyone, emitted from the jumping player.

## Asset (Scott uploads — MCP can't upload audio)
Roblox needs the audio uploaded as an asset (`rbxassetid://…`); the local `~/Downloads/rubber-squeak.wav`
can't be referenced directly and the MCP has no audio-upload tool. Scott uploads it (Studio → Asset Manager
→ Audio → Import, or create.roblox.com → Creations → Audio) and pastes the asset ID into
`GridConfig.jumpSoundId`. **Until the real ID is set, use a TEMPORARY built-in `rbxasset://` sound as a
placeholder** so jumps are audible/testable now — Scott swaps in the real ID later (one-line change).

## Build
- New `GridConfig` tunables: `jumpSoundId` (= the uploaded asset id; placeholder built-in for now),
  `jumpSoundVolume`, `jumpSoundRange` (RollOffMaxDistance), and a playback-speed range
  `jumpSoundPitchMin` / `jumpSoundPitchMax` (e.g. ~0.85–1.2) for the per-jump variation.
- **Detect each (human) player's JUMP, server-side**, so the sound replicates to all clients + is positional
  (emitted from the jumper). Hook each character's `Humanoid` jump — e.g. `Humanoid.Jumping:Connect(active →
  if active then play)` (or `StateChanged`→`Jumping`), wired on `PlayerAdded` → `CharacterAdded`. Play a
  `Sound` parented to the character's `HumanoidRootPart` (clone-per-jump or a small pool so rapid jumps
  don't cut off), with a **random `PlaybackSpeed` in [jumpSoundPitchMin, jumpSoundPitchMax]** each jump
  ("varied play speeds"). Debris-reap the clone after its tail. Debounce so one jump = one sound (the
  `Jumping` event can fire repeatedly; guard with a short per-character cooldown).
- Scope: HUMAN players (the natural reading of "a player jumps"). Bots jump via a server-driven collider,
  not a Humanoid jump, so they're excluded by default — fine. (If Scott later wants bot jumps to squeak too,
  that's a small add.)
- Mirror the existing impact-SFX pattern (`NineSquareServer` `playImpact`: server-side Sound on the ball,
  clone + Debris + pitch jitter) for consistency. Audio only — no gameplay/physics change.

## Acceptance criteria
- Jumping plays the squeak from the jumping player, at a randomized playback speed each jump; other players
  hear it (positional). One sound per jump (debounced, no machine-gun on the repeating Jumping event).
- Driven by `GridConfig.jumpSoundId` — set to the placeholder now; swapping in Scott's uploaded asset id
  (one value) makes it play the real squeak with NO other change.
- No regression to movement/dash/flip behaviour or gameplay. Verified in Play via the MCP (jump → a sound
  plays, varied PlaybackSpeed across jumps; confirm the clone + speed via the live datamodel / console even
  if the placeholder asset is a stand-in). Studio left in Edit.

## Relevant files
- `src/server/NineSquareServer.server.luau` — add the jump-sound system (PlayerAdded → CharacterAdded →
  Humanoid jump hook → play a pooled/cloned Sound on the HRP with random PlaybackSpeed + debounce); mirror
  the existing `playImpact` helper.
- `src/shared/GridConfig.luau` — `jumpSoundId` (+ volume/range/pitch-min/pitch-max).
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; standalone `require`
  STALE — verify via `script_read`/`get_console_output`; in Play, jump and confirm a Sound instance spawns
  on the HRP with a PlaybackSpeed in range that varies across jumps. Leave Studio in Edit.)

## Constraints
- Audio only — don't change movement/jump/dash/flip physics or gameplay. Server-authoritative + positional
  (so everyone hears each jump). Debounce one-sound-per-jump. Tunables in `GridConfig`; the asset id is a
  single swappable value (placeholder built-in until Scott's upload clears moderation).
