package main

import "core:math"
import "core:math/linalg"
import "core:math/rand"
import rl "vendor:raylib"

// =============================================================================
// enemy.odin - enemy spawning, steering helpers, the update loop, collisions and kills.
// Per-type behaviour is registered in enemy_defs.odin; boss-only behaviour lives in boss.odin.
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
		if e.active && enemy_def(e.kind).is_boss do n += 1
	}
	return n
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
	for m in g.minions { // the players' minions are targets too
		if !m.exists || !m.alive do continue
		d := linalg.length(wrap_delta(from, m.pos) if wrap else m.pos - from)
		if d < dist {
			dist, target, found = d, m.pos, true
		}
	}
	return
}

// Bosses wrap around the screen, so they exist at up to 9 positions. This returns
// the copy of the boss position closest to `point` (other enemies: just pos).
closest_wrapped_pos :: proc(e: Enemy, point: [2]f32) -> [2]f32 {
	if !enemy_def(e.kind).wraps_screen do return e.pos
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

// Seamless screen wrap (EnemyDef.wraps_screen): crossing an edge re-enters on the other side.
wrap_enemy :: proc(e: ^Enemy) -> bool {
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
	move := enemy_def(e.kind).move
	if move != nil do move(g, e, dt)
}

outside_play_area :: proc(pos: [2]f32, margin: f32) -> bool {
	return pos.x < -margin || pos.x > SCREEN_W + margin || pos.y < -margin || pos.y > SCREEN_H + margin
}

update_enemies :: proc(g: ^Game, dt: f32) {
	for &e in g.enemies {
		if !e.active do continue
		def := enemy_def(e.kind)
		if e.flash > 0  do e.flash -= dt

		// Frozen (Freeze skill): no steering, knock-back, weapons or culling - just a few ice sparkles.
		if g.freeze_ticks > 0 {
			if rand.float32() < 0.012 {
				spawn_particle(g, e.pos + rand_vec2() * e.radius * 0.8, {0, -14}, rl.Color{170, 220, 255, 255}, 0.5, 2.5)
			}
			continue
		}
		if e.hit_cd > 0 do e.hit_cd -= dt

		// Parked enemies (a stuck sticky bomb) stay exactly where they are.
		if enemy_inert(e) {
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
		if def.ai != nil do hold = def.ai(g, &e, dt)
		if !hold do move_enemy(g, &e, dt)

		if def.wraps_screen {
			before := e.pos
			if wrap_enemy(&e) {
				// Warp flash on both sides of the border.
				spawn_burst(g, before, def.wrap_color, 14, 200, 3)
				spawn_burst(g, e.pos, def.wrap_color, 14, 200, 3)
			}
		}

		if def.trail != nil do def.trail(g, e)

		// Missiles, drones and rocks that flew far off-screen would otherwise live forever
		// and slowly fill the enemy pool.
		if def.cull_offscreen && outside_play_area(e.pos, RUNNER_CULL_MARGIN) {
			e.active = false
		}
	}
}

// --- Killing ---

kill_enemy :: proc(g: ^Game, e: ^Enemy, killer: ^Player) {
	def := enemy_def(e.kind)
	e.active = false
	killer.kill_count += 1
	killer.score += e.points

	add_float(g, e.pos, e.points, def.score_float)
	spawn_burst(g, e.pos, e.color, 10 + int(e.radius), 220, 3)

	// Type-specific rewards / effects (default: coin + status + skill rolls).
	on_death := def.on_death
	if on_death == nil do on_death = death_default
	on_death(g, e)
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
	for &m in g.minions {
		if !m.exists || !m.alive do continue
		if rl.CheckCollisionCircles(center, STICKY_EXPLOSION_RADIUS, m.pos, MINION_RADIUS) {
			hurt_minion(g, &m, e.damage)
		}
	}
	spawn_burst(g, center, rl.Color{255, 70, 220, 255}, 42, 250, 4)
	spawn_burst(g, center, rl.Color{255, 220, 120, 255}, 18, 180, 3)
	add_shake(g, 8)
	e.active = false
}

// Fixed 60 Hz tick for every enemy that has a `tick` hook (fuses and the like).
update_enemy_ticks :: proc(g: ^Game) {
	for &e in g.enemies {
		if !e.active do continue
		tick := enemy_def(e.kind).tick
		if tick != nil do tick(g, &e)
	}
}

enemy_hits_player :: proc(g: ^Game, p: ^Player, index: i32) {
	if p.dead || p.invis_ticks > 0 do return // invisible: everything passes through
	if g.freeze_ticks > 0 do return           // frozen enemies are harmless
	rect := player_rect(p^)

	for &e in g.enemies {
		if !e.active do continue
		if enemy_inert(e) do continue
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

		enemy_contact(g, &e, p, epos)

		if p.dead do return
	}
}

// Enemies target allies too: contact damages the ally (a boss kills it outright).
enemies_hit_allies :: proc(g: ^Game) {
	if g.freeze_ticks > 0 do return
	for &e in g.enemies {
		if !e.active do continue
		for &a in g.allies {
			if !a.active do continue
			if !rl.CheckCollisionCircles(closest_wrapped_pos(e, a.pos), e.radius, a.pos, a.radius) do continue

			if enemy_def(e.kind).smashes_allies {
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
