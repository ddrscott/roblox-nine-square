--!strict
-- ReplicatedStorage.GridConfig
-- Tunable dimensions + pure grid/contact math for 9 Square M1. No side effects.
local GridConfig = {}

-- Dimensions (studs / seconds). All tunable; values are greybox starting points.
GridConfig.squareSize = 14          -- one square edge
GridConfig.floorThickness = 1
GridConfig.frameHeight = 11         -- contact plane = measured jump reach (apex ~11.2; std-jump 7.2 + hit-zone ~4)
GridConfig.beamThickness = 0.5
GridConfig.legThickness = 1.0       -- cosmetic corner support posts (floor->frame); a touch thicker than beamThickness
GridConfig.ballRadius = 2           -- ball sphere radius (4-stud diameter)
GridConfig.apexHeight = 16          -- (legacy) extra bulge for the old lerp-arc serve
GridConfig.serveTravel = 1.1        -- (legacy)
GridConfig.descentWindow = 0.8      -- (legacy)
GridConfig.hitZoneRadius = 1.6      -- contact sphere radius (covers the head; you volley with your head)
GridConfig.showHitSphere = true     -- debug: render the local player's contact sphere (HitSphereView client) so you can see it
GridConfig.hitZoneYOffset = 0       -- contact sphere offset above the Head part (0 = centred on the head)
                                    --   reach at std-jump apex ~= Head_Y + yOffset + radius + ballRadius
                                    --   ~= (7.2 + ~1.5) + 0 + 1.6 + 2 ~= 12.3 >= frameHeight(11): still hittable
GridConfig.ballRestitution = 0.6    -- PASSIVE bounce: how much of the ball's own incoming speed it keeps
                                    --   off a still player. <= 1 so a motionless player NEVER adds energy
                                    --   (the ball rebounds slower than it arrived, like any surface).
GridConfig.hitGain = 2.5            -- ACTIVE power: outgoing speed added along the normal per stud/s of the
                                    --   player's approach speed toward the ball -> faster hit = harder strike.
GridConfig.strikeMoveThreshold = 8  -- min approach speed (studs/s) to count as an intentional strike; only
                                    --   above this does hitMinPop apply (a still/glancing contact just bounces).
GridConfig.hitMinPop = 55           -- floor on the outgoing speed of an ACTIVE strike so a clean drive stays in play
GridConfig.hitSpeedH = 22           -- (legacy) fixed horizontal launch speed; superseded by the velocity-proportional strike
GridConfig.hitSpeedV = 72           -- (legacy) fixed vertical launch speed; superseded by the velocity-proportional strike
GridConfig.hitCooldown = 0.30       -- (legacy) old proximity-trigger debounce; the moving-sphere collision now
                                    --   repositions the ball out of the hit-sphere, so one approach = one hit (no timer)
GridConfig.minLift = 0.30           -- floor on the contact normal's vertical part (biases a clean bump upward)
-- Impact SFX: a short bump/pop played server-side from the ball on EVERY player strike (human + bots, since
-- both go through BallController:onPlayerHit). Server-side so it replicates to all clients (players +
-- spectators) and is positional (emitted from the ball part). `impactSoundId` is a built-in rbxasset that
-- ships with the engine -> always loads, no asset-permission warnings. A small clone-pool + per-hit pitch
-- jitter (seeded from a hit counter, NOT math.random in the hot loop) keeps fast rallies crisp.
GridConfig.impactSoundId = "rbxasset://sounds/snap.mp3"  -- short (~0.42s) percussive bump/pop; built-in, always loads
GridConfig.impactSoundVolume = 0.8  -- reasonable level (not blown out)
GridConfig.impactSoundRange = 90    -- RollOffMaxDistance (studs) the strike is audible within
GridConfig.impactPitchJitter = 0.12 -- +/- PlaybackSpeed variance per hit for liveliness (0 = no jitter)
GridConfig.floorRestitution = 0.55  -- ground bounciness: fraction of vertical speed kept per floor bounce
GridConfig.floorFriction = 0.72     -- horizontal speed kept per floor bounce (so it rolls to a stop)
GridConfig.restSpeedV = 8           -- settle once a floor bounce would rise slower than this (studs/s)
GridConfig.restSpeedH = 4           -- ...and horizontal speed is below this
GridConfig.steerConeDeg = 15        -- (legacy)
GridConfig.lobTravel = 1.0          -- (legacy)
GridConfig.lobDistance = 14         -- (legacy)

-- Movement skill moves (client-side; M1 reads replicated HRP velocity, so these velocities feed the
-- velocity-proportional strike directly -- no strike-formula change). All tunable.
GridConfig.doubleTapWindow = 0.25   -- max seconds between two taps to count as a double-tap (dash & flip)
GridConfig.dashSpeed = 40           -- horizontal burst speed applied to the character during a dash (studs/s); 2x distance over dashDuration for a longer hop
GridConfig.dashDuration = 0.18      -- how long the dash burst is held before control returns (s)
GridConfig.flipUpVelocity = 38      -- upward velocity set on the double-jump flip (studs/s); halved from 75 for a lower flip arc
GridConfig.flipForwardBoost = 26    -- horizontal velocity added in the facing direction on the flip (studs/s)
GridConfig.flipSpinTime = 0.45      -- duration of the cosmetic forward-flip rotation (s)
GridConfig.jumpVelocityMult = 1.3   -- human jump boost: the local Humanoid's default JumpPower is scaled by
                                    --   this (UseJumpPower=true) on character setup -> ~30% more upward velocity,
                                    --   so a jump-strike carries more force into the velocity-proportional hit.
                                    --   Applied per-character (each respawn gets a fresh default), so it never stacks.
GridConfig.staminaMax = 100         -- energy pool ceiling
GridConfig.staminaRegen = 28        -- energy regained per second while not spending
GridConfig.dashCost = 30            -- energy spent per dash (must have >= this to dash)
GridConfig.flipCost = 35            -- energy spent per double-jump flip (must have >= this to flip)

-- ============================================================================================
-- M5.4 -- SERVER-AUTHORITY / ANTI-CHEAT clamp tunables. The strike reads each SEATED human's replicated
-- HumanoidRootPart velocity + position as a moving hit-sphere collider (HitResolver), then BallController
-- folds it into the swept, velocity-proportional collision. A client could spoof its replicated HRP to
-- manufacture a super-hit or warp the collider into the ball. The server CLAMPS those INPUTS before they
-- reach bc:step -- it does NOT touch the deterministic ball physics or the strike formula, so legitimate
-- play (always under these ceilings) feels identical; the clamp only bites on impossible values.
-- ============================================================================================

-- Max plausible collider SPEED (studs/s) a legitimate player can carry into the strike, derived from the
-- movement tunables. Worst-case composed burst a real client can produce:
--   horizontal: dash (40) folded with the flip's forward boost (26) ~= 66 studs/s
--   vertical:   flip up-velocity (38), or a gravity-accumulated DESCENT from the flip/jump apex
-- |(66 horiz, ~40 vert)| ~= 77 studs/s at the burst; a fast fall from apex adds more vertical, so we set a
-- generous ceiling well ABOVE any legitimate composite (never bites real play) but far BELOW a spoofed
-- super-hit (e.g. 1000 studs/s). The collider's velocity magnitude is clamped to this in HitResolver.
GridConfig.maxStrikeSpeed = 120     -- studs/s ceiling on a seated human's hit-sphere velocity fed to bc:step

-- When a client has NO stamina it cannot legitimately dash/flip, so its burst velocity can't exceed plain
-- run/jump motion. The server mirrors the stamina pool (regen + spend, same formula as the client) and,
-- when a player's tracked stamina is below a dash cost, clamps that player's collider velocity to THIS
-- lower ceiling -- so a client can't dash/flip into every hit with an empty pool to cheat the
-- velocity-proportional strike. Derived from walk/run + jump (no dash burst): ~jump-up (boosted ~62) plus
-- a little horizontal; set comfortably above that, below the full-burst maxStrikeSpeed.
GridConfig.maxStrikeSpeedNoStamina = 78  -- studs/s ceiling when the player's server-tracked stamina is spent

-- Anti-teleport: max plausible per-frame DISPLACEMENT (studs) of a seated human's collider centre between
-- consecutive Heartbeats. At maxStrikeSpeed (120) over a slow ~0.06s frame that's ~7 studs; we cap at this
-- generous bound so ordinary motion (incl. a lag spike's catch-up) passes untouched, but a warp straight
-- into the ball is clamped -- the collider is moved at most this far toward its new (spoofed) position, so
-- it can't appear inside the ball in one frame. The clamped-away displacement also bounds the velocity.
GridConfig.maxFrameDisplacement = 16  -- studs cap on a seated human collider's per-frame centre jump

-- Court camera: a fixed high view the player can zoom with the mouse wheel. Zoom lerps between the
-- "out" and "in" offsets below (relative to the court origin); zooming IN also raises the look target
-- so the pitch flattens and you see less floor. zoom 0 = full out (default), 1 = full in.
GridConfig.camZoomStep = 0.12       -- zoom change per mouse-wheel notch
GridConfig.camFarEye = Vector3.new(0, 42, 38)   -- camera offset when zoomed OUT (the default view)
GridConfig.camFarLook = Vector3.new(0, 7, 0)    -- look-at offset when zoomed out (steeper, more floor)
GridConfig.camNearEye = Vector3.new(0, 24, 24)  -- camera offset when zoomed IN (closer + lower)
GridConfig.camNearLook = Vector3.new(0, 15, 0)  -- look-at offset when zoomed in (raised -> pitch up, less floor)
-- Shift toggles FOLLOW mode: the camera centres on the player instead of the court. Tighter, gym-safe
-- offsets (so it doesn't clip the walls when following an edge square), zoom-lerped like the court cam.
GridConfig.camFollowSmooth = 0.15   -- per-frame lerp toward the focus point (higher = snappier follow / toggle)
GridConfig.camFollowFarEye = Vector3.new(0, 26, 22)   -- follow camera offset from the player, zoomed OUT
GridConfig.camFollowFarLook = Vector3.new(0, 8, 0)
GridConfig.camFollowNearEye = Vector3.new(0, 16, 14)  -- follow offset zoomed IN (closer + pitched up)
GridConfig.camFollowNearLook = Vector3.new(0, 10, 0)
-- Camera wall fade (occlusion): the Scriptable cam skips Roblox's built-in auto-transparency, so we fade
-- the gym walls/ceiling ourselves when the camera eye crosses to their outside (would block/clip the view).
-- Whitelisted occluders only (WallE/W/N/S, Ceiling); never the floor, grid, frame, ball, player, or Glass.
GridConfig.camWallFadeTransparency = 1.0   -- target transparency for an obstructing wall/ceiling (fully transparent)
GridConfig.camWallFadeSpeed = 10           -- lerp rate per second toward the target (higher = snappier, no pop)
GridConfig.camWallFadeMargin = 6           -- studs of slack so a wall fades just BEFORE the eye reaches its plane

-- Spectator overflow (M5.2). Players beyond the 9 seats spectate from a court-overlook view and auto-join
-- the next freed seat (a live FIFO queue, server-authoritative). The gallery 3D build is M5.3; for now a
-- spectator just spawns clear of the court at a temporary overlook and watches from a high look-down camera.
-- specOverlookEye/Look are offsets (from the court origin) for the spectator camera -- higher + further back
-- than the player court cam so the whole 9-square reads. specSpawnOffset is where a spectator's character is
-- parked (clear of the court collision sets) until they're auto-seated; the real gallery spawn arrives in M5.3.
-- M5.3 wires these to the real upper-floor GALLERY (built in MatchService.buildGym). The spectator now
-- spawns/parks ON the gallery floor (south side, clear of the opening) and the overlook camera looks
-- straight DOWN through the gallery + ceiling opening onto the 9-square. galleryFloorY drives both the
-- spawn height and the camera eye height so they track the gallery build (offsets are from the origin).
GridConfig.specOverlookEye = Vector3.new(0, 60, 30)    -- spectator camera offset from the court origin (gallery height, south of the opening, looking down)
GridConfig.specOverlookLook = Vector3.new(0, 4, 0)     -- spectator camera look-at offset (the court floor below the opening)
GridConfig.specSpawnOffset = Vector3.new(0, 57, 30)    -- where a spectator's HRP is parked: on the gallery floor, south edge of the opening (galleryFloorY + ~3 foot-to-root; |z| past galleryOpening/2)

-- M5.3 Upper-floor spectator gallery (3D-asset build). A second level ABOVE the existing gym ceiling with a
-- rectangular OPENING punched through BOTH the gym ceiling AND the gallery floor over the court ("knock out
-- a window") so spectators standing on the gallery look straight DOWN onto the 9-square. Built as a RING of
-- 4 panels (N/S/E/W) around the central hole, plus short perimeter walls, a roof, a creator-store railing
-- around the opening, benches, and decor. ALL of it is purely environmental: CanCollide is true ONLY on the
-- gallery floor ring + perimeter walls (so spectators can stand/walk), and the whole gallery lives OUTSIDE
-- NineSquare.Frame so it never enters BallController._surfaces or the court collision. Heights/sizes are
-- tunable so Scott can nudge the gallery without hand-editing Studio.
GridConfig.galleryOpening = 46          -- studs: edge of the square opening over the court (court span is 42, so 46 clears the 9-square + frame with margin)
GridConfig.galleryFloorY = 54           -- studs: top of the gallery floor (y), above the gym ceiling (gym H = 50)
GridConfig.galleryFloorThickness = 1    -- gallery floor slab thickness
GridConfig.galleryWallHeight = 18       -- studs: height of the gallery's short perimeter walls (above galleryFloorY)
GridConfig.galleryRailHeight = 3.5      -- studs: height of the safety railing ringing the opening (so spectators don't fall through)
GridConfig.galleryRailInset = 0.5       -- studs the railing sits OUTSIDE the opening edge (a hair, so it rings the hole)

-- Court center on the floor; set at runtime by the server.
GridConfig.origin = Vector3.new(0, 0, 0)

-- Cell -> (dx, dz) in {-1,0,1}. +X = East, +Z = South (Roblox conventions).
GridConfig.cells = {
	NW = { dx = -1, dz = -1 }, N = { dx = 0, dz = -1 }, NE = { dx = 1, dz = -1 },
	W  = { dx = -1, dz =  0 }, C = { dx = 0, dz =  0 }, E  = { dx = 1, dz =  0 },
	SW = { dx = -1, dz =  1 }, S = { dx = 0, dz =  1 }, SE = { dx = 1, dz =  1 },
}
GridConfig.outerCells = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

-- Rank -> cell (PRD §4.2 / M3 design §3): index = rank (1..9). King = rank 1 = "C", then the
-- clockwise ring outward. The human enters at rank 9 (NW); dummies hold ranks 1..8. Config-driven:
-- change this table and placement follows (cellForRank just indexes it).
GridConfig.rankCells = { "C", "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

-- Bot occupant look. The 8 non-human squares are now REAL R15 rigs (default blocky "Rig Builder"
-- dummy), one template cloned per rank. The rig is COSMETIC + server-authoritative: its
-- HumanoidRootPart is anchored and CFrame-driven by the server (NO Humanoid:MoveTo / pathfinding /
-- self-locomotion -- WalkSpeed/JumpPower = 0), every part is CanCollide=false + Massless and lives
-- OUTSIDE NineSquare.Frame, so the ball never collides with a rig (the hit stays server-resolved on
-- the abstract hit-sphere collider in BotController). The procedural idle (sway / ready-steps /
-- ball-lean) still drives the ROOT translation; stock R15 animation tracks (idle/walk/run/jump) are
-- LAYERED on top via the rig's Animator for limb life (gated by the body's actual per-frame speed).
GridConfig.botRigTemplateName = "BotRigTemplate"  -- name of the R15 rig template under ReplicatedStorage
GridConfig.botRigFootToRoot = 3.006   -- studs from a standing R15 rig's feet up to its HumanoidRootPart
                                      --   centre (so feet sit on the cell floor: HRP_Y = floorY + this).
                                      --   Measured off the default R15 blocky rig (HipHeight 2.192 + HRP half).
GridConfig.dummyHeight = 5          -- (legacy cylinder height; retained for back-compat references)
GridConfig.dummyRadius = 1.3        -- (legacy cylinder radius)
GridConfig.dummyColor = Color3.fromRGB(120, 90, 210)   -- a clearly-non-player violet (bot body)
GridConfig.dummyKingColor = Color3.fromRGB(225, 185, 60) -- the King (rank 1 / C) stands out gold
GridConfig.botBodyColor = Color3.fromRGB(120, 90, 210)   -- bot torso/limb colour (alias of dummyColor)
GridConfig.botKingColor = Color3.fromRGB(225, 185, 60)   -- King bot colour
GridConfig.botSkinColor = Color3.fromRGB(245, 222, 179)  -- head colour (reads as a face)
GridConfig.botTorsoSize = Vector3.new(2.2, 2.6, 1.2)     -- (legacy stylised torso block; collider-only ref)
GridConfig.botHeadSize = 1.4                              -- (legacy stylised head edge; collider-only ref)
GridConfig.botArmSize = Vector3.new(0.7, 2.4, 0.7)       -- (legacy stylised arm; collider-only ref)
GridConfig.botHopHeight = 2.6        -- (legacy) studs the bot popped upward on a volley before the leap rework
GridConfig.botHopUpTime = 0.10       -- (legacy) up-leg of the old in-place hop
GridConfig.botHopDownTime = 0.22     -- (legacy) down-leg of the old in-place hop

-- Stock R15 animation ids LAYERED on the server-driven rig (cosmetic only -- limb life on top of the
-- procedural root translation). These are Roblox's public default R15 animations (always load, no
-- asset-permission warnings). The right track is chosen per frame from the rig's ACTUAL body speed:
-- below botAnimWalkSpeed -> idle; between walk/run -> walk; above botAnimRunSpeed -> run; a jump track
-- one-shots when the bot drives its collider up to strike (driveOccupant with a rising armRaise).
GridConfig.botAnimIdleId = "rbxassetid://507766666"  -- looped R15 idle
GridConfig.botAnimWalkId = "rbxassetid://507777826"  -- R15 walk cycle (intercept slide / ready-step)
GridConfig.botAnimRunId  = "rbxassetid://507767714"  -- R15 run cycle (fast intercept drive)
GridConfig.botAnimJumpId = "rbxassetid://507765000"  -- R15 jump (one-shot when striking)
GridConfig.botAnimWalkSpeed = 2.5    -- studs/s body speed above which the walk track plays (below = idle)
GridConfig.botAnimRunSpeed  = 14     -- studs/s body speed above which the run track plays instead of walk
GridConfig.botAnimWalkRate  = 0.7    -- multiplier mapping body speed -> walk/run AdjustSpeed so the cycle
                                     --   visually tracks the actual translation (higher = faster legs)
GridConfig.botAnimFadeTime  = 0.18   -- crossfade (s) between idle/walk/run tracks (smooth blend, no pop)

-- Bot LEAP-TO-BALL (M4 visual fix). Instead of a small in-place floor hop, the bot body now LEAPS up
-- toward the live contact point (~frameHeight at the ball's XZ) so it visibly meets + strikes the ball,
-- then arcs back to its square. The leap is an eased arc: ease-out up to the apex (the strike, synced to
-- bc:launch), a brief hold at contact, ease-in back down, then snap home. A raised near-arm + torso lean
-- at the apex read it as a strike, not a jump. Purely cosmetic (CanCollide stays false, server-resolved).
GridConfig.botLeapReachFrac = 0.9    -- 0..1: fraction of the way from the bot's rest pose toward the contact
                                     --   point the apex reaches (1 = body centre at the ball; 0.9 leaves the
                                     --   head/reach to close the last bit so it looks like a stretch to it)
GridConfig.botLeapMaxLeanXZ = 2.2    -- studs: cap on horizontal lean toward the ball's XZ (so a contact near
                                     --   the square edge doesn't fling the body way out of its square)
GridConfig.botLeapUpTime = 0.13      -- seconds: ease-out rise from the floor to the apex (the strike)
GridConfig.botLeapHoldTime = 0.05    -- seconds: brief hold at the apex (the moment of contact / follow-through)
GridConfig.botLeapDownTime = 0.30    -- seconds: ease-in fall back down, then snap home to the rest pose
GridConfig.botLeapTiltDeg = 18       -- degrees the torso pitches/leans toward the ball at the apex (lean-in)
GridConfig.botLeapArmRaiseDeg = 150  -- degrees the near (strike) arm swings up overhead at the apex (the reach)
GridConfig.botLeapSquashFrac = 0.12  -- a touch of stretch on the way up / squash on land for life (0 = off)

-- Serve flow (M3 step 3). A rally is always served by the King (rank 1 / C). A human King hovers the
-- ball at C and jump-strikes it (M1 physical serve); a dummy King auto-serves after `serveDelay` --
-- the server launches a deterministic arc from C's frame point to a random outer square's frame point.
GridConfig.serveDelay = 1.2          -- seconds the dummy King "winds up" before auto-serving (also the beat after a fault)
GridConfig.serveArcApex = 6          -- extra studs the auto-serve arc peaks ABOVE the higher of its two frame endpoints

-- Fault feedback. The red floor panel that marks the OUT square must stay readable from the landing
-- (onLand) through the ball's settle to rest (onRest, where the rotation now runs). flashCell uses this
-- as its default hold time; the server re-asserts the flash at onLand so it covers the whole land->rest
-- window. Generous on purpose: better to hold the red a touch long than blank it mid-settle.
GridConfig.faultFlashDuration = 2.5  -- seconds the OUT square holds red after a fault (covers land -> rest)

-- Over-the-pipe ownership (fault attribution). A ball only LEGALLY enters a square by clearing the
-- dividing pipe and dropping in. BallController tracks an `ownerCell` (the square the ball legally
-- belongs to) and only transfers it on a cell-boundary crossing whose height is at/above this
-- threshold (the ball cleared the pipe top). A crossing BELOW this (a low deflect that slid UNDER the
-- pipe into a neighbour) does NOT transfer ownership -- the ball is still the hitter's responsibility,
-- so the neighbour is not wrongly knocked out. ~= frameHeight + ballRadius: the ball's centre is above
-- the pipe top (pipe top ~= frameHeight; clearing it means the centre rose a ball radius past it).
GridConfig.pipeClearHeight = GridConfig.frameHeight + GridConfig.ballRadius  -- = 13 with current tunables

-- Bot volley (M4 step 1). Each Heartbeat BotController intercepts a DESCENDING Flight ball over a bot
-- square within `botContactBand` of frameHeight and either volleys it toward the aim target (outer->C /
-- King->random outer) reusing the serve arc, or MISSES (prob botMissChance) -> floor fault -> rotation.
GridConfig.botMissChance = 0.02      -- chance a bot fails to return the ball (-> fault -> grid rotates).
                                     --   Driven near-zero (bots as RELIABLE as possible): rotation now comes
                                     --   mainly from the HUMAN's own faults plus the rare unavoidable edge case.
                                     --   The miss MECHANIC is kept (under-jump -> floor fault) so difficulty can
                                     --   be re-added later by raising this. (Was 0.18; 0.25 ended rallies too fast.)
GridConfig.botContactBand = 3        -- studs around frameHeight that count as the bot's contact window (descending)

-- PHYSICAL bot hits (rework). Bots no longer artificially `bc:launch`; instead each bot that intercepts a
-- descending ball gets a real moving hit-sphere collider `{center, radius=hitZoneRadius, vel}` -- the SAME
-- shape the human carries -- which the server drives to an OFF-CENTER stand position relative to the ball
-- and then JUMPS up into the contact point. That collider is fed to `bc:step(dt, colliders)` alongside the
-- human's, so the existing swept, velocity-proportional collision (`strikeVelocity`) resolves the bot hit.
-- The aim emerges from the off-center contact: the bot stands on the FAR side of the ball from its aim cell
-- so `n = unit(ball - center)` points toward the aim; the jump velocity supplies the force.
GridConfig.botJumpVelocity = 12      -- upward speed (studs/s) the bot drives its hit-sphere into the ball at
                                     --   contact -> the velocity-proportional strike (hitGain) turns this into
                                     --   outgoing ball speed (paired with the off-center normal for the aim).
                                     --   60 sprayed every return out of bounds; 28 kept the strike inside the
                                     --   court (lands in/near the aim cell) so bot->C->bot rallies sustain while
                                     --   still clearing the pipe (a save). Higher = flatter/longer -> more OOB.
                                     --   NOTE: a brief +30% bump to 36.4 (mirroring the HUMAN jump boost) made the
                                     --   bot drive the ball nearly straight up at hitGain*36.4 ~= 91 studs/s -> it
                                     --   cleared the gym ceiling (H=50) on every hit. The +30% boost is human-only.
                                     --   Lowered 20 -> 16 for the in-bounds rework: the steeper in-bounds aim reflects
                                     --   the ball's fast descent more vertically, and a bot<->bot rally settles into a
                                     --   LIMIT CYCLE whose energy (peak height) is set by this drive + restitution. At
                                     --   20 that cycle peaked ~47.5 (ball top ~49.5, grazing the ceiling); 16 drops the
                                     --   cycle so the botLandPeakCap can hold the peak well under the ceiling while the
                                     --   strike still clears the pipe + sustains the rally.
                                     --   Lowered 16 -> 9 to bring the rally arc inside the DEFAULT CAMERA's view (the
                                     --   limit-cycle peak scales with this drive: jv20->peak~47.5, jv16->~41, ~1.6
                                     --   studs/unit; jv9 -> ~24 peak). BUT jv9 left the centre/King seat too weak to
                                     --   clear the ball OUTWARD over a pipe (it self-rallied straight up in C). Raised
                                     --   to 12 (peak ~30-31, ball top ~32-33 ~ the camera's ~32.75 centre top) so the
                                     --   King reliably clears to the outer ring while the typical arc still stays ~in
                                     --   view; the rare higher ball going beyond is acceptable (per design).
GridConfig.botOffCenterFrac = 0.50   -- 0..1: how far off-centre the bot stands, as a fraction of
                                     --   (hitZoneRadius + ballRadius). The stand centre is offset this far on
                                     --   the FAR side of the ball from the aim, so contact is clearly off-centre
                                     --   (steers the ball toward the aim) but the spheres still overlap to strike.
                                     --   This sets the line-of-centres TILT: SMALLER = steeper n (minLift biases
                                     --   it up) -> a tighter arc that lands IN the aim cell; LARGER = flatter n ->
                                     --   the hitMinPop(55) floor flings the ball horizontally -> OOB. Lowered from
                                     --   0.55 to keep returns in-bounds (the landing-prediction loop steepens further
                                     --   per-hit if a given contact would still sail out).
GridConfig.botMoveSpeed = 34         -- studs/s the bot slides its feet/collider laterally to the launch point
                                     --   during the descent (visible repositioning before the drive)
GridConfig.botStandoff = 1.6         -- studs the bot's drive STARTS behind its off-centre stand (further along
                                     --   -aimDir): the collider sweeps launchPoint -> contactPoint, so colVel
                                     --   carries this much horizontal travel toward the aim -> the strike's
                                     --   line of centres tilts toward the aim cell (not a vertical-only pop).
                                     --   Lower = steeper/shorter strike (lands nearer C); higher = flatter/longer.
                                     --   Lowered from 3.0: the long horizontal sweep drove the approach speed past
                                     --   strikeMoveThreshold and added flat hitGain power -> overshoot/OOB. 1.6 keeps
                                     --   enough lateral drive to steer toward the aim while landing inside the court.
GridConfig.botKingStandoffMult = 3.6 -- 0..N: MULTIPLIER applied to botStandoff ONLY for the CENTRE/King seat
                                     --   (cell == "C"). The King must drive the ball OUTWARD ~14 studs over a
                                     --   dividing pipe into an outer cell, whereas outer bots hit DOWNHILL into the
                                     --   big central target and clear easily. With the plain botStandoff(1.6) the
                                     --   King's drive against a near-vertical descending ball collapses to a vertical
                                     --   pop (n = unit(colVel) -> nearly straight up) -> the ball falls back into C
                                     --   and the bot SELF-RALLIES. A larger standoff sweeps the collider from further
                                     --   back/lower along -aimDir, so colVel (and thus the line-of-centres normal n)
                                     --   carries a strong HORIZONTAL component toward the aimed outer -> the strike
                                     --   actually clears the pipe and lands in the outer cell. The shared in-bounds /
                                     --   peak-cap forecast loop still trims any overshoot, so this only restores the
                                     --   King's outward reach. OUTER seats use the plain botStandoff (mult = 1) and
                                     --   their camera-height arc + accuracy are unchanged. Verified in Studio: at 3.6
                                     --   (paired with botKingStandoffFloorFrac) the King clears on EVERY swing (SAVE->C
                                     --   each time, longest 'defending C' run = 1) -- no self-rally; peak still ~24-30
                                     --   (under the ~32.75 camera top).
GridConfig.botKingStandoffFloorFrac = 0.7 -- 0..1: FLOOR on the King's STEEPENED standoff, as a fraction of its
                                     --   boosted base (botStandoff * botKingStandoffMult). The in-bounds OOB-steepen
                                     --   pass (BotController) shrinks standoff+offset to pull a long hit into the court,
                                     --   but for the King that could collapse the outward drive back to a vertical pop
                                     --   -> the ball falls into C and the bot SELF-RALLIES. Clamping the King's standoff
                                     --   to this fraction guarantees it ALWAYS keeps enough horizontal drive to carry
                                     --   over the pipe; in-bounds correction then rides on the OFFSET (which still
                                     --   steepens freely). 0 would re-allow the collapse; 1 would block in-bounds
                                     --   steepening entirely. OUTER seats use floor = 0 (unaffected).
GridConfig.botJumpLeadTime = 0.0     -- seconds to begin the jump EARLY before the predicted contact time, so the
                                     --   collider is rising THROUGH the ball at contact (0 = reach contact exactly)
GridConfig.botRestColliderY = 4.5    -- height (studs above the cell floor) of the bot's hit-sphere at rest /
                                     --   ground (its "head" height before the jump); the jump rises from here

-- Bot AIM / LANDING-PREDICTION (keep returns in-bounds). The bot aims at its target cell's CENTRE pulled
-- slightly toward the COURT centre (an in-bounds margin so a clean return has slack to the court edge), then
-- BallController-mirroring math predicts where the resolved strike's arc returns to the floor. If that landing
-- would be out of the court (or wouldn't clear the dividing pipe), the bot deterministically STEEPENS the
-- contact (shrinks the off-centre stand + standoff) and re-predicts, up to botLandPredictIters times -- trading
-- horizontal reach for a tighter arc that drops inside the aim cell. No Math.random: a fixed correction loop.
GridConfig.botAimJitterDeg = 12       -- +/- random yaw (degrees) applied to the bot's aim direction each swing so
                                     --   hits aren't robotically perfect: returns scatter naturally around the
                                     --   target (sometimes near a cell edge, occasionally nicking a neighbour). The
                                     --   in-bounds landing forecast still reins in any spill, so this adds life
                                     --   without spraying it OOB. 0 = perfectly precise; higher = wilder/looser.
GridConfig.botAimInsetFrac = 0.32    -- 0..1: pull the aim point this fraction of a half-square toward the COURT
                                     --   centre from the aim cell's centre, so the predicted landing sits a margin
                                     --   inside the court boundary (not on the far edge where a small error -> OOB)
GridConfig.botLandMarginFrac = 0.30  -- 0..1: in-bounds safety margin as a fraction of a half-square. The landing
                                     --   is "safe" only when |x|,|z| <= courtExtent - botLandMarginFrac*(squareSize/2),
                                     --   where courtExtent = 1.5*squareSize (the outer court edge). Bigger = more slack.
GridConfig.botLandPredictIters = 6   -- max correction passes per swing (peak-cap then in-bounds; see BotController)
GridConfig.botLandSteepenStep = 0.78 -- per pass, multiply the off-centre offset + standoff by this to STEEPEN
                                     --   (shorter, tighter arc); the loop DIVIDES standoff by it to FLATTEN
                                     --   (lower, longer arc) when the forecast peak would near the ceiling
GridConfig.botMinOffCenterFrac = 0.34 -- 0..1: FLOOR on the off-centre fraction the steepen pass may shrink to, so
                                     --   the contact keeps enough lateral tilt to steer toward the aim cell
GridConfig.botLandPeakCap = 32       -- studs: max ball-CENTRE peak height the forecast arc may reach before the
                                     --   loop flattens the strike. A CAMERA bound: at the zoomed-out court cam the
                                     --   visible top is ~32.75 at centre (dipping to ~27.5 over the far cells), so a
                                     --   ~40 peak (ball top ~42)
                                     --   sailed 25% above the screen. Cap 28 (ball top ~30) keeps the typical rally on
                                     --   screen; rare overshoots may still poke above the far-cell top -- acceptable.
                                     --   (The gym ceiling at ~49.5 is now far above; this cap is a CAMERA bound, not a
                                     --   ceiling bound.) Paired with the lower botJumpVelocity so the natural limit
                                     --   cycle already sits near here and the flatten loop only trims overshoot.

-- Lifelike bot idle motion (idle ready-stance + anticipatory ball tracking). Every bot that is NOT the
-- active receiver (no live swing) gets a cheap, deterministic "alive" motion centred on its home stand:
-- a continuous toe-bob + weight-sway, plus occasional short READY STEPS to a spot a stud or two from home
-- and back, plus a subtle LEAN/step toward the live ball's XZ so the whole grid reacts to the rally. All
-- phases are seeded from the bot's rank so they don't move in lockstep; clamped inside the cell so a bot
-- never drifts out of position for the next rally. Driven server-side on the existing Heartbeat step.
GridConfig.botIdleBobHeight = 0.35   -- studs: vertical toe-bob amplitude (continuous up/down weight shift)
GridConfig.botIdleBobSpeed = 3.2     -- rad/s: bob oscillation rate
GridConfig.botIdleSwayRadius = 0.55  -- studs: lateral weight-shift radius (a slow elliptical sway around home)
GridConfig.botIdleSwaySpeed = 1.4    -- rad/s: sway oscillation rate
GridConfig.botIdleStepInterval = 2.1 -- seconds between ready-step shuffles (a short move out from home + back)
GridConfig.botIdleStepDist = 1.8     -- studs: how far a ready step shuffles the feet from home before returning
GridConfig.botIdleStepDur = 0.55     -- seconds the out-and-back ready shuffle takes (the rest of the interval is home)
GridConfig.botIdleClampMargin = 2.2  -- studs kept clear of the cell edge: idle offset is clamped to
                                     --   (squareSize/2 - margin) so a bot never wanders over a pipe / out of its square
GridConfig.botTrackLeanFrac = 0.45   -- 0..1: fraction of the idle XZ budget biased toward the LIVE ball's XZ
                                     --   (anticipatory tracking) -- the grid leans into the rally without leaving home
GridConfig.botIdleLeanDeg = 7        -- degrees the torso leans toward the live ball while idling (subtle body face)

-- Save highlight (last-saved square). A "save" = a (non-serve, non-self-fault) contact that clears the
-- ball OUT of the hitter's square. On each save the overhead frame pipes of the struck square light up
-- and stay lit until the next save. The continuous Frame beams can't be lit per-cell, so MatchService
-- builds a separate non-colliding `SaveHighlight` overlay -- 4 glowing neon edge-segments outlining the
-- saved cell's border at frameHeight -- and repositions/shows it on each save. Visual only.
GridConfig.saveHighlightColor = Color3.fromRGB(64, 168, 104)  -- a soft, muted green (dimmed from a vivid 70,255,140) -- a hint, not a bright bar
GridConfig.saveHighlightTransparency = 0.55  -- partial transparency on the (Neon) overlay so it reads as a faint "last save" glow, not a glaring bar; 0 = solid, 1 = invisible
GridConfig.saveHighlightThickness = 0.9   -- edge-segment cross-section (a touch fatter than beamThickness so it reads as a glow over the pipe)
GridConfig.saveHighlightYOffset = 0.15    -- studs above frameHeight so the overlay sits just proud of the frame beams (no z-fight)

-- ── Seat nameplates (M5.6) ──────────────────────────────────────────────────────────────────────
-- A BillboardGui floats over each of the 9 seats showing WHO occupies it (a human's name or "Bot") so a
-- table of friends can tell themselves apart and read the rotation. The King's plate is gold + crowned.
-- The plates are server-built+driven (RotationService owns the occupancy model) under a fixed anchor per
-- cell, so they replicate to every client automatically and never depend on client trust. Cosmetic only:
-- the anchors are non-colliding, non-querying, invisible parts OUTSIDE the ball/player collision sets.
GridConfig.nameplateHeight = GridConfig.frameHeight + 3   -- studs above the cell floor the plate floats at (above the frame pipes)
GridConfig.nameplateSize = Vector2.new(7, 1.6)            -- BillboardGui size in studs (width, height)
GridConfig.nameplateKingColor = Color3.fromRGB(255, 210, 80)   -- King plate text/stroke gold (matches the RankHud KING colour)
GridConfig.nameplateHumanColor = Color3.fromRGB(120, 220, 255) -- a seated human's plate text (matches the rank pill cyan)
GridConfig.nameplateBotColor = Color3.fromRGB(190, 175, 230)   -- a bot's plate text (a muted violet -- clearly "not a person")
GridConfig.nameplateMaxDistance = 220                     -- studs the plate stays visible to (covers the gallery overlook)

function GridConfig.cellForRank(rank: number): string
	local cell = GridConfig.rankCells[rank]
	assert(cell, "no cell for rank " .. tostring(rank))
	return cell
end

-- Cell -> rank (reverse of cellForRank). Returns the rank whose square is `cell`, or nil if unknown.
-- M3 step 3 needs this to attribute a fault (the ball landed in cell X) to the occupant at that rank.
function GridConfig.rankForCell(cell: string): number?
	for rank, c in ipairs(GridConfig.rankCells) do
		if c == cell then return rank end
	end
	return nil
end

function GridConfig.cellCenter(cell: string): Vector3
	local c = GridConfig.cells[cell]
	assert(c, "unknown cell " .. tostring(cell))
	return GridConfig.origin + Vector3.new(c.dx * GridConfig.squareSize, 0, c.dz * GridConfig.squareSize)
end

function GridConfig.cellFramePoint(cell: string): Vector3
	return GridConfig.cellCenter(cell) + Vector3.new(0, GridConfig.frameHeight, 0)
end

-- Which cell is a world position under? Returns cell name or nil if outside the 3x3 court.
function GridConfig.cellAtPosition(pos: Vector3): string?
	local rel = pos - GridConfig.origin
	local function idx(v: number): number?
		local i = math.floor(v / GridConfig.squareSize + 0.5)
		if i < -1 or i > 1 then return nil end
		return i
	end
	local ix, iz = idx(rel.X), idx(rel.Z)
	if not ix or not iz then return nil end
	for name, c in pairs(GridConfig.cells) do
		if c.dx == ix and c.dz == iz then return name end
	end
	return nil
end

return GridConfig
