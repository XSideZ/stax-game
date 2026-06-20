# STAX — Handoff for the next session (end of 2026-06-20)

Hey future Claude. Big multi-task day with Jay (CEO/user). **Everything below is pushed to
`origin/main`** (`github.com/XSideZ/stax-game`, you CAN `git push origin main`). **HEAD = `30e73ab`.**
Project is **Godot 4.7**. Jay's friend builds **iOS** from `main` on a Mac; Jay tests on an iPhone
16 Pro (120Hz). **Build number is now 43** (`export_presets.cfg`).

## ⚠️ Read first
- **You can't meaningfully test on PC.** Skins/perf/feel only show on the phone, account/restore needs
  the iOS OAuth round-trip. Work is **blind iteration**: change → Jay builds on Mac → tests → reports → adjust.
- **Don't churn `project.godot` / `.godot`** under a mismatched local Godot (opening Godot or pressing F5
  re-saves `project.godot` with a harmless line reorder — `git restore` it, don't commit it).
- **Load-bearing (don't break):** append-only save field order (`GameState._save`/`_read_save_fields`);
  crash-safe save (atomic + `.bak` + no-wipe-on-short-read); center banners go through the queue.
- **Jay's style:** just build it, don't present options; push after a fix lands; give SQL as clean
  copy-paste blocks (he runs SQL/deploys himself); proactively ask him to run device probes.

## ⏳ AWAITING JAY'S ON-DEVICE VERIFICATION (the next-session to-do)
Jay is pushing a **TestFlight build (43)** of everything below. When he reports back, iterate on:
1. **Skins** (aurora/opal/stained) — do they look right AND hold 60fps? (honey already confirmed fixed.)
2. **Difficulty** — does ease #3 finally feel right? He's been chasing "perfect"; expect another nudge.
3. **Leaderboard/friends scroll** — drag-anywhere now works?
4. **Stained** — may look a touch flat now (see below); he may want the leaded detail back.
5. Confirms: dev button gone, still level 100, 60fps everywhere feels smooth.

## What shipped today (all on `main`)

### 1. Skins — restored the continuous "parallax" look (the headline work)
Jay missed the old skins where the pattern flowed unbroken block-to-block; the cheap rewrite (`d6880d4`)
had gutted them into per-block skins. **Key finding: the lag was NEVER the clipping** — sakura(16)/
autumn(28)/gold(17)/prism(25) are all continuous `clip_poly_to_rect` patterns that run fine. The lag came
from **unbounded per-cell lattice loops** (old honey ~12-16 clipped hexes/cell, old stained ~12+ diamonds×2).
**The recipe (reuse it):** continuous canvas-space pattern in `pr`-space + `delta` (drag-preview match),
each element a clipped poly, **BOUNDED to ~3-9 cheap low-vert clips/cell** (= sakura/gold budget).
All in `scripts/BlockSkins.gd`:
- **HONEY (12, static):** continuous hex comb, `hs = ps*0.42` (~3-5 hexes/cell). `@25a5d8f`. **Jay confirmed
  the lag is FIXED on phone.**
- **AURORA (20, animated):** continuous wavy curtains, 10-vert ribbon, 2 passes, **per-band cull** (skip
  bands that can't reach the cell before clipping — the old 3-pass 14-vert ribbon ~15×/cell was the killer).
- **OPAL (22, animated):** play-of-colour now drifts ACROSS blocks (hue = f(canvas pos, time), like prism).
- **STAINED (26, static):** continuous big-pane cathedral lattice, `g = ps*0.62`, ONE jewel fill per pane.
  Aurora/opal/stained all `@d69bff3`.
- **STAINED highlight fix `@b443745`:** the lead-came bevel line + glint were drawn unclipped (guarded only
  on the diamond CENTRE), so on panes bigger than a cell the highlight lines spilled outside the block. Now
  guarded on BOTH endpoints inside / whole circle fits. **KNOWN SIDE-EFFECT:** the bevel now rarely shows
  (panes > cell), so stained may look flatter. If Jay wants the leaded detail back, add a **clip-safe**
  highlight (draw along the already-clipped pane outline, not the raw diamond edges).
- Original heavy versions saved at **`C:\Users\johal\old_blockskins.gd`** (from `70ef376`) — DELETE once Jay
  accepts the rebuilds.

### 2. Difficulty — eased TWICE (still dialing to "perfect")
Levers are named consts + `_hard_bias()`/`_pick_adversarial_shape()` in `scripts/Game.gd`.
- **Ease #2 `@631e26f`:** small even step.
- **Ease #3 `@7a5fe8c`** (Jay: still too hard, "cut it all quite a bit" — big broad cut): `_hard_bias`
  0.47/0.18→**0.34/0.12, cap 0.65→0.48**; ramp later+slower (DIFF_START 2→3, DIFF_LEN 16→22, DIFF_SCORE_START
  1000→2000, **DIFF_SCORE_LEN 13k→20k** = fully hard ~22k); DEEP_START 20k→35k, DEEP_LEN 130k→160k; drought
  52/26→40/18; gift 0.26→0.34 + 0.06 floor; smart_p 0.35→0.45, SMART_FADE_MOVES 10→16; EARLY_CLEAR_SETS 3→4.
  These compound. **If still hard, next levers: `_hard_bias` cap + `DIFF_SCORE_LEN`.**

### 3. Battery / FPS — now 60fps everywhere `@bcfc483`
Audited: gameplay (`Game.gd`) + board (`Grid.gd`) already throttle idle redraws / animated skins to 30fps
and use a GPU shader for the board frame — good. Menu + game-over were full-60fps decorative. Briefly tried
game-over at 30 but Jay wanted 60 (felt framey), so **menu, gameplay, and game-over all `Engine.max_fps=60`**
now (set in each scene's `_ready`; GameState boot default 60). Biomes is an overlay inside MainMenu → already
60. The **global 60 cap (vs 120Hz uncapped) is the real battery win.** Unused optional lever: pause the menu's
animated-bg redraw when a full-cover overlay panel is open.

### 4. Leaderboard
- **Zero-score test rows** (Test/Player1/random names) were in Supabase `public.players` — NOT from tester
  emails (Play Store enrollment never writes to the backend), just leftover seed/test data. Jay ran SQL:
  `delete from public.players where best_score = 0;` + replaced `get_global_board` to `where best_score > 0`.
  Schema doc synced in repo `@08ee019` (SUPABASE_SETUP.md). Friends board (`get_friends_board`) was left as-is.
- **Scroll fix `@30e73ab`:** leaderboard/friends rows (`_make_board_row`) defaulted to `MOUSE_FILTER_STOP`, so
  they swallowed touch drags — only the scrollbar scrolled. Set the card to PASS + children (row/labels/pin)
  to IGNORE so a drag anywhere scrolls, like achievements. Covers both GLOBAL + FRIENDS tabs.

### 5. Mac build sync `@2371b0a`
From Jay's Mac (iOS prep): new app icon (`icon.svg.png`), `project.godot config/icon` → `res://icon.svg.png`,
`export_presets.cfg` build number **31 → 43**. (Done as targeted edits — our project.godot is CRLF, Mac is LF.)

### 6. Dev tools — added then removed
Added an "UNLOCK ALL (DEV)" Settings button + `GameState.dev_unlock_all()` `@f736cb4` so Jay could max
level/skins on-device. He used it (he's now **level 100** on his profile — persists via local save across
TestFlight updates). **Fully REMOVED `@bcfc483`** (no flag/footgun left). Quick re-add if asked: max
`player_xp` to level 100 + set every `ACH_GROUPS` tier in `unlocked` + `_save()`.

## Non-code (reference for Jay's monetization thinking, not tasks)
- **Block Blast comp:** ~35.5M DAU now (70M peak), ~$17.5M/mo ad revenue, #1 most-downloaded game 2024+2025,
  almost 100% ads (IAP ~$66k lifetime). Mediocre retention (D1 26%/D7 4%) — scale is from VOLUME.
- **STAX earnings model (rewarded-only):** plan with ARPDAU ~$0.008–0.012 (US-heavy up to $0.02–0.03,
  global LATAM/India-heavy $0.003–0.006). A sustained 10M views/mo @ 40% US → realistic ~$6–10k/mo. Ad
  revenue is 0% platform cut (Apple/Google only cut IAP). Jay's viral short-form skill is the real asset.

## Store status (App Store Connect)
1.0 is **live**. 1.1 has been **"Waiting for Review" ~1 week** (in queue, NOT rejected). Discussed: best to
**consolidate everything into one build** (remove the queued 1.1, rebuild from `main`, resubmit — resets
queue position but ships everything in one review) + optionally **request expedited review**, rather than let
1.1 ship then wait again for a 1.2. The TestFlight push (build 43) is that consolidated build.

Good luck — pick up wherever Jay's device feedback points. — Claude (2026-06-20)
