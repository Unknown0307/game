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
		e.gun_ticks = BIG_SHOOT_COOLDOWN_TICKS + rand.int31_max(21) // don't open fire the instant it spawns
		e.gun_flip  = rand.int31_max(2) == 0
		if rand.float32() < BIG_LASER_CHANCE {
			e.laser = true
			e.color = rl.Color{35, 140, 190, 255}
		}
	case .Sticky:
		e.radius = 10.0
		e.speed  = rand.float32_range(42.0, 62.0) * mult
		e.color  = rl.Color{255, 80, 210, 255}
		e.damage = STICKY_EXPLOSION_DAMAGE
		e.points = 25
	case .Minion:
		e.radius = 10.0
		e.speed  = rand.float32_range(140.0, 195.0) * mult
		e.color  = rl.Color{210, 130, 255, 255}
		e.points = 12
	case .Asteroid:
		e.radius = rand.float32_range(ASTEROID_RADIUS_MIN, ASTEROID_RADIUS_MAX)
		e.speed  = rand.float32_range(ASTEROID_SPEED_MIN, ASTEROID_SPEED_MAX) * min(mult, 1.3)
		e.color  = rl.Color{150, 135, 120, 255}
		e.damage = 2 if e.radius >= 17.0 else 1
		e.points = ASTEROID_POINTS
		e.spin   = rand.float32_range(-1.6, 1.6)
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
		e.dash_cd   = BOSS_DASH_FIRST_DELAY
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
	e.angle = math.atan2(f32(SCREEN_H) * 0.5 - e.pos.y, f32(SCREEN_W) * 0.5 - e.pos.x) // face the arena
	return e
}

// --- Targeting & movement ---

// Shortest vector from `from` to `to` when the screen wraps around (the boss
// takes shortcuts through the borders just like the players do).
wrap_delta :: proc(from, to: [2]f32) -> [2]f32 {
	d := to - from
	sw := f32(SCREEN_W)
	sh := f32(SCREEN_H)
	if d.x > sw * 0.5 {
		d.x -= sw
	} else if d.x < -sw * 0.5 {
		d.x += sw
	}
	if d.y > sh * 0.5 {
		d.y -= sh
	} else if d.y < -sh * 0.5 {
		d.y += sh
	}
	return d
}

// Nearest living player OR ally (enemies go after allies too).
nearest_target :: proc(g: ^Game, from: [2]f32, wrap := false) -> (target: [2]f32, dist: f32, found: bool) {
	dist = math.F32_MAX
	for p in g.players {
		if p.dead do continue
		c := player_center(p)
		d := linalg.length(wrap_delta(from, c) if wrap else c - from)
		if d < dist {
			dist, target, found = d, c, true
		}
	}
	for a in g.allies {
		if !a.active do continue
		d := linalg.length(wrap_delta(from, a.pos) if wrap else a.pos - from)
		if d < dist {
			dist, target, found = d, a.pos, true
		}
	}
	return
}

// Bosses wrap around the screen, so they exist at up to 9 positions. This returns
// the copy of the boss position closest to `point` (other enemies: just pos).
closest_wrapped_pos :: proc(e: Enemy, point: [2]f32) -> [2]f32 {
	if e.kind != .Boss do return e.pos
	best := e.pos
	best_d := linalg.length(e.pos - point)
	for ox in ([3]f32{0, SCREEN_W, -SCREEN_W}) {
		for oy in ([3]f32{0, SCREEN_H, -SCREEN_H}) {
			c := e.pos + [2]f32{ox, oy}
			d := linalg.length(c - point)
			if d < best_d {
				best, best_d = c, d
			}
		}
	}
	return best
}

// Seamless screen wrap for the boss: crossing an edge re-enters on the other side.
wrap_boss :: proc(e: ^Enemy) -> bool {
	sw := f32(SCREEN_W)
	sh := f32(SCREEN_H)
	before := e.pos
	if e.pos.x < 0 {
		e.pos.x += sw
	} else if e.pos.x > sw {
		e.pos.x -= sw
	}
	if e.pos.y < 0 {
		e.pos.y += sh
	} else if e.pos.y > sh {
		e.pos.y -= sh
	}
	return e.pos != before
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

turn_toward :: proc(cur, want, max_step: f32) -> f32 {
	d := want - cur
	for d > math.PI  do d -= 2 * math.PI
	for d < -math.PI do d += 2 * math.PI
	return cur + clamp(d, -max_step, max_step)
}

move_enemy :: proc(g: ^Game, e: ^Enemy, dt: f32) {
	if e.kind == .Asteroid {
		e.pos += e.heading * e.speed * dt
		e.angle += e.spin * dt
		return
	}
	wrap := e.kind == .Boss
	target, _, found := nearest_target(g, e.pos, wrap)
	if !found do return

	delta := target - e.pos
	if wrap do delta = wrap_delta(e.pos, target)
	dist := linalg.length(delta)
	if dist <= 0.001 do return
	dir := delta / dist
	want := math.atan2(dir.y, dir.x)

	switch e.kind {
	case .Runner, .Minion:
		steer_runner(e, dir, dt, g.params)
		e.pos += e.heading * e.speed * dt
		e.angle = math.atan2(e.heading.y, e.heading.x)
	case .Boss:
		e.pos += dir * e.speed * dt
		e.angle = turn_toward(e.angle, want, 1.8 * dt) // a whale turns slowly
	case .Normal, .Big, .Sticky:
		e.pos += dir * e.speed * dt
		e.angle = turn_toward(e.angle, want, 8.0 * dt)
	case .Asteroid:
		// handled in update_enemies (asteroids ignore targets)
	}
}

outside_play_area :: proc(pos: [2]f32, margin: f32) -> bool {
	return pos.x < -margin || pos.x > SCREEN_W + margin || pos.y < -margin || pos.y > SCREEN_H + margin
}

emit_enemy_trail :: proc(g: ^Game, e: Enemy) {
	switch e.kind {
	case .Runner:
		if rand.float32() < 0.5 do spawn_particle(g, epoint(e.pos, e.angle, e.radius, -1.4, 0), {0, 0}, rl.ORANGE, 0.3, 4)
	case .Minion:
		if rand.float32() < 0.4 do spawn_particle(g, epoint(e.pos, e.angle, e.radius, -1.3, 0), {0, 0}, e.color, 0.35, 3)
	case .Sticky:
		spawn_particle(g, e.pos, {0, 0}, rl.Color{255, 80, 210, 255}, 0.4, 3)
	case .Boss:
		jitter := [2]f32{rand.float32_range(-1, 1), rand.float32_range(-1, 1)}
		spawn_particle(g, e.pos + jitter * (e.radius * 0.6), jitter * 40, rl.Color{255, 60, 60, 255} if e.enraged else rl.Color{255, 90, 200, 255}, 0.5, 6)
	case .Normal, .Big, .Asteroid:
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

		// Repel knock-back: an impulse that fades out (the enemy keeps its own steering on top).
		if linalg.length(e.knock) > 1 {
			e.pos += e.knock * dt
			e.knock *= max(0, 1 - KNOCK_DECAY * dt)
		} else {
			e.knock = {}
		}

		// Reflected by Surprise: a straight-line missile until the effect runs out.
		if e.reflect_ticks > 0 {
			move_reflected_enemy(g, &e, dt)
			continue
		}

		hold := false
		if e.kind == .Boss do hold = update_boss_ai(g, &e, dt)
		if !hold do move_enemy(g, &e, dt)

		if e.kind == .Boss {
			before := e.pos
			if wrap_boss(&e) {
				// Warp flash on both sides of the border.
				spawn_burst(g, before, BOSS_PURPLE, 14, 200, 3)
				spawn_burst(g, e.pos, BOSS_PURPLE, 14, 200, 3)
			}
		}

		emit_enemy_trail(g, e)

		// A runner that missed and flew far off-screen would otherwise live forever
		// and slowly fill the enemy pool.
		if (e.kind == .Runner || e.kind == .Minion || e.kind == .Asteroid) && outside_play_area(e.pos, RUNNER_CULL_MARGIN) {
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
		roll_skill_drop(g, e.pos, true)
	} else if e.kind == .Asteroid {
		// rocks are plentiful on belt levels: no coin / enhancement / skill rolls
		spawn_burst(g, e.pos, rl.Color{190, 170, 150, 255}, 6, 120, 2.5)
	} else {
		if rand.float32() < COIN_DROP_CHANCE do spawn_coin_at(g, e.pos)
		roll_enhancement_drop(g, e.pos, false)
		roll_skill_drop(g, e.pos, false)
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

enemy_hits_player :: proc(g: ^Game, p: ^Player, index: i32) {
	if p.dead || p.invis_ticks > 0 do return // invisible: everything passes through
	rect := player_rect(p^)

	for &e in g.enemies {
		if !e.active do continue
		if e.kind == .Sticky && e.stuck do continue
		if e.reflect_ticks > 0 && e.reflect_owner == index do continue // never hurts who reflected it
		epos := closest_wrapped_pos(e, player_center(p^))
		if !rl.CheckCollisionCircleRec(epos, e.radius, rect) do continue

		// Surprise: whatever touches the player is thrown back, no damage taken.
		if p.surprise_ticks > 0 {
			reflect_enemy(g, &e, p, index, epos)
			continue
		}

		// A reflected missile hitting the *other* player.
		if e.reflect_ticks > 0 {
			e.active = false
			hurt_player(g, p, e.damage)
			spawn_burst(g, e.pos, e.color, 8, 150, 3)
			if p.dead do return
			continue
		}

		switch e.kind {
		case .Boss:
			// The boss isn't consumed: it hurts, then gets knocked back.
			if e.hit_cd <= 0 {
				e.hit_cd = BOSS_HIT_COOLDOWN
				e.dash_t = 0
				hurt_player(g, p, e.damage)
				offset := epos - player_center(p^)
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
		case .Normal, .Runner, .Big, .Minion, .Asteroid:
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
			if !rl.CheckCollisionCircles(closest_wrapped_pos(e, a.pos), e.radius, a.pos, a.radius) do continue

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

// --- Asteroids ---

// Straight-line rock from just outside a random edge, aimed at a random point
// of the arena (it never tracks the players).
spawn_asteroid_at_edge :: proc(g: ^Game) {
	e := spawn_enemy_at(g, .Asteroid, {})
	if e == nil do return
	e.pos = edge_spawn_position(e.radius)
	aim := [2]f32{rand.float32_range(SCREEN_W * 0.15, SCREEN_W * 0.85), rand.float32_range(SCREEN_H * 0.15, SCREEN_H * 0.85)}
	e.heading = linalg.normalize0(aim - e.pos)
	e.angle = rand.float32_range(0, 2 * math.PI)
}

// Belt asteroid: sheds off the belt ring of a body that is on the map, drifting
// outward and sideways. Never appears right next to a living player.
spawn_asteroid_from_belt :: proc(g: ^Game, body_pos: [2]f32, ring_radius: f32) {
	for _ in 0 ..< 8 {
		ang := rand.float32_range(0, 2 * math.PI)
		out := [2]f32{math.cos(ang), math.sin(ang)}
		pos := body_pos + out * ring_radius
		if pos.x < 10 || pos.x > SCREEN_W - 10 || pos.y < 10 || pos.y > SCREEN_H - 10 do continue

		_, dist, found := nearest_player(g, pos)
		if found && dist < ASTEROID_SAFE_DIST do continue

		e := spawn_enemy_at(g, .Asteroid, pos)
		if e == nil do return
		sign: f32 = 1 if rand.int31_max(2) == 0 else -1
		tangent := [2]f32{-out.y, out.x} * sign
		e.heading = linalg.normalize0(tangent * 0.8 + out * 0.6)
		e.angle = rand.float32_range(0, 2 * math.PI)
		return
	}
	spawn_asteroid_at_edge(g) // the ring is mostly off-screen or crowded: fall back to the edge
}
