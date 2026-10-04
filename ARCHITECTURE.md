# Runner - architecture & extension guide

Single Odin package (`odin run .`). All state lives in one `Game` struct
(`types.odin`); systems are plain procs that take `^Game`.

## The one idea: registries

Every kind of content is described in **one place**, a `*_def(kind)` proc with a
`switch`, returning a struct of data plus optional hook procs. The rest of the
game (update loop, collisions, HUD, drops, drawing) only ever asks the registry.
Adding content = *one enum value + one `case` + the hook procs you need*.
A `nil` hook always means "default behaviour".

| Content  | Enum (types.odin) | Registry                       | Behaviour code            |
|----------|-------------------|--------------------------------|---------------------------|
| Status   | `StatusKind`      | `status_def`  (status.odin)    | passive numbers + `on_apply` |
| Skill    | `SkillKind`       | `skill_def`   (skill_defs.odin)| `use_*` procs (skills.odin)  |
| Enemy    | `EnemyKind`       | `enemy_def`   (enemy_defs.odin)| hooks in enemy_defs.odin; art in enemy_art.odin |
| Ally     | `AllyKind`        | `ally_def`    (ally_defs.odin) | hooks in ally_defs.odin   |
| Shader   | `Shaders` struct  | `load_shaders` (shaders.odin)  | GLSL in `shaders/*.fs`    |

## Recipes

### Add a status (e.g. "+8% move speed")
1. `StatusKind`: add `Swift`.
2. `status_def`: `case .Swift: return StatusDef{name = "SPEED +8%", label = "SPD", color = rl.ORANGE, drop_weight = 1, on_apply = ...}`.
   Pure stat statuses use the numeric fields (`size_bonus`, `cooldown_reduction`,
   `damage_reduction`, `max_health_bonus`). For a new stat, read it where it matters
   by counting copies: `count_status(p, .Swift)`.
That's it - pickup colour/label, HUD slot, drop roll, stacking and the cap
(`MAX_STATUSES`) already work.

### Add a skill
1. `SkillKind`: add it (enum order = wheel order).
2. `skill_def`: name, 3-letter label, colour, `cooldown` (ticks), `use = use_myskill`.
   Optional: `cooldown_extra`, `has_aim_toggle`, `progress`, `hud_status`.
3. Write `use_myskill :: proc(g: ^Game, p: ^Player, index: i32)`.
Dice drops, the wheel, cycling, cooldown ticking and the Cooldown status are automatic.
A skill that needs per-frame state adds fields to `Player` and a line in
`tick_player_skills` (ticks) or `update_player_timers` (visuals).

### Add an enemy
1. `EnemyKind`: add it.
2. `enemy_def`: `case .Zigzag: return EnemyDef{init = init_zigzag, move = move_zigzag, draw = draw_zigzag, spawn_chance = chance_zigzag}`
3. Write the hooks. `init` sets radius/speed/hp/colour; `spawn_chance(lp)` is its share
   of regular waves (the rest are Normal); `draw` goes in enemy_art.odin.
   Other hooks: `ai`, `trail`, `tick` (60 Hz), `inert`, `on_contact`, `on_death`, `glow`,
   flags `is_boss`, `wraps_screen`, `cull_offscreen`, `smashes_allies`.
   Boss-like enemies are spawned by hand with `spawn_enemy_at` (see boss.odin).

### Add an ally
1. `AllyKind`: add it. 2. `ally_def`: hp, colours, `spawn_chance`, `on_touch`, `draw_icon`.

### Add a shader
1. Put the GLSL in `shaders/myeffect.fs` and embed it: `MYEFFECT_FS :: #load("shaders/myeffect.fs", string)` (shaders.odin).
2. Add a struct with the shader + uniform locations, a field in `Shaders`, load it in
   `load_shaders` (use `load_fragment`) and unload it in `unload_shaders`.
3. Add a `draw_myeffect(...)` / `set_myeffect(...)` helper next to the others and call it from render.odin.

### Add a "gimmick" (level rule, hazard, event)
- Per-level setup: `set_level` / `reset_level_world` in game.odin.
- Per-frame systems run from `update_playing` (game.odin) - add a line there.
- Fixed-rate (60 Hz) logic: `update_ticks`. Drawing: `render_world` (render.odin).
- Numbers that scale with the level: `level_params` (difficulty.odin).
- Tunables always go in config.odin.

## File map

    main.odin        window + frame loop
    config.odin      every tunable constant
    types.odin       data structures, enums (no behaviour)
    difficulty.odin  level number -> LevelParams
    game.odin        phases, level flow, update order, spawners

    status.odin      status registry + stacking          (content)
    skill_defs.odin  skill registry + HUD hooks          (content)
    enemy_defs.odin  enemy registry + enemy hooks        (content)
    ally_defs.odin   ally registry + hooks               (content)

    skills.odin      skill behaviours, the player gun, skill dice
    enemy.odin       spawning, steering helpers, collisions, kills
    boss.odin        boss spawn + abilities
    gunfire.odin     enemy bullets, lasers, mothership raygun
    minions.odin     the Minion status drone
    pickups.odin     coins, allies, status drops
    player.odin     players, shields, damage

    render.odin / enemy_art.odin / ship_art.odin / toon.odin   drawing
    shaders.odin + shaders/*.fs                                 GLSL + loaders
    style.odin / backdrop.odin                                  level palettes, space backdrop
    hud.odin / menu.odin                                        HUD and menus
    fx.odin                                                     particles, floating text, shake

## Known seams (next candidates)
- `Enemy` is one flat struct holding the state of every enemy type (laser, stuck,
  boss ability timers...). Fine at this size; when it grows, move per-type state into
  sub-structs or a union keyed by `kind`.
- Enemy weapons (`update_enemy_guns` in gunfire.odin) still switch on kind; they could
  become an `EnemyDef.tick`/`fire` hook.
- Rocket's gun behaviour (`fire_gun`) is still keyed on `p.skill == .Rocket`.
