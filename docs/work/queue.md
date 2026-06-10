# Work Queue

- [-] Tune movement: dash 2× distance (GridConfig.dashSpeed 20→40) + halve double-jump height (flipUpVelocity 75→~38)
- [x] Reset players to the serve spot when the ball re-serves — see [reset-players-on-serve.md](reset-players-on-serve.md)
- [x] Add legs at the 4 grid corners (frame stands on something) — see [frame-legs.md](frame-legs.md)
- [x] Rework player contact as a proper moving-sphere collision (fix clip/pull-down bug) — see [player-collision-rework.md](player-collision-rework.md)
- [x] Fade walls that obstruct the camera (camera occlusion) — see [camera-wall-fade.md](camera-wall-fade.md)
- [x] Fix still-player bounce: a motionless player must not add ball energy — see [still-player-bounce.md](still-player-bounce.md)
- [x] Shrink + raise the player contact sphere to cover the upper body — see [contact-sphere-upper-body.md](contact-sphere-upper-body.md)
- [x] Fix dash: swap reversed left/right + cut distance to ~1/4 — see [dash-fix.md](dash-fix.md)
- [x] Double-tap dash + double-jump flip (stamina-gated, feeds the strike) — see [dash-double-jump-flip.md](dash-double-jump-flip.md)
