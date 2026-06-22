# STAX — changes from Jay's side that need to land in the Android build

Hey Michael's Claude — Jay's been iterating heavily over the last ~36 hours
on his Mac via TestFlight (iOS, Godot 4.6.3). Everything below is in the files
in this bundle. **You'll want all of it on Android too** — most changes are
pure GDScript and platform-neutral; flag any that look risky for Android.

Current TestFlight on iOS: **build 54** (version 4.4 (54)).

---

## Files changed (drop these straight in)

- `project.godot` — `config/icon` now points at `res://icon.svg.png` (we
  removed the old SVG; see below). `enabled=PackedStringArray(...)` still has
  the AdMob plugin enabled (iOS). Android should be unaffected.
- `export_presets.cfg` — iOS version bumped to 54. Android preset (`preset.1`)
  unchanged.
- `icon.svg.png` + `.import` — **new canonical STAX icon** (purple/neon
  candy lettering with stacked blocks, 1254×1254, no alpha). Replaces the
  old Godot placeholder.
- `scripts/Net.gd` — added `remove_friend(pid, code)` + `friend_removed`
  signal. Needed for the friends-list "remove" feature.
- `scripts/MainMenu.gd` — huge friend-system overhaul (see SQL section).
- `scripts/BlockSkins.gd` — new texture-cache system + Crystal v5 redesign.
- `scripts/Game.gd` — difficulty scaling rework, ad rescue bug fix, idle
  redraw optimization, power-revival fix.

## Files to DELETE from the repo

- `icon.svg`
- `icon.svg.import`

(They got replaced by the .png-based icon. The path change in `project.godot`
makes them dead weight.)

---

## What changed — feature by feature

### 1. New canonical app icon
Purple/neon STAX icon (file in bundle). Replaces old. `project.godot`
`config/icon` updated to point at the .png directly.

### 2. Friend system overhaul (REQUIRES SUPABASE SQL — see end of doc)
- **Mutual add**: when player A adds player B by code, both directions are
  inserted in `friendships`. Both sides immediately see each other.
- **Remove friends**: tapping a friend row in the leaderboard opens a small
  modal with **STATS / REMOVE FRIEND / CANCEL** buttons. Remove deletes both
  directions.
- **Levels shown inline**: leaderboard rows now display `NAME (12)` with the
  level in parens after the name (on BOTH global and friends tabs). Pulls
  from the `level` field that's already in the API.
- **Global rank pins on friends tab**: each friend's row shows their proper
  global rank pin (top-3 = gold/silver/bronze, etc.). The friends-board RPC
  was updated to return `global_rank` per friend.
- **Friend stats view**: in the modal, **STATS** swaps the content to show
  GLOBAL RANK / LEVEL / BEST SCORE / FRIEND CODE for that friend. **BACK**
  returns to the actions menu.

`Net.gd` adds `remove_friend(pid, code)` calling `remove_friend_by_code` RPC,
emitting `friend_removed`. `MainMenu.gd` wires up the modal + row tap handler
(replaced the old ✕ button — Jay didn't like the layout).

### 3. Difficulty scaling rework (`Game.gd`)
The old curve plateaued at score ~355k. Players reported high-score runs
"got easier" after 100k because nothing kept tightening. New design:

- **Below 100k**: completely untouched (the existing curve was already well
  tuned for the early/mid game).
- **100k → 500k**: NEW intense "mastery" ramp adds +0.18 hard_bias, +25
  drought sets, and pushes gift_chance floor down.
- **500k → 10M**: NEW gradual "ultra" ramp adds +0.06 hard_bias, +15 drought,
  more gift_chance squeeze.
- Hard bias cap raised 0.48 → 0.70.
- See `_difficulty()`, `_deep()`, `_mastery()`, `_ultra()`, `_hard_bias()`,
  `_wants_clear()`, and the slot-0 gift_chance computation in `Game.gd`.

Also: existing `DIFF_LEN`, `DIFF_SCORE_LEN`, `DEEP_LEN` were doubled in a
prior 2× easing pass (see the `(eased ×2: ...)` comments).

### 4. Ad-rescue soft-lock fix (`Game.gd`)
Bug: a player with a tall vertical piece in tray (e.g. 5-vertical) who ran
out of moves, watched a rewarded ad, and came back was sometimes still stuck
because the old `_help_player_continue` cleared 2 horizontal rows — leaving
no column tall enough for the 5-vertical.

Fix: in `_restore_state` after the ad-revive, loop clearing columns + rows
alternately until `grid.can_any_fit(...)` returns true. Hard fallback wipes
the top half of the board if even that doesn't help (effectively impossible
to hit, but guarantees no soft-lock). New helpers: `_clear_topmost_rows`,
`_clear_topmost_cols`.

### 5. Power-revival rule tightened (`Game.gd`)
Previously: ANY active power could rescue you from game-over by spawning
fresh pieces if the fired power didn't open enough space. Jay said this was
too generous — bombs should be a real risk.

Now: only the **ULT** (full meter, gravity power) guarantees survival. Bomb
and twin-bomb that don't open enough space cause game-over as expected.
Tracked via new `_last_power` field set in `_fire_power`, checked in
`_resolve_after_power`.

### 6. Battery / heat optimization (3 layers — most important section)

**A) Static-skin idle redraw skip** (`Game.gd`, `Grid.gd` already had similar):
When the current skin is NOT in `BlockSkins.ANIMATED` AND nothing else is
moving (no drag, no animation, no score countup), `_process` skips the idle
30fps redraw entirely. Static skins (PASTEL, NEON, BRICK, CANDY, HONEY,
STAINED, SYNTHWAVE, etc.) cost essentially zero CPU when board is at rest.
See the `elif BlockSkins.ANIMATED.has(_visual_idx())` branch.

**B) Menu faller throttle** (`MainMenu.gd`):
Faller layer was redrawing at 60fps. Throttled to 30fps via
`_faller_redraw_accum`. Visually identical (slow decorative motion), halves
the menu's per-second skin paint cost. Same for biome-gallery previews.

**C) Texture cache for static skin cells** (`BlockSkins.gd` — biggest change):
Added a static Dictionary cache + SubViewport-based async bake system.
First time a (style, color, seed_v mod 32, cell_size bucketed to 2px)
tuple is painted live, paint() kicks off a one-frame SubViewport that
renders the cell into an ImageTexture. From then on, every paint of that
key is a single `draw_texture_rect` instead of 5-10 geometry draws.

- Bypasses for: ANIMATED styles (they actually change), OVERLAY_STYLES
  (drips render in 2nd pass), squashed cells (rect ≠ pr), glow-pulsing
  cells (line-clear preview).
- Bake completion uses `RenderingServer.frame_post_draw` — critical detail.
  An earlier version used `process_frame` and captured before the SubViewport
  had rendered → translucent textures. Don't change this.
- Cache lives in class-static vars, persists across scenes.
- Memory cap ~13MB worst-case (32 styles × 7 colors × 32 seed variants × ~7KB
  per texture).

**Expected impact** (measured on Jay's iPhone 17e, build 54):
- Aurora (legendary animated): 21%/hr battery unplugged. Smooth at Fair
  AND Serious thermal pressure (Xcode Device Conditions simulation).
  Critical-state still laggy but that's an extreme corner case.
- Static skins: phone barely warms.

### 7. Crystal skin v5 (`BlockSkins.gd`)
Old crystal (v4) was an octagonal "emerald cut" — Jay didn't like it. Fully
rewrote as v5: brilliant-cut diamond with 4 inset facets meeting at an
apex below center, vertical gradient (dark→light, "light through gem"),
classic specular slash on the top-left facet, **two drifting + pulsing
sparkles** inside the gem. Joined `ANIMATED` list (was static before).

If Jay asks for crystal tweaks ("more sparkly", "less colourful", etc.),
the func is `_crystal` in BlockSkins.gd, fully self-contained.

---

## SQL (already run on Jay's Supabase — DO ON YOURS TOO if your DB is separate)

Three changes to functions, run all in SQL Editor → New query:

```sql
-- 1. Mutual add — insert both directions
create or replace function public.add_friend_by_code(p_id uuid, p_code text)
returns text language plpgsql security definer set search_path = public as $$
declare fid uuid; fname text;
begin
  select id, name into fid, fname from players where friend_code = upper(p_code);
  if fid is null or fid = p_id then return null; end if;
  insert into friendships (player_id, friend_id) values (p_id, fid) on conflict do nothing;
  insert into friendships (player_id, friend_id) values (fid, p_id) on conflict do nothing;
  return fname;
end; $$;

-- 2. NEW: remove friend (deletes BOTH directions)
create or replace function public.remove_friend_by_code(p_id uuid, p_code text)
returns boolean language plpgsql security definer set search_path = public as $$
declare fid uuid;
begin
  select id into fid from players where friend_code = upper(p_code);
  if fid is null then return false; end if;
  delete from friendships
    where (player_id = p_id and friend_id = fid)
       or (player_id = fid and friend_id = p_id);
  return true;
end; $$;
grant execute on function public.remove_friend_by_code(uuid,text) to anon;

-- 3. get_friends_board — DROP first because return columns changed (added friend_code + global_rank)
drop function if exists public.get_friends_board(uuid);
create function public.get_friends_board(p_id uuid)
returns table(rank int, name text, best_score int, level int, is_me boolean,
              friend_code text, global_rank int)
language sql security definer set search_path = public as $$
  with f as (
    select friend_id as id from friendships where player_id = p_id
    union select p_id
  ),
  gr as (
    select id, (row_number() over (order by best_score desc, updated_at asc))::int as g
    from players where best_score > 0
  )
  select (row_number() over (order by p.best_score desc, p.updated_at asc))::int,
         p.name, p.best_score, p.level, (p.id = p_id), p.friend_code,
         coalesce(gr.g, 0)
  from players p
  join f on f.id = p.id
  left join gr on gr.id = p.id
  order by p.best_score desc, p.updated_at asc;
$$;
grant execute on function public.get_friends_board(uuid) to anon;

-- 4. One-shot backfill: mirror rows for any pre-mutual-change one-way friendships
insert into friendships (player_id, friend_id)
select friend_id, player_id from friendships on conflict do nothing;
```

If you share the same Supabase project (`dftjbfjgyzpfznsfezpa`), Jay already
ran this — skip. If Android uses a separate project, run there.

---

## Things deliberately NOT touched

- Android export preset (preset.1 in `export_presets.cfg`) — untouched
- `scripts/Auth.gd`, `scripts/GameState.gd`, `scripts/Sfx.gd`, `scripts/Ads.gd`
  — no changes
- All other skin renderers — unchanged
- Crash-safe save logic — DON'T REORDER FIELDS rule respected

---

## Build versioning

Jay's iOS build is at 54. If you bump Android, pick whatever Android sequence
you've been using — they're independent (Apple and Google track them
separately).

— Claude (Jay's side, 2026-06-22)
