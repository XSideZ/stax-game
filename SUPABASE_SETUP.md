# STAX online leaderboard + friends — Supabase setup

Pure HTTPS from Godot (no native plugin), so iOS + Android share ONE leaderboard.

## 1. Create the project
1. Go to https://supabase.com → new project (free tier is fine). Pick a region near your players.
2. Once it's up, open **Project Settings → API** and copy:
   - **Project URL** (e.g. `https://abcdxyz.supabase.co`)
   - **anon public** key (the long one labelled `anon` / `public` — safe to ship in the app)

## 2. Paste the keys into the app
In `scripts/Net.gd`, set:
```gdscript
const SUPABASE_URL      := "https://abcdxyz.supabase.co"   # your Project URL
const SUPABASE_ANON_KEY := "eyJhbGci..."                    # your anon public key
```
Until these are filled in, the game runs exactly as before (all network calls no-op).

## 3. Run the SQL
Open **SQL Editor → New query**, paste the whole block below, Run.

```sql
-- ── Tables ──────────────────────────────────────────────────────────────────
create table if not exists public.players (
  id          uuid primary key,
  friend_code text unique not null,
  name        text not null default 'PLAYER',
  best_score  int  not null default 0,
  level       int  not null default 1,
  updated_at  timestamptz not null default now()
);

create table if not exists public.friendships (
  player_id  uuid not null references public.players(id) on delete cascade,
  friend_id  uuid not null references public.players(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (player_id, friend_id)
);

create index if not exists idx_players_best on public.players (best_score desc);

-- ── Lock the tables: no direct access. Everything goes through the functions ──
alter table public.players      enable row level security;
alter table public.friendships  enable row level security;
-- (RLS on with no policies = the anon key cannot read/write tables directly)

-- ── Functions (SECURITY DEFINER: run as owner, bypass RLS in a controlled way) ─

-- Upsert the caller's row; keeps the higher score. Creates the row on first call.
create or replace function public.submit_score(
  p_id uuid, p_code text, p_name text, p_score int, p_level int)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into players (id, friend_code, name, best_score, level, updated_at)
  values (p_id, p_code, left(p_name, 12), greatest(p_score, 0), p_level, now())
  on conflict (id) do update
    set name       = left(excluded.name, 12),
        best_score = greatest(players.best_score, excluded.best_score),
        level      = excluded.level,
        updated_at = now();
end; $$;

-- Top N globally. Returns NO ids/codes, so clients can't grief other players.
create or replace function public.get_global_board(p_limit int default 50)
returns table(rank int, name text, best_score int, level int)
language sql security definer set search_path = public as $$
  select (row_number() over (order by best_score desc, updated_at asc))::int,
         name, best_score, level
  from players
  order by best_score desc, updated_at asc
  limit greatest(1, least(p_limit, 200));
$$;

-- The caller's global rank (1-based).
create or replace function public.get_my_rank(p_id uuid)
returns int language sql security definer set search_path = public as $$
  select count(*)::int + 1 from players
  where best_score > coalesce((select best_score from players where id = p_id), 0);
$$;

-- Add a friend by their code (one-way: you see people you add). Returns their name.
create or replace function public.add_friend_by_code(p_id uuid, p_code text)
returns text language plpgsql security definer set search_path = public as $$
declare fid uuid; fname text;
begin
  select id, name into fid, fname from players where friend_code = upper(p_code);
  if fid is null or fid = p_id then return null; end if;
  insert into friendships (player_id, friend_id) values (p_id, fid)
    on conflict do nothing;
  return fname;
end; $$;

-- Friends leaderboard (your friends + you), sorted. is_me flags your own row.
create or replace function public.get_friends_board(p_id uuid)
returns table(rank int, name text, best_score int, level int, is_me boolean)
language sql security definer set search_path = public as $$
  with f as (
    select friend_id as id from friendships where player_id = p_id
    union select p_id
  )
  select (row_number() over (order by p.best_score desc, p.updated_at asc))::int,
         p.name, p.best_score, p.level, (p.id = p_id)
  from players p join f on f.id = p.id
  order by p.best_score desc, p.updated_at asc;
$$;

-- ── Let the public anon role call ONLY these functions ──────────────────────
grant execute on function public.submit_score(uuid,text,text,int,int) to anon;
grant execute on function public.get_global_board(int)                 to anon;
grant execute on function public.get_my_rank(uuid)                     to anon;
grant execute on function public.add_friend_by_code(uuid,text)         to anon;
grant execute on function public.get_friends_board(uuid)               to anon;
```

## 4. Test
- Launch STAX on two devices (or wipe the save between runs). Each generates a UUID +
  friend code and pushes a row up on launch / game over.
- In **Table Editor → players** you should see rows appear with names + best scores.
- Friends UI (add-by-code + friends board) is the next build step in-app.

## Notes / limitations (v1)
- **Identity is anonymous** (device UUID in the save). Wiping the app loses the account.
  Optional "sign in to back up" can come later.
- **Scores are client-submitted** → a determined user can inflate their OWN score. The
  functions never expose other players' ids, so you can't tamper with anyone else.
  Fine for a casual game; server-validated runs would be a much bigger lift.
- **Store requirements before shipping social:** a privacy policy, plus a name filter +
  a "report" path (Apple requires UGC moderation for anything social).
