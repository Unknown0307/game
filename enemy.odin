package main

import "core:math"
import "core:math/linalg"
import "core:math/rand"
import rl "vendor:raylib"

// =============================================================================
// enemy.odin - enemy construction, spawning, steering, collisions and kills.
// Boss-only behaviour lives in boss.odin.
// =============================================================================

alloc_enemy :: proc(g: ^Game) -> ^Enemy {
	for &e in g.enemies {
		if !e.active do return &e
	}
	return nil
}

count_bosses :: proc(g: ^Game) -> int {
	n := 0
	for e in g.enemies {
		if e.active && e.kind == .Boss do n += 1
	}
	return n
}

// Builds an enemy of `kind` scaled for the current level.
make_enemy :: proc(kind: EnemyKind, lp: LevelParams) -> Enemy {
	e := Enemy{kind = kind, active = true, hp = 1, max_hp = 1, damage = 1, points = 10}
	mult := lp.speed_mult

	switch kind {
	case .Normal:
		e.radius = 12.0
		e.speed  = rand.float32_range(90.0, 150.0) * mult
		e.color  = rl.RED
		e.points = 10
	case .Runner:
		e.radius = 8.0
		e.speed  = rand.float32_range(150.0, 210.0) * mult
		e.color  = rl.ORANGE
		e.points = 15
	case .Big:
		// Bigger ones are slower, hit harder and are worth more.
		e.radius = rand.float32_range(20.0, 34.0)
		e.speed  = (75.0 - (e.radius - 20.0) * 2.5) * mult
		e.color  = rl.Color{190, 35, 70, 255}
		e.damage = 2
		if e.radius >= 27.0 do e.damage = 3
		e.points = i32(e.radius * 1.5)
	case .Sticky:
		e.radius = 10.0
		e.speed  = rand.float32_range(42.0, 62.0) * mult
		e.color  = rl.Color{255, 80, 210, 255}
		e.damage = STICKY_EXPLOSION_DAMAGE
		e.points = 25
	case .Boss:
		e.radius = BOSS_RADIUS
		e.speed  = min(BOSS_BASE_SPEED * mult, PLAYER_MAX_SPEED * BOSS_SPEED_CAP)
		e.color  = rl.Color{180, 60, 255, 255}
		e.hp     = lp.boss_hp
		e.max_hp = lp.boss_hp
		e.damage = BOSS_DAMAGE
		e.points = BOSS_SCORE
		e.can_repel = lp.boss_has_ability
		e.repel_cd  = BOSS_FIRST_REPEL_DELAY
		e.summon_cd = BOSS_FIRST_SUMMON_DELAY
	}
	return e
}

// Places a new enemy at an explicit position (used by boss summons).
spawn_enemy_at :: proc(g: ^Game, kind: EnemyKind, pos: [2]f32) -> ^Enemy {
	slot := alloc_enemy(g)
	if slot == nil do return nil
	slot^ = make_enemy(kind, g.params)
	slot.pos = pos
	return slot
}

// A point just outside a random screen edge.
edge_spawn_position :: proc(radius: f32) -> (pos: [2]f32) {
	pad := radius + 10
	switch rand.int31_max(4) {
	case 0:
		pos = {rand.float32_range(0, SCREEN_W), -pad}
	case 1:
		pos = {SCREEN_W + pad, rand.float32_range(0, SCREEN_H)}
	case 2:
		pos = {rand.float32_range(0, SCREEN_W), SCREEN_H + pad}
	case:
		pos = {-pad, rand.float32_range(0, SCREEN_H)}
	}
	return
}

spawn_enemy_at_edge :: proc(g: ^Game, kind: EnemyKind) -> ^Enemy {
	e := spawn_enemy_at(g, kind, {})
	if e == nil do return nil
	e.pos = edge_spawn_position(e.radius)
	return e
}

// --- Targeting & movement ---

// Nearest living player OR ally (enemies go after allies too).
nearest_target :: proc(g: ^Game, from: [2]f32) -> (target: [2]f32, dist: f32, found: bool) {
	dist = math.F32_MAX
	for p in g.players {
		if p.dead do continue
		c := player_center(p)
		d := linalg.length(c - from)
		if d < dist {
			dist, target, found = d, c, true
		}
	}
	for a in g.allies {
		if !a.active do continue
		d := linalg.length(a.pos - from)
		if d < dist {
			dist, target, found = d, a.pos, true
		}
	}
	return
}

nearest_player :: proc(g: ^Game, from: [2]f32) -> (target: [2]f32, dist: f32, found: bool) {
	dist = math.F32_MAX
	for p in g.players {
		if p.dead do continue
		c := player_center(p)
		d := linalg.length(c - from)
		if d < dist {
			dist, target, found = d, c, true
		}
	}
	return
}

rotate_vec :: proc(v: [2]f32, angle: f32) -> [2]f32 {
	c := math.cos(angle)
	s := math.sin(angle)
	return {v.x * c - v.y * s, v.x * s + v.y * c}
}

// Runners only curve while the target is inside a narrow forward cone. If the
// target is behind them they keep going straight (and are culled off-screen).
steer_runner :: proc(e: ^Enemy, dir: [2]f32, dt: f32, lp: LevelParams) {
	if linalg.length(e.heading) <= 0.001 {
		e.heading = dir
		return
	}
	current := math.atan2(e.heading.y, e.heading.x)
	desired := math.atan2(dir.y, dir.x)
	delta := desired - current
	if delta > math.PI do delta -= 2 * math.PI
	if delta < -math.PI do delta += 2 * math.PI

	if abs(delta) <= lp.runner_cone {
		turn := clamp(delta, -lp.runner_turn_rate * dt, lp.runner_turn_rate * dt)
		e.heading = rotate_vec(e.heading, turn)
	}
}

move_enemy :: proc(g: ^Game, e: ^Enemy, dt: f32) {
	target, dist, found := nearest_target(g, e.pos)
	if !found || dist <= 0.001 do return

	dir := (target - e.pos) / dist
	if e.kind == .Runner {
		steer_runner(e, dir, dt, g.params)
		e.pos += e.heading * e.speed * dt
	} else {
		e.pos += dir * e.speed * dt
	}
}

outside_play_area :: proc(pos: [2]f32, margin: f32) -> bool {
	return pos.x < -margin || pos.x > SCREEN_W + margin || pos.y < -margin || pos.y > SCREEN_H + margin
}

emit_enemy_trail :: proc(g: ^Game, e: Enemy) {
	switch e.kind {
	case .Runner:
		if rand.float32() < 0.5 do spawn_particle(g, e.pos, {0, 0}, rl.ORANGE, 0.3, 4)
	case .Sticky:
		spawn_particle(g, e.pos, {0, 0}, rl.Color{255, 80, 210, 255}, 0.4, 3)
	case .Boss:
		jitter := [2]f32{rand.float32_range(-1, 1), rand.float32_range(-1, 1)}
		spawn_particle(g, e.pos + jitter * (e.radius * 0.6), jitter * 40, rl.Color{255, 90, 200, 255}, 0.5, 6)
	case .Normal, .Big:
	}
}

update_enemies :: proc(g: ^Game, dt: f32) {
	for &e in g.enemies {
		if !e.active do continue
		if e.hit_cd > 0 do e.hit_cd -= dt
		if e.flash > 0  do e.flash -= dt

		if e.kind == .Sticky && e.stuck {
			e.pos = e.stick_pos
			continue
		}

		hold := false
		if e.kind == .Boss do hold = update_boss_ai(g, &e, dt)
		if !hold do move_enemy(g, &e, dt)

		emit_enemy_trail(g, e)

		// A runner that missed and flew far off-screen would otherwise live forever
		// and slowly fill the enemy pool.
		if e.kind == .Runner && outside_play_area(e.pos, RUNNER_CULL_MARGIN) {
			e.active = false
		}
	}
}

// --- Killing ---

kill_enemy :: proc(g: ^Game, e: ^Enemy, killer: ^Player) {
	e.active = false
	killer.kill_count += 1
	killer.score += e.points

	fk := FloatKind.Score
	if e.kind == .Boss do fk = .Boss
	add_float(g, e.pos, e.points, fk)
	spawn_burst(g, e.pos, e.color, 10 + int(e.radius), 220, 3)

	if e.kind == .Boss {
		spawn_burst(g, e.pos, rl.GOLD, 80, 420, 5)
		spawn_burst(g, e.pos, rl.WHITE, 40, 300, 4)
		add_shake(g, 18)
		for _ in 0 ..< 8 {
			spawn_coin_at(g, e.pos + [2]f32{rand.float32_range(-50, 50), rand.float32_range(-50, 50)})
		}
		roll_enhancement_drop(g, e.pos, true)
	} else {
		if rand.float32() < COIN_DROP_CHANCE do spawn_coin_at(g, e.pos)
		roll_enhancement_drop(g, e.pos, false)
	}
}

// --- Collisions ---

explode_sticky_enemy :: proc(g: ^Game, e: ^Enemy) {
	center := e.stick_pos
	for &p in g.players {
		if p.dead do continue
		if rl.CheckCollisionCircleRec(center, STICKY_EXPLOSION_RADIUS, player_rect(p)) {
			hurt_player(g, &p, e.damage)
		}
	}
	spawn_burst(g, center, rl.Color{255, 70, 220, 255}, 42, 250, 4)
	spawn_burst(g, center, rl.Color{255, 220, 120, 255}, 18, 180, 3)
	add_shake(g, 8)
	e.active = false
}

update_sticky_ticks :: proc(g: ^Game) {
	for &e in g.enemies {
		if !e.active || e.kind != .Sticky || !e.stuck do continue
		e.stick_ticks -= 1
		if e.stick_ticks <= 0 do explode_sticky_enemy(g, &e)
	}
}

enemy_hits_player :: proc(g: ^Game, p: ^Player) {
	if p.dead do return
	rect := player_rect(p^)

	for &e in g.enemies {
		if !e.active do continue
		if e.kind == .Sticky && e.stuck do continue
		if !rl.CheckCollisionCircleRec(e.pos, e.radius, rect) do continue

		switch e.kind {
		case .Boss:
			// The boss isn't consumed: it hurts, then gets knocked back.
			if e.hit_cd <= 0 {
				e.hit_cd = BOSS_HIT_COOLDOWN
				hurt_player(g, p, e.damage)
				offset := e.pos - player_center(p^)
				dist := linalg.length(offset)
				if dist > 0.001 do e.pos += offset / dist * 120
			}
		case .Sticky:
			// No contact damage: freeze here, wait a few ticks, detonate.
			e.stuck = true
			e.stick_ticks = STICKY_STICK_TICKS
			e.stick_pos = e.pos
			e.flash = 0.35
			spawn_burst(g, e.pos, rl.Color{255, 220, 90, 255}, 18, 130, 3)
		case .Normal, .Runner, .Big:
			e.active = false
			hurt_player(g, p, e.damage)
			spawn_burst(g, e.pos, e.color, 8, 150, 3)
		}

		if p.dead do return
	}
}

// Enemies target allies too: contact damages the ally (a boss kills it outright).
enemies_hit_allies :: proc(g: ^Game) {
	for &e in g.enemies {
		if !e.active do continue
		for &a in g.allies {
			if !a.active do continue
			if !rl.CheckCollisionCircles(e.pos, e.radius, a.pos, a.radius) do continue

			if e.kind == .Boss {
				a.hp = 0
			} else {
				a.hp -= 1
				e.active = false
				spawn_burst(g, e.pos, e.color, 8, 150, 3)
			}
			a.flash = 0.2
			spawn_burst(g, a.pos, rl.LIME, 10, 140, 3)

			if a.hp <= 0 {
				a.active = false
				spawn_burst(g, a.pos, rl.LIME, 35, 260, 4)
				add_shake(g, 5)
			}
			if !e.active do break
		}
	}
}
