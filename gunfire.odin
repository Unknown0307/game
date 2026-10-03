package main

import "core:math"
import "core:math/linalg"
import rl "vendor:raylib"

// =============================================================================
// gunfire.odin - weapons of the Big enemy (the cruiser) and the Mothership boss,
// plus flight / collision of every bullet (enemy, reflected and player shots).
//
//  * Gun cruisers fire one bullet every BIG_SHOOT_COOLDOWN_TICKS (20 ticks),
//    alternating between their two turrets, at the nearest player/ally.
//  * Laser cruisers (BIG_LASER_CHANCE of Big spawns) instead switch on a beam
//    for LASER_TICKS (15 ticks). The beam starts at the enemy's centre and is
//    long enough to reach the END OF THE MAP in the direction it faces.
//
// Cooldowns are counted in the fixed 60 Hz ticks (update_ticks in game.odin);
// bullet flight and drawing run per frame.
// =============================================================================

BULLET_COLOR :: rl.Color{255, 130, 70, 255}
LASER_COLOR  :: rl.Color{90, 230, 255, 255}

// Distance from `origin` along `dir` to the edge of the map (the screen rectangle).
distance_to_map_edge :: proc(origin, dir: [2]f32) -> f32 {
	best: f32 = MAP_DIAGONAL
	if dir.x > 0.0001 {
		best = min(best, (f32(SCREEN_W) - origin.x) / dir.x)
	} else if dir.x < -0.0001 {
		best = min(best, (0 - origin.x) / dir.x)
	}
	if dir.y > 0.0001 {
		best = min(best, (f32(SCREEN_H) - origin.y) / dir.y)
	} else if dir.y < -0.0001 {
		best = min(best, (0 - origin.y) / dir.y)
	}
	return max(best, 0)
}

// The cruiser's beam starts at its centre and ends at the map edge it is facing.
laser_length :: proc(e: Enemy) -> f32 {
	dir := [2]f32{math.cos(e.angle), math.sin(e.angle)}
	return max(distance_to_map_edge(e.pos, dir), e.radius * 2.0)
}

angle_gap :: proc(a, b: f32) -> f32 {
	d := b - a
	for d > math.PI  do d -= 2 * math.PI
	for d < -math.PI do d += 2 * math.PI
	return abs(d)
}

spawn_bullet :: proc(g: ^Game, pos, vel: [2]f32) {
	for &b in g.bullets {
		if b.active do continue
		b = Bullet{pos = pos, vel = vel, life = BULLET_LIFETIME, active = true}
		return
	}
}

big_fire_bullet :: proc(g: ^Game, e: ^Enemy, target: [2]f32) {
	side: f32 = 1 if e.gun_flip else -1
	e.gun_flip = !e.gun_flip

	muzzle := epoint(e.pos, e.angle, e.radius, 0.9, side * 0.55)
	delta := target - muzzle
	d := linalg.length(delta)
	if d < 0.001 do return

	spawn_bullet(g, muzzle, delta / d * BULLET_SPEED)
	spawn_burst(g, muzzle, BULLET_COLOR, 4, 90, 2)
}

// One damage pulse of a beam (cruiser laser or mothership raygun): players and
// allies touching it get hurt. Invisible players are ignored.
beam_hit :: proc(g: ^Game, origin, dir: [2]f32, length, half_w: f32, damage: i32, color: rl.Color) {
	n := int(length / 6.0) + 1

	for &p in g.players {
		if p.dead || p.invis_ticks > 0 do continue
		rect := player_rect(p)
		for i in 0 ..= n {
			pt := origin + dir * (length * f32(i) / f32(n))
			if rl.CheckCollisionCircleRec(pt, half_w, rect) {
				hurt_player(g, &p, damage)
				spawn_burst(g, pt, color, 6, 140, 2.5)
				break
			}
		}
	}
	for &a in g.allies {
		if !a.active do continue
		for i in 0 ..= n {
			pt := origin + dir * (length * f32(i) / f32(n))
			if rl.CheckCollisionCircles(pt, half_w, a.pos, a.radius) {
				a.hp -= 1
				a.flash = 0.2
				spawn_burst(g, a.pos, color, 8, 140, 3)
				if a.hp <= 0 {
					a.active = false
					spawn_burst(g, a.pos, rl.LIME, 35, 260, 4)
					add_shake(g, 5)
				}
				break
			}
		}
	}
}

laser_hit :: proc(g: ^Game, e: Enemy) {
	dir := [2]f32{math.cos(e.angle), math.sin(e.angle)}
	beam_hit(g, e.pos, dir, laser_length(e), LASER_WIDTH * 0.5, LASER_DAMAGE, LASER_COLOR)
}

// --- Mothership (boss skin) ---

RAYGUN_COLOR :: rl.Color{255, 70, 150, 255}

ray_origin :: proc(e: Enemy, angle: f32) -> [2]f32 {
	return e.pos + [2]f32{math.cos(angle), math.sin(angle)} * e.radius * 1.1
}

mothership_fire_bullet :: proc(g: ^Game, e: ^Enemy, delta: [2]f32) {
	side: f32 = 1 if e.gun_flip else -1
	e.gun_flip = !e.gun_flip
	k := e.radius * 0.9
	muzzle := epoint(e.pos, e.angle, k, 1.1, side * 0.6)
	d := linalg.normalize0(delta - (muzzle - e.pos))
	if linalg.length(d) < 0.001 do return
	spawn_bullet(g, muzzle, d * BULLET_SPEED)
	spawn_burst(g, muzzle, BULLET_COLOR, 4, 90, 2)
}

// One tick of the mothership: bullet every 40 ticks, raygun every 10 s (600 ticks).
update_mothership :: proc(g: ^Game, e: ^Enemy) {
	target, dist, found := nearest_target(g, e.pos, true)

	// Beam is on: pulse damage, then start the 10 s cooldown.
	if e.ray_ticks > 0 {
		if e.ray_ticks % RAY_HIT_INTERVAL_TICKS == 0 {
			dir := [2]f32{math.cos(e.ray_angle), math.sin(e.ray_angle)}
			beam_hit(g, ray_origin(e^, e.ray_angle), dir, RAY_LENGTH, RAY_WIDTH * 0.5, RAY_DAMAGE, RAYGUN_COLOR)
		}
		e.ray_ticks -= 1
		if e.ray_ticks == 0 do e.ray_cd = MOTHERSHIP_RAY_COOLDOWN_TICKS
		return
	}

	// Charging: stand still, turn toward the target, then lock the aim and fire.
	if e.ray_charge > 0 {
		if found {
			d := wrap_delta(e.pos, target)
			e.angle = turn_toward(e.angle, math.atan2(d.y, d.x), 2.6 * TICK_DT)
		}
		e.ray_charge -= 1
		if e.ray_charge == 0 {
			e.ray_angle = e.angle
			e.ray_ticks = RAY_TICKS
			add_shake(g, 6)
		}
		return
	}

	if e.ray_cd > 0   do e.ray_cd -= 1
	if e.gun_ticks > 0 do e.gun_ticks -= 1
	if !found do return

	delta := wrap_delta(e.pos, target)
	busy := e.dash_t > 0 || e.dash_windup > 0 || e.charge > 0
	if e.ray_cd <= 0 && !busy && dist <= RAY_LENGTH {
		e.ray_charge = RAY_CHARGE_TICKS
		spawn_ring(g, e.pos, RAYGUN_COLOR, 20, 130, 0.4, 3)
	} else if e.gun_ticks <= 0 && dist <= MOTHERSHIP_GUN_RANGE {
		mothership_fire_bullet(g, e, delta)
		e.gun_ticks = MOTHERSHIP_BULLET_COOLDOWN_TICKS
	}
}

// Runs once per 60 Hz tick.
update_enemy_guns :: proc(g: ^Game) {
	for &e in g.enemies {
		if e.active && e.kind == .Boss && e.skin == .Mothership {
			update_mothership(g, &e)
			continue
		}
		if !e.active || e.kind != .Big do continue

		// Beam is on: pulse damage every few ticks, then start the cooldown.
		if e.laser_ticks > 0 {
			if e.laser_ticks % LASER_HIT_INTERVAL_TICKS == 0 do laser_hit(g, e)
			e.laser_ticks -= 1
			if e.laser_ticks == 0 do e.gun_ticks = LASER_COOLDOWN_TICKS
			continue
		}
		if e.gun_ticks > 0 {
			e.gun_ticks -= 1
			continue
		}

		// Ready: never shoot from off-screen, and only when roughly facing the target.
		if outside_play_area(e.pos, 0) do continue
		target, dist, found := nearest_target(g, e.pos)
		if !found do continue
		want := math.atan2(target.y - e.pos.y, target.x - e.pos.x)
		if angle_gap(e.angle, want) > BIG_AIM_TOLERANCE do continue

		if e.laser {
			if dist <= LASER_TRIGGER_RANGE {
				e.laser_ticks = LASER_TICKS
				add_shake(g, 2)
			}
		} else if dist <= BIG_GUN_RANGE {
			big_fire_bullet(g, &e, target)
			e.gun_ticks = BIG_SHOOT_COOLDOWN_TICKS
		}
	}
}

update_bullets :: proc(g: ^Game, dt: f32) {
	for &b in g.bullets {
		if !b.active do continue

		if b.from_player {
			update_player_shot(g, &b, dt)
			continue
		}

		b.pos += b.vel * dt
		b.life -= dt
		if b.life <= 0 || outside_play_area(b.pos, 30) {
			b.active = false
			continue
		}

		turned := false
		for &p, pi in g.players {
			if p.dead || p.invis_ticks > 0 do continue
			if b.reflected && b.owner == i32(pi) do continue // never hurts who reflected it
			if !rl.CheckCollisionCircleRec(b.pos, BULLET_RADIUS, player_rect(p)) do continue

			if p.surprise_ticks > 0 {
				reflect_bullet(g, &b, &p, i32(pi))
				turned = true
			} else {
				hurt_player(g, &p, BULLET_DAMAGE)
				spawn_burst(g, b.pos, BULLET_COLOR, 6, 140, 2.5)
				b.active = false
			}
			break
		}
		if turned || !b.active do continue

		for &a in g.allies {
			if !a.active do continue
			if rl.CheckCollisionCircles(b.pos, BULLET_RADIUS, a.pos, a.radius) {
				a.hp -= BULLET_DAMAGE
				a.flash = 0.2
				spawn_burst(g, b.pos, BULLET_COLOR, 6, 140, 2.5)
				if a.hp <= 0 {
					a.active = false
					spawn_burst(g, a.pos, rl.LIME, 35, 260, 4)
					add_shake(g, 5)
				}
				b.active = false
				break
			}
		}
	}
}

draw_bullets :: proc(g: ^Game) {
	rl.BeginBlendMode(.ADDITIVE)
	for b in g.bullets {
		if !b.active do continue
		d := linalg.normalize0(b.vel)

		if b.from_player && b.rocket {
			col := skill_color(.Rocket)
			flick := 0.7 + 0.3 * math.sin(g.time * 60 + b.pos.x)
			rl.DrawLineEx(b.pos, b.pos - d * 22 * flick, 5, rl.Fade(rl.Color{255, 190, 80, 255}, 0.5))
			draw_glow(b.pos, 16, col, 0.7)
			rl.DrawLineEx(b.pos - d * 6, b.pos + d * 6, 4, rl.Fade(rl.WHITE, 0.95))
			continue
		}

		col := BULLET_COLOR
		if b.from_player || b.reflected do col = g.players[b.owner].color
		if b.from_player {
			rl.DrawLineEx(b.pos, b.pos - d * 16, 3, rl.Fade(col, 0.5))
			draw_glow(b.pos, 10, col, 0.7)
			rl.DrawCircleV(b.pos, PLAYER_BULLET_RADIUS * 0.8, rl.Fade(rl.WHITE, 0.95))
			continue
		}
		rl.DrawLineEx(b.pos, b.pos - d * 14, 3, rl.Fade(col, 0.45))
		draw_glow(b.pos, 12, col, 0.6)
		rl.DrawCircleV(b.pos, BULLET_RADIUS * 0.8, rl.Fade(rl.WHITE, 0.95))
	}
	rl.EndBlendMode()
}

draw_lasers :: proc(g: ^Game) {
	for e in g.enemies {
		if !e.active || e.kind != .Big || e.laser_ticks <= 0 do continue

		dir := [2]f32{math.cos(e.angle), math.sin(e.angle)}
		start := e.pos + dir * e.radius
		end := e.pos + dir * laser_length(e)

		// Snaps open over the first 3 ticks and thins out over the last 4.
		grow := min(1.0, f32(LASER_TICKS - e.laser_ticks + 1) / 3.0)
		fade := min(1.0, f32(e.laser_ticks) / 4.0)
		w := LASER_WIDTH * min(grow, fade) * (0.85 + 0.15 * math.sin(g.time * 90))

		rl.BeginBlendMode(.ADDITIVE)
		rl.DrawLineEx(start, end, w * 2.2, rl.Fade(LASER_COLOR, 0.25))
		rl.DrawLineEx(start, end, w * 1.2, rl.Fade(LASER_COLOR, 0.6))
		rl.DrawLineEx(start, end, w * 0.45, rl.Fade(rl.WHITE, 0.95))
		draw_glow(end, w * 3.0, LASER_COLOR, 0.7)
		rl.DrawCircleV(end, w * 0.7, rl.Fade(rl.WHITE, 0.9))
		rl.EndBlendMode()
	}
}

// Mothership raygun: a thin aiming line while charging, then a fat beam.
draw_rayguns :: proc(g: ^Game) {
	for e in g.enemies {
		if !e.active || e.kind != .Boss || e.skin != .Mothership do continue
		if e.ray_charge <= 0 && e.ray_ticks <= 0 do continue

		if e.ray_ticks > 0 {
			dir := [2]f32{math.cos(e.ray_angle), math.sin(e.ray_angle)}
			start := ray_origin(e, e.ray_angle)
			end := start + dir * RAY_LENGTH
			grow := min(1.0, f32(RAY_TICKS - e.ray_ticks + 1) / 4.0)
			fade := min(1.0, f32(e.ray_ticks) / 6.0)
			w := RAY_WIDTH * min(grow, fade) * (0.88 + 0.12 * math.sin(g.time * 80))

			rl.BeginBlendMode(.ADDITIVE)
			rl.DrawLineEx(start, end, w * 2.0, rl.Fade(RAYGUN_COLOR, 0.25))
			rl.DrawLineEx(start, end, w * 1.2, rl.Fade(RAYGUN_COLOR, 0.65))
			rl.DrawLineEx(start, end, w * 0.45, rl.Fade(rl.WHITE, 0.95))
			draw_glow(start, w * 2.2, RAYGUN_COLOR, 0.8)
			draw_glow(end, w * 2.0, RAYGUN_COLOR, 0.6)
			rl.EndBlendMode()
		} else {
			// Telegraph: the line follows the aim and brightens as the charge fills.
			dir := [2]f32{math.cos(e.angle), math.sin(e.angle)}
			start := ray_origin(e, e.angle)
			k := 1.0 - f32(e.ray_charge) / f32(RAY_CHARGE_TICKS)
			blink := 0.5 + 0.5 * math.sin(g.time * 40)
			rl.BeginBlendMode(.ADDITIVE)
			rl.DrawLineEx(start, start + dir * RAY_LENGTH, 1.5 + 2.5 * k, rl.Fade(RAYGUN_COLOR, 0.15 + 0.35 * k * (0.6 + 0.4 * blink)))
			draw_glow(start, 8 + 22 * k, RAYGUN_COLOR, 0.4 + 0.5 * k)
			rl.EndBlendMode()
		}
	}
}
