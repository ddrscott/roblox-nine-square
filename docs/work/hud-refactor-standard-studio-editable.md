# HUD refactor — standard Roblox GUI, Studio-editable, responsive, component-based

## Why
The HUD was built the quick way: each element hand-created in code (`Instance.new`) with FIXED PIXEL
offsets + manual AnchorPoint/Position across RankHud / NineSquareClient / Movement, no layout containers,
no scale. That's why it's been whack-a-mole — overlaps, things looking like buttons, no mobile scaling, the
bad corner. Scott wants it re-architected the STANDARD way AND **Studio-editable**.

## Target architecture (standard Roblox GUI)
1. **Author the HUD as saved instances in `StarterGui`** (a `ScreenGui` named e.g. `NineSquareHUD` with named
   component Frames), designed/laid out with real layout objects — so it's editable in the **Studio GUI
   editor** and PERSISTS. Build-ONCE / self-heal (like the world build): the instances live in the saved
   place; a script only CREATES a default tree if it's MISSING (fresh place), and otherwise LEAVES it alone
   so Studio tweaks persist. StarterGui clones to each player's `PlayerGui` on spawn (standard).
2. **Resolution-independent + responsive:** size/position with **Scale-based `UDim2`** and a top-level
   **`UIScale`** (and/or `UIAspectRatioConstraint`) driven by viewport, so ONE layout scales across phones +
   desktop — replace the per-device fixed-pixel swaps / `isMobile()` size hacks. (Keep showing/hiding the
   right pieces per state, but sizing comes from scale, not hardcoded px.)
3. **Layout containers, not manual offsets:** anchor each cluster to a screen CORNER and use
   `UIListLayout`/`UIGridLayout` + `UIPadding` to arrange contents (they reflow + never overlap):
   - top-RIGHT cluster: stamina bar, scoreboard (Turns + TAK), the lobby buttons (Join / small Spectate),
     the Spectating status — stacked via a UIListLayout so they never collide.
   - top-LEFT: the transient toast feed + KING chip.
4. **Reusable component/style system** off `GridConfig.uiStyle`: small builders `makeButton(...)` (tappable:
   solid fill, AutoButtonColor, button font) and `makeLabel(...)` (static: flat/subtle bg, label font) so a
   button always reads as a button and a label always as a label — consistently, everywhere.

## Migrate the existing HUD into the new system (and fix the outstanding issues)
Move ALL current HUD into the StarterGui-authored, layout-driven, scale-based system, binding data from the
client scripts (set text/fill/visibility) instead of creating layout:
- **Scoreboard:** Turns + TAK (labels). **Stamina bar:** with a READABLE caption (good contrast, or drop the
  word) — fixes the unreadable "STAMINA". **Join Game:** a button, **less bold** (medium weight, calmer).
  **Spectate (leave):** a small, low-key button. **Spectating status:** a clear LABEL (not a button).
  **Toast feed:** transient/see-through, small, top-left. **KING chip:** label, only while King.
- These fold in the superseded "corner polish" task (readable stamina / less-bold Join / Spectating-as-label)
  + the mobile-responsive scaling — all handled by the new layout+scale+component system.

## Client refactor
- `RankHud` / `NineSquareClient` (lobby+scoreboard+camera UI) / `Movement` (stamina) STOP `Instance.new`-ing
  HUD layout. Instead they `WaitForChild` the authored `PlayerGui.NineSquareHUD` components by name and only
  BIND state to them (text, bar fill, Visible, button.Activated → JoinRequest/LeaveRequest). If the authored
  HUD is absent (fresh place), a self-heal builder creates the default tree (so a clean place still works).
- No behaviour change: same data, same remotes (JoinRequest/LeaveRequest), same events — only the GUI
  construction + layout change.

## Acceptance criteria
- The HUD is **responsive** — one layout scales cleanly across desktop AND phone aspects (no fixed-pixel
  per-device hacks); nothing overlaps; clusters reflow via layout containers. Verified via `screen_capture`
  desktop + phone, seated + lobby.
- **Consistent components:** every button reads as a tappable button; every status/stat reads as a static
  label; the corner is clean and legible (stamina readable, Join not over-bold, Spectating a label).
- The HUD is **authored in StarterGui** (editable in the Studio GUI editor) and **persists** (build-once /
  self-heal — Studio tweaks aren't clobbered; a fresh place self-builds a default). Confirm the instances
  live under StarterGui and survive a Play→Edit cycle.
- Behaviour unchanged — Join/Spectate/queue/Spectating, scoreboard values (Turns/TAK), stamina fill, toasts,
  KING chip all still work via the bound data. Gameplay/cameras/seating untouched. Studio left in Edit.

## Relevant files
- NEW: the `StarterGui.NineSquareHUD` instance tree (authored via the MCP in Edit so it persists) — or a
  build-once `HUD` module that self-heals it.
- `src/client/RankHud.client.luau`, `src/client/NineSquareClient.client.luau`, `src/client/Movement.client.luau`
  — refactor to BIND to the authored components (find-or-self-heal), not build layout.
- `src/shared/GridConfig.luau` — `uiStyle` (formalize button/label component styles); drop now-dead
  fixed-pixel HUD tunables; any scale tunables.
- README — document the HUD architecture (StarterGui-authored, layout/scale/components, build-once-editable).
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; author the StarterGui
  tree in Edit so it persists; client UI runs on the Client datamodel in Play; standalone `require` STALE —
  verify via `script_read`/`get_console_output` + `screen_capture` desktop + phone, seated + lobby; confirm
  StarterGui contains the HUD + it survives Play→Edit. Leave Studio in Edit.)

## Constraints
- GUI architecture/presentation only — don't change gameplay, stat tracking, the lobby/seat/queue logic,
  cameras, the world, or the remotes. Standard Roblox layout (UIListLayout/UIPadding/Scale/UIScale/
  UIAspectRatioConstraint) + a reusable component system; NO fixed-pixel-per-device hacks. Build-once /
  self-heal so the StarterGui HUD is Studio-editable + persists (don't clobber manual GUI tweaks). Keep all
  current HUD function + data bindings working.
