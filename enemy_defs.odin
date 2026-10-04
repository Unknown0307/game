package main

import "core:math"
import "core:math/linalg"
import "core:math/rand"
import rl "vendor:raylib"

// =============================================================================
// enemy_defs.odin - the enemy registry: everything that DESCRIBES an enemy type.
//
// HOW TO ADD AN ENEMY
//   1. Add a value to EnemyKind (types.odin).
//   2. Add one `case` to enemy_def() below and fill in only the hooks it needs.
//   3. Write the hooks (small procs, usually in this file; art goes in
//      enemy_art.odin). Every hook is optional - a nil hook means "default".
//   4. Give it a `spawn_chance` to make it appear in regular waves, or spawn it
//      by hand with spawn_enemy_at() (bosses, minions, asteroids do that).
//   The update loop, collisions, kills, drawing and glow all go through this
//   table, so nothing else has to change.
//
// Hooks (all optional):
//   init          fill in radius / speed / hp / colour for a freshly spawned enemy
//   spawn_chance  share of regular spawns (0..1) at this level; the rest are Normal
//   ai            per-frame brain run before moving; return true to hold position
//   move          per-frame movement (default: stands still)
//   trail         per-frame particle trail
//   tick          fixed 60 Hz tick (fuses and the like)
//   inert         true = the enemy is parked: harmless, untargeted, does not move
//   on_contact    what happens when it touches a player or a player's minion
//   on_death      what happens when it dies (default: coin / status / skill drops)
//   draw, glow    drawing (see enemy_art.odin / render.odin)
// =============================================================================

// Something an enemy can touch and hurt.
HitTarget :: union {
	^Player,
	^PlayerMinion,
}

EnemyDef :: struct {
	init:         proc(e: ^Enemy, lp: LevelParams),
	spawn_chance: proc(lp: LevelParams) -> f32,
	ai:           proc(g: ^Game, e: ^Enemy, dt: f32) -> (hold_position: bool),
	move:         proc(g: ^Game, e: ^Enemy, dt: f32),
	trail:        proc(g: ^Game, e: Enemy),
	tick:         proc(g: ^Game, e: ^Enemy),
	inert:        proc(e: Enemy) -> bool,
	on_contact:   proc(g: ^Game, e: ^Enemy, target: HitTarget, epos: [2]f32),
	on_death:     proc(g: ^Game, e: ^Enemy),
	draw:         proc(g: ^Game, e: Enemy, col: rl.Color, t, ph: f32, frozen: bool),
	glow:         proc(g: ^Game, e: Enemy, t: f32),

	// Flags
	is_boss:        bool,       // takes hp damage instead of dying, can't be reflected, blocks the portal
	wraps_screen:   bool,       // leaves one edge, re-enters the opposite one (and is hit across the seam)
	cull_offscreen: bool,       // removed once it flies far off-screen
	smashes_allies: bool,       // kills an ally outright instead of taking one hit
	wrap_color:     rl.Color,   // flash colour when it wraps
	score_float:    FloatKind,  // style of the floating score text
}

// The registry. One case per enemy type.
enemy_def :: proc(kind: EnemyKind) -> EnemyDef {
	switch kind {
	case .Normal:
		return EnemyDef{init = init_normal, move = move_chaser, draw = draw_normal}
	case .Runner:
		return EnemyDef{init = init_runner, spawn_chance = chance_runner, move = move_runner,
			trail = trail_runner, draw = draw_runner_enemy, cull_offscreen = true}
	case .Big:
		return EnemyDef{init = init_big, spawn_chance = chance_big, move = move_chaser,
			draw = draw_big, glow = glow_big}
	case .Sticky:
		return EnemyDef{init = init_sticky, spawn_chance = chance_sticky, move = move_chaser,
			trail = trail_sticky, tick = tick_sticky, inert = inert_sticky, on_contact = contact_sticky,
			draw = draw_sticky, glow = glow_sticky}
	case .Minion:
		return EnemyDef{init = init_minion, move = move_runner, trail = trail_minion,
			draw = draw_minion, glow = glow_minion, cull_offscreen = true}
	case .Boss:
		return EnemyDef{init = init_boss, ai = update_boss_ai, move = move_boss, trail = trail_boss,
			on_contact = contact_boss, on_death = death_boss, draw = draw_boss, glow = glow_boss,
			is_boss = true, wraps_screen = true, smashes_allies = true, wrap_color = BOSS_PURPLE,
			score_float = .Boss}
	case .Asteroid:
		return EnemyDef{init = init_asteroid, move = move_asteroid, on_death = death_asteroid,
			draw = draw_asteroid_enemy, cull_offscreen = true}
	}
	return EnemyDef{}
}

// --- Spawning ---

// Builds an enemy of `kind` scaled for the current level.
make_enemy :: proc(kind: EnemyKind, lp: LevelParams) -> Enemy {
	e := Enemy{kind = kind, active = true, hp = 1, max_hp = 1, damage = 1, points = 10}
	init := enemy_def(kind).init
	if init != nil do init(&e, lp)
	return e
}

// Which enemy a regular spawn should be: every kind with a spawn_chance gets that share,
// whatever is left over is Normal.
pick_enemy_kind :: proc(lp: LevelParams) -> EnemyKind {
	roll := rand.float32()
	for kind in EnemyKind {
		chance := enemy_def(kind).spawn_chance
		if chance == nil do continue
		share := chance(lp)
		if roll < share do return kind
		roll -= share
	}
	return .Normal
}

level_steps :: proc(lp: LevelParams) -> f32 {
	return f32(max(lp.level - 1, 0))
}

chance_sticky :: proc(lp: LevelParams) -> f32 {
	return min(STICKY_CHANCE_BASE + STICKY_CHANCE_STEP * level_steps(lp), STICKY_CHANCE_MAX)
}

chance_big :: proc(lp: LevelParams) -> f32 {
	return min(BIG_CHANCE_BASE + BIG_CHANCE_STEP * level_steps(lp), BIG_CHANCE_MAX)
}

chance_runner :: proc(lp: LevelParams) -> f32 {
	return min(RUNNER_CHANCE_BASE + RUNNER_CHANCE_STEP * level_steps(lp), RUNNER_CHANCE_MAX)
}

// --- init hooks (radius, speed, colour, hp, points) ---

init_normal :: proc(e: ^Enemy, lp: LevelParams) {
	e.radius = 12.0
	e.speed  = rand.float32_range(90.0, 150.0) * lp.speed_mult
	e.color  = rl.RED
	e.points = 10
}

init_runner :: proc(e: ^Enemy, lp: LevelParams) {
	e.radius = 8.0
	e.speed  = rand.float32_range(150.0, 210.0) * lp.speed_mult
	e.color  = rl.ORANGE
	e.points = 15
}

init_big :: proc(e: ^Enemy, lp: LevelParams) {
	// Bigger ones are slower, hit harder and are worth more.
	e.radius = rand.float32_range(20.0, 34.0)
	e.speed  = (75.0 - (e.radius - 20.0) * 2.5) * lp.speed_mult
	e.color  = rl.Color{190, 35, 70, 255}
	e.damage = 2
	if e.radius >= 27.0 do e.damage = 3
	e.points = i32(e.radius * 1.5)
	e.gun_ticks = BIG_SHOOT_COOLDOWN_TICKS + rand.int31_max(21) // don't open fire the instant it spawns
	e.gun_flip  = rand.int31_max(2) == 0
	if rand.float32() < BIG_LASER_CHANCE {
		e.laser = true
		e.color = rl.Color{35, 140, 190, 255}
	}
}

init_sticky :: proc(e: ^Enemy, lp: LevelParams) {
	e.radius = 10.0
	e.speed  = rand.float32_range(42.0, 62.0) * lp.speed_mult
	e.color  = rl.Color{255, 80, 210, 255}
	e.damage = STICKY_EXPLOSION_DAMAGE
	e.points = 25
}

init_minion :: proc(e: ^Enemy, lp: LevelParams) {
	e.radius = 10.0
	e.speed  = rand.float32_range(140.0, 195.0) * lp.speed_mult
	e.color  = rl.Color{210, 130, 255, 255}
	e.points = 12
}

init_asteroid :: proc(e: ^Enemy, lp: LevelParams) {
	e.radius = rand.float32_range(ASTEROID_RADIUS_MIN, ASTEROID_RADIUS_MAX)
	e.speed  = rand.float32_range(ASTEROID_SPEED_MIN, ASTEROID_SPEED_MAX) * min(lp.speed_mult, 1.3)
	e.color  = rl.Color{150, 135, 120, 255}
	e.damage = 2 if e.radius >= 17.0 else 1
	e.points = ASTEROID_POINTS
	e.spin   = rand.float32_range(-1.6, 1.6)
}

init_boss :: proc(e: ^Enemy, lp: LevelParams) {
	e.radius = BOSS_RADIUS
	e.speed  = min(BOSS_BASE_SPEED * lp.speed_mult, PLAYER_MAX_SPEED * BOSS_SPEED_CAP)
	e.color  = rl.Color{180, 60, 255, 255}
	e.hp     = lp.boss_hp
	e.max_hp = lp.boss_hp
	e.damage = BOSS_DAMAGE
	e.points = BOSS_SCORE
	e.can_repel = lp.boss_has_ability
	e.repel_cd  = BOSS_FIRST_REPEL_DELAY
	e.summon_cd = BOSS_FIRST_SUMMON_DELAY
	e.dash_cd   = BOSS_DASH_FIRST_DELAY
}

// --- move hooks ---

// Direction (and facing angle) from an enemy toward the nearest living player.
chase_dir :: proc(g: ^Game, e: ^Enemy) -> (dir: [2]f32, want: f32, ok: bool) {
	wrap := enemy_def(e.kind).wraps_screen
	target, _, found := nearest_target(g, e.pos, wrap)
	if !found do return

	delta := target - e.pos
	if wrap do delta = wrap_delta(e.pos, target)
	dist := linalg.length(delta)
	if dist <= 0.001 do return

	dir  = delta / dist
	want = math.atan2(dir.y, dir.x)
	ok   = true
	return
}

// Straight at the target, turning the sprite quickly.
move_chaser :: proc(g: ^Game, e: ^Enemy, dt: f32) {
	dir, want, ok := chase_dir(g, e)
	if !ok do return
	e.pos += dir * e.speed * dt
	e.angle = turn_toward(e.angle, want, 8.0 * dt)
}

// Limited turning that gets better with the level (see steer_runner).
move_runner :: proc(g: ^Game, e: ^Enemy, dt: f32) {
	dir, _, ok := chase_dir(g, e)
	if !ok do return
	steer_runner(e, dir, dt, g.params)
	e.pos += e.heading * e.speed * dt
	e.angle = math.atan2(e.heading.y, e.heading.x)
}

move_boss :: proc(g: ^Game, e: ^Enemy, dt: f32) {
	dir, want, ok := chase_dir(g, e)
	if !ok do return
	e.pos += dir * e.speed * dt
	e.angle = turn_toward(e.angle, want, 1.8 * dt) // a whale turns slowly
}

// Asteroids ignore targets: they drift on a straight line.
move_asteroid :: proc(g: ^Game, e: ^Enemy, dt: f32) {
	e.pos += e.heading * e.speed * dt
	e.angle += e.spin * dt
}

// --- trail hooks ---

trail_runner :: proc(g: ^Game, e: Enemy) {
	if rand.float32() < 0.5 do spawn_particle(g, epoint(e.pos, e.angle, e.radius, -1.4, 0), {0, 0}, rl.ORANGE, 0.3, 4)
}

trail_minion :: proc(g: ^Game, e: Enemy) {
	if rand.float32() < 0.4 do spawn_particle(g, epoint(e.pos, e.angle, e.radius, -1.3, 0), {0, 0}, e.color, 0.35, 3)
}

trail_sticky :: proc(g: ^Game, e: Enemy) {
	spawn_particle(g, e.pos, {0, 0}, rl.Color{255, 80, 210, 255}, 0.4, 3)
}

trail_boss :: proc(g: ^Game, e: Enemy) {
	jitter := [2]f32{rand.float32_range(-1, 1), rand.float32_range(-1, 1)}
	spawn_particle(g, e.pos + jitter * (e.radius * 0.6), jitter * 40, rl.Color{255, 60, 60, 255} if e.enraged else rl.Color{255, 90, 200, 255}, 0.5, 6)
}

// --- Sticky bomb: parks itself on contact, then detonates ---

inert_sticky :: proc(e: Enemy) -> bool {
	return e.stuck
}

tick_sticky :: proc(g: ^Game, e: ^Enemy) {
	if !e.stuck do return
	e.stick_ticks -= 1
	if e.stick_ticks <= 0 do explode_sticky_enemy(g, e)
}

contact_sticky :: proc(g: ^Game, e: ^Enemy, target: HitTarget, epos: [2]f32) {
	// No contact damage: freeze here, wait a few ticks, detonate.
	e.stuck = true
	e.stick_ticks = STICKY_STICK_TICKS
	e.stick_pos = e.pos
	e.flash = 0.35
	spawn_burst(g, e.pos, rl.Color{255, 220, 90, 255}, 18, 130, 3)
}

// --- Contact: what an enemy does when it touches a player or a player's minion ---

target_center :: proc(t: HitTarget) -> [2]f32 {
	#partial switch v in t {
	case ^Player:       return player_center(v^)
	case ^PlayerMinion: return v.pos
	}
	return {}
}

hurt_target :: proc(g: ^Game, t: HitTarget, amount: i32) {
	#partial switch v in t {
	case ^Player:       hurt_player(g, v, amount)
	case ^PlayerMinion: hurt_minion(g, v, amount)
	}
}

// Default contact: the enemy is used up and the target takes its damage.
contact_consume :: proc(g: ^Game, e: ^Enemy, target: HitTarget, epos: [2]f32) {
	e.active = false
	hurt_target(g, target, e.damage)
	spawn_burst(g, e.pos, e.color, 8, 150, 3)
}

// The boss isn't consumed: it hurts on its hit cooldown, then gets knocked back.
contact_boss :: proc(g: ^Game, e: ^Enemy, target: HitTarget, epos: [2]f32) {
	if e.hit_cd > 0 do return
	e.hit_cd = BOSS_HIT_COOLDOWN
	e.dash_t = 0
	hurt_target(g, target, e.damage)
	offset := epos - target_center(target)
	dist := linalg.length(offset)
	if dist > 0.001 do e.pos += offset / dist * 120
}

enemy_contact :: proc(g: ^Game, e: ^Enemy, target: HitTarget, epos: [2]f32) {
	hook := enemy_def(e.kind).on_contact
	if hook != nil {
		hook(g, e, target, epos)
	} else {
		contact_consume(g, e, target, epos)
	}
}

// A parked enemy (stuck bomb) is harmless and ignored by collisions.
enemy_inert :: proc(e: Enemy) -> bool {
	inert := enemy_def(e.kind).inert
	return inert != nil && inert(e)
}

// --- Death ---

// Default: a coin now and then, plus a chance for a status / skill drop.
death_default :: proc(g: ^Game, e: ^Enemy) {
	if rand.float32() < COIN_DROP_CHANCE do spawn_coin_at(g, e.pos)
	roll_status_drop(g, e.pos, false)
	roll_skill_drop(g, e.pos, false)
}

death_boss :: proc(g: ^Game, e: ^Enemy) {
	spawn_burst(g, e.pos, rl.GOLD, 80, 420, 5)
	spawn_burst(g, e.pos, rl.WHITE, 40, 300, 4)
	add_shake(g, 18)
	for _ in 0 ..< 8 {
		spawn_coin_at(g, e.pos + [2]f32{rand.float32_range(-50, 50), rand.float32_range(-50, 50)})
	}
	roll_status_drop(g, e.pos, true)
	roll_skill_drop(g, e.pos, true)
}

// Rocks are plentiful on belt levels: no coin / status / skill rolls.
death_asteroid :: proc(g: ^Game, e: ^Enemy) {
	spawn_burst(g, e.pos, rl.Color{190, 170, 150, 255}, 6, 120, 2.5)
}
