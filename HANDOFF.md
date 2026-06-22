# STAX — Handoff from Jay's side (2026-06-22)

> **Michael's Claude — read this before merging.** This batch was done on Jay's Mac
> (canonical project at `~/Downloads/stax-game-main-2`, NOT a git clone — Jay
> downloads zips). It was NOT pushed to `origin/main`; Jay asked me to leave the
> changes locally so you can review + integrate them on your side. Uploaded as
> **TestFlight build 4.4 (102)**, currently being tested by Jay on iPhone + iPad.

## Why this handoff exists
Jay flagged several iPad / launch-prep issues over a long session: name-prompt
re-appearing for new players, iPad UI off-centre, ads not appearing on iPad,
some skins shifting the board left, candy + bricks skins feeling off. I tackled
all of them plus the launch-readiness backlog items he greenlit. Details below.

## ⚠️ Three fixes added at the very end of the session (post the main batch below)
- **DEV_TOOLS removed**: `MainMenu.gd` no longer carries `const DEV_TOOLS := true`
  or the "UNLOCK ALL (DEV)" settings button. My local zip-extract still had it
  from an older snapshot; main already removed it. Don't re-add. `GameState.gd`'s
  `dev_unlock_all()` is also still present in my copy — remove if your `main`
  doesn't have it (it's harmless if no caller exists, but cleaner gone).
- **Menu-lock-after-update bug**: `MainMenu._on_auth_signed_in` only refreshed
  the LEADERBOARD / BIOMES lock badges when the ACCOUNT panel was open. Silent
  boot-resume (the normal case for a signed-in player after a TestFlight update)
  silently bumped `player_xp` from cloud but never rebuilt buttons, so a
  level-22 tester saw both gated buttons until they entered a run + came back.
  Fix: refresh unconditionally when `restored=true`, defer through the
  close-tween if the panel happens to be open.
- **Panel-wide drag-scrolling**: leaderboard / achievements / biomes were
  previously only scrollable by dragging the actual rows. Promoted each panel's
  `ScrollContainer` to a member var and connected a `gui_input` handler on the
  panel itself (`_attach_drag_scroll(panel, scroll)`) that forwards drag deltas
  to `scroll_vertical`. Bare button taps still work because buttons capture
  input first.

## ⚠️ Ad-serving regression we found at the very end of the session
Jay reported ads broken on BOTH iPhone and iPad after the iPad UI overhaul
batch. Root cause **was not the UI changes** — it was that
`export_presets.cfg` had `plugins/AdMob=false` and `project.godot`'s
`[editor_plugins] enabled=PackedStringArray()` was empty. With both flags
off, the iOS export silently builds the app without the Poing AdMob plugin
binaries — `RewardedAdLoader.new()` then fails at runtime and `_impl.is_rewarded_ready()`
always returns false, so the WATCH AD button only ever showed "AD LOADING…"
then timed out. Fixed in this batch:
- `export_presets.cfg`: `plugins/AdMob=true`
- `project.godot`: `enabled=PackedStringArray("res://addons/admob/plugin.cfg")`

**Don't let either of these get cleared again** — opening the project in a
Godot editor that doesn't have the plugin "enabled" via the editor UI will
silently rewrite both back to off. The original HANDOFF.md below already
warned about this; we hit it again. Worth a CI check before any iOS build.

## Files changed (sanity-check these against `main` before merging)
- `scripts/GameState.gd`
- `scripts/Game.gd`
- `scripts/GameOver.gd`
- `scripts/MainMenu.gd`
- `scripts/Tutorial.gd`
- `scripts/BlockSkins.gd`
- `project.godot` (stretch/aspect=expand)
- `export_presets.cfg` (build number 102)
- `ios/PrivacyInfo.xcprivacy` (new)
- `~/Desktop/stax-build/patch_xcodeproj.py` (lives on Jay's build Mac, not in repo)
- `~/Desktop/stax-build/build_ios.sh` (REPO default path fix, also off-repo)

## What changed and why

### 1. iPad UI centring (this took multiple iterations — the final shape is non-obvious)
The viewport now uses `stretch/aspect=expand` so iPad's wider canvas isn't
black-barred. Each scene's script computes `x_off = (viewport_w - 414)/2`. Then:

- **`Game.tscn` + `GameOver.tscn` UI labels are anchor-centred (anchors_preset 8)**.
  These self-centre on iPad without any code shift. **Do NOT set `ui.offset.x =
  x_off` on those CanvasLayers** — doing so was my first attempt (build 100) and
  it double-shifted the anchored Labels off to the right by ~129 px. Jay's
  iPad reported the WATCH AD button as "not there" because it was pushed
  off-centre and felt missing.
- **`MainMenu.tscn`'s UI CanvasLayer is empty in the scene** (all UI is built
  procedurally at 414-frame coords). It DOES use `ui.offset.x = x_off`; the
  PRESET_FULL_RECT dim overlays inside it now set `offset_left/right = -x_off`
  so the dim still reaches the iPad's side strips.
- **Procedural panels added in Game.gd / GameOver.gd code** carry `x_off` in
  their own `position.x` because they live next to the anchored Labels.
- **`Game.gd._draw` uses a cached `_bg_origin = Vector2(x_off, 0) + shake_offset`**
  and every `draw_set_transform(...)` inside `_draw_bg_pattern` is rewritten to
  add `_bg_origin` (positioned transforms) or restore to `_bg_origin` (resets).
  The old code reset to `Vector2.ZERO`, which wiped out our base shift mid-frame
  — that's why FROST / MEADOW / BLOSSOM / etc. had the board shifted left while
  static skins like PASTEL looked fine. Don't reintroduce `Vector2.ZERO` resets
  inside `_draw_bg_pattern`.
- **Grid Node2D** is shifted via `grid.position = Vector2(GRID_X + x_off, GRID_Y)`
  in both `_ready` and `_process`. `drag_layer` / `fx_layer` also positioned at
  `x_off`. Inputs: every `event.position` in `_input` has `Vector2(x_off, 0)`
  subtracted before going to `_start_drag` etc, so hit-test stays in 414-frame.
- **`Tutorial.gd`** keeps the veil at full-rect so taps register, but its draw
  overlay applies `veil.draw_set_transform(Vector2(x_off, 0))` before drawing
  rings/pointer/bubble/cubie; its bubble_label + tap_label positions add `x_off`.

### 2. WATCH AD button visibility (Jay's "ads not working on iPad" report)
`GameOver._ready` used to call `_hide_ad_button()` the moment
`Ads.can_offer_rewarded()` returned false — which is the case while the
rewarded ad is still preloading. iPad fill rates are slower than iPhone, so
the button often vanished before AdMob had a chance to fill. Now the button
stays visible in a disabled "AD LOADING…" state, polls every 1s, and gives
up after 15s (then hides). See `_set_ad_button_state(offer_text)`.

### 3. Ad-revive reward
`_restore_state` in `continue_mode == "ad"` now calls `_spawn_pieces()` to
deal a fresh randomised 3-tray on top of the gifted cleared rows. Resume
(non-ad) still restores the saved set.

### 4. Save-bug fix + dead-code removal in GameState.gd
- **Brand-new install bug** was: `save_epoch = 0` default → first `_save()` writes
  epoch 0 → next `_load` sees `0 < RESET_EPOCH(2)` → wipes everything → player
  re-asked for name on second launch. The legacy wipe path was meant for
  pre-rework saves only.
- **Fix:** removed the `if best_code == 1 and save_epoch < RESET_EPOCH:
  _reset_progress()` block from `_load()` entirely. Set `save_epoch` default to
  `RESET_EPOCH` and left the field in the save tail (append-only invariant
  unchanged). Field is now vestigial; clean up post-launch.
- **Appended `apple_hint_state` + `apple_hint_games` to the save tail** for the
  new Apple sign-in nudge (index 31 and 32). Followed the append-only rule.

### 5. Apple sign-in nudge (iOS only)
Mirror of the review prompt: gated on `games_played >= 3`, snoozable to +5
games, dismissed on actual sign-in or "Don't show again". **Explicitly
suppressed when `should_ask_review()` would fire this session** — never both
in one menu open. Title: "BACK UP YOUR PROGRESS". `_on_auth_signed_in` calls
`GameState.finish_apple_hint()` so a successful sign-in silences it.

### 6. Privacy manifest
- New: `ios/PrivacyInfo.xcprivacy` with NSPrivacyAccessedAPITypes (FileTimestamp,
  SystemBootTime, DiskSpace, **UserDefaults — Godot writes user:// and AdMob
  caches consent**), NSPrivacyTracking = **true** (AdMob's tracking when ATT
  granted means our combined app tracks), NSPrivacyCollectedDataTypes for the
  Supabase user_id + leaderboard score upload. NSPrivacyTrackingDomains stays
  empty — AdMob's bundled manifest lists its own.
- `patch_xcodeproj.py` gained step 11: copies `repo/ios/PrivacyInfo.xcprivacy`
  over Godot's auto-generated stub in `out_dir/`. **This script lives on Jay's
  build Mac at `~/Desktop/stax-build/patch_xcodeproj.py`** — if your build
  machine has its own copy of the patcher, replicate the step or builds won't
  pick up the manifest.

### 7. Skin perf / vibrancy
- **BRICKS**: per-brick specks `draw_circle` → `draw_rect` (sub-pixel circles
  were expanding into 32-vertex triangle fans, ~900 calls/frame at full
  board). Cut specks per brick from 2 → 1. Cracks simplified from 2-segment
  to 1-line. Moss tufts also rect not circle.
- **NEON**: 3 nested halo `rr_fill`s (each grown +5%/+9%/+18% beyond the
  cell) collapsed to a single combined halo. Big fillrate / overdraw win at
  64 cells per board.
- **HONEY**: per-hex `clip_poly_to_rect` skipped when all 6 vertices are
  already inside the cell (common at the coarsened hex size).
- **CANDY**: stripes used to be lerped 35% toward red regardless of piece
  colour, which muddied non-red pieces. Now uses the piece's own colour with
  a small saturation deepen; white base is faintly tinted with the piece
  colour so it doesn't read as bland. Jay said candy "felt less vibrant" —
  this should help.

### 8. project.godot
`window/stretch/aspect="expand"`. This is what un-letterboxes the iPad. Don't
revert without also reverting all the per-script x_off plumbing.

## Known issues / decisions Jay deferred
- DEV_TOOLS = true still. Jay says the dev unlock button visually appears but
  doesn't fire anything in his current build anyway. Either way, flip false
  before public 1.0.
- Android ad unit IDs in `scripts/AdsAdmob.gd:12-16` still Google TEST. Jay
  said this is already replaced on your branch; I left this file alone here
  to avoid clobbering. Merge yours.
- Google sign-in still failing per the earlier CLAUDE.md note — Jay was about
  to retest separately.
- Supabase auth dialog shows the raw `dftjbfjgyzpfznsfezpa.supabase.co` host
  (Jay says "looks dodge"). He'll set up a custom domain on Supabase Pro
  himself and update `Net.SUPABASE_URL`.
- iCloud KV sync, account-restore "Welcome back" panel, localisation,
  per-biome ambient music, proper iOS plugin (instead of patch_xcodeproj.py),
  Apple client-secret JWT regen (Dec 2026) — all noted as "after 1.0" in:
  `~/.claude/projects/-Users-glow/memory/project_stax_1_0_backlog.md`
  on Jay's Mac. Recreate the equivalent on your side if useful.

## How to verify after merging
1. Open in Godot 4.6.3 (NOT 4.7 for iOS — AdMob plugin ABI mismatch).
2. Run `~/Desktop/stax-build/build_ios.sh archive` equivalent on your end.
3. Apply the patcher with the new step 11 (or replicate it).
4. Upload via altool — Jay's been on builds 100/101/102; next yours should
   be ≥ 103 unless coordinated.
5. Spot-check on iPad portrait: board centred, score numerals centred above
   the board, WATCH AD shows "AD LOADING…" briefly then the offer text,
   pause-menu panel centred, FROST + MEADOW + BLOSSOM skins keep the board
   centred (these were the regressions).

---

# STAX — Handoff for the next session (2026-06-20)

Hey future Claude. Jay (CEO, the user) and I did a big multi-session run. Everything below is
**pushed to `origin/main`** (`github.com/XSideZ/stax-game`, HEAD `1eb6fb4`). You CAN `git push origin
main` from this clone. Jay's friend builds the **iOS** app from `main` (now a **Godot 4.7** project).

## ⚠️ Read this first
- **You CANNOT test on PC the way it matters.** The account/restore flow needs the iOS OAuth round-trip;
  the skins and battery/perf only show on the phone (esp. the 120 Hz iPhone 16 Pro). So skin/feel work
  is **blind iteration**: make tasteful changes → Jay builds & tests → he reports → you adjust.
- **Don't run Godot headless to "verify"** unless you really need to — the project is on 4.7 and churning
  `.godot`/`project.godot` under a mismatched local engine has burned us. The edits are simple GDScript;
  eyeball them instead.
- **Load-bearing (don't break):** never reorder fields in `GameState._save`/`_read_save_fields` (append
  only); keep the crash-safe save (atomic temp+rename, `.bak`, never wipe on short read); center banners
  go through the queue (don't call `_spawn_*` directly).

## 🎨 THE 4 SKINS — this is the active task Jay wants continued
All skin renderers live in **`scripts/BlockSkins.gd`** as `static func _name(...)`, dispatched by style
index in `paint()`. The biome/skin list and names live in 3 other files (see "renaming a skin" below).

**Why these 4 were a problem:** the originals did **dozens of `clip_poly_to_rect` calls per cell** to
paint continuous patterns across the board → big framerate drops (Jay's complaint). I rewrote them.

**THE PERFORMANCE RULE (do not violate):** cheap renderers only — a gradient (`rr_grad`) + a small
number of **in-bounds** primitives (`ci.draw_circle`, `ci.draw_line`, `ci.draw_polyline`,
`draw_poly_safe(ci, pts, col, true)` for convex polys). **NO `clip_poly_to_rect`. NO per-cell loops over
board space.** The gold-standard cheap template is **`_synthwave`** (style 27) — study it.

Helpers: `rr_fill(ci,rect,rad,col)`, `rr_grad(ci,rect,rad,top,bot)`, `rr_outline(ci,rect,rad,col,w)`,
`draw_poly_safe(ci,pts,col,assume_convex)`. Each skin maps the piece `col` to its palette so pieces stay
tellable apart.

**Current state of the 4 (after "skin pass 2", commit `1eb6fb4`):**
| Style | Name   | Func       | Anim? | What it draws now |
|-------|--------|------------|-------|-------------------|
| 12    | HONEY  | `_honey`   | static | gradient + full 7-cell honeycomb + honey pool + sheen + bubbles |
| 20    | AURORA | `_aurora`  | **animated** | night gradient + 3 wavy curtain bands (polylines, ripple/drift/hue-shift) + twinkling stars |
| 22    | OPAL   | `_opal`    | **animated** | NEW skin (replaced MARBLE) — milky base + drifting iridescent colour flecks + breathing glow + sparkles |
| 26    | STAINED| `_stained` | static | 5-pane leaded window (centre diamond + 4 corner panes, varied hues, lead came + bevels) |

The **`ANIMATED`** const (top of BlockSkins.gd, ~line 15) lists styles that force per-frame redraws.
honey(12)+stained(26) are NOT in it (static); aurora(20)+opal(22) ARE (cheap legendary shimmer).
**Jay said aurora & opal are "legendary" tier → they should stay animated.** sakura(16)/autumn(28) were
already fine — don't touch them.

**Jay's latest feedback (the to-do):** he picked **Opal** to replace marble. He'll test pass-2 and tell
you what's still off (e.g. "opal more/less colourful", "aurora bands bigger/wavier", "honey/stained still
missing something"). Iterate on the LOOK while keeping the performance rule.

**Renaming a skin touches 4 places** (I did marble→opal across all of them — follow this if renaming):
1. `BlockSkins.gd` — the `_name` renderer + the `NN: _name(...)` dispatch line in `paint()`.
2. `MainMenu.gd` — `SKIN_NAMES` array (~line 44).
3. `GameState.gd` — the `THEMES` biome entry (~line 521): `{bg, orb, accent, name}`.
4. `Game.gd` — `_draw_bg_pattern()` match, the `NN:` case (the board background for that biome).

## ✅ Everything else done across these sessions (all on `main`)
- **Branding/logo:** new STAX logo = chunky 3D candy lettering. App icon = stacked **ST/AX on a neon-glow
  bg**; full iOS PNG set + sources at `C:\Users\johal\Desktop\STAX-logo-concepts\` (generator `_gen.py`,
  rasterised via headless Chrome). In-game **falling menu letters restyled** to match (`MainMenu._build_logo`
  + `LOGO_COLORS`). Pick still pending for final iOS-icon swap on Jay's side.
- **Account / restore UX:** returning players no longer re-prompted for a name (`MainMenu._ready` guard);
  restore brings back the real account name (`GameState.apply_cloud_profile(d, restoring)`); leaderboard/
  biomes **lock state refreshes after a restore** (`_refresh_menu_buttons`); **overlay panels always raise
  to front on open** (`ui.move_child(box,-1)` in every `_open_*`) — fixed "menus open behind the buttons".
- **Difficulty:** cranked hard (`4314056`) then **eased one notch** (`cd8eb86`). Knobs are named consts in
  `Game.gd` + `_hard_bias()`/`_pick_adversarial_shape()`. **Jay is still dialing it in** — he may ask for
  another small ease ("a tiny bit more") or say it's perfect.
- **Perf/battery:** `Engine.max_fps = 60` (GameState._ready) + `application/run/max_fps=60` — the iPhone 16
  Pro was rendering at 120 Hz. Plus the skin-lag fix above. If still hot, next lever = throttle the menu's
  `queue_redraw`/`faller_layer.queue_redraw` to ~30fps.
- **Leaderboard:** shows **top 1000** now (client `fetch_global(1000)` + the `get_global_board` RPC cap
  raised 200→1000 — **Jay already ran the SQL** in Supabase).
- **Menu freeze on spam-tap:** re-entry guards `_launching` / `_confirm_open` in MainMenu (launch + new-game
  confirm + the name-prompt LET'S GO).
- **Double bomb:** now spends the WHOLE meter; the two bombs land **≥3 cells apart** (`_far_target`).
- **`project.godot`:** moved to **Godot 4.7** (`config/features`) — friend updating to 4.7.

## How Jay likes to work (from memory)
- Just build it; don't present a wall of options. Push after a fix lands (he tests on phone). Give SQL as
  clean copy-paste blocks (he runs SQL/deploys himself). Don't ask "want me to ship?". Proactively ask him
  to run device probes you can't do yourself. He has a proven short-form viral skill — launches are organic.

Good luck. Pick up the skins. — Claude (2026-06-20)
