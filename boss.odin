package main

import "core:math"
import "core:math/linalg"
import "core:math/rand"
import rl "vendor:raylib"

// =============================================================================
// boss.odin - the boss (space whale or mothership): spawning and the repel/summon behaviour.
//
//  * A boss spawns on every 5th level (see level_params).
//  * Every boss has abilities (also a lunge and an enrage phase below 50% hp):
//      - if a player is inside BOSS_REPEL_RADIUS it charges (telegraphed ring,
//        boss stands still) and then repels the players away from it;
//      - if BOTH players are outside that radius it summons baby whales
//        (Minions) that swim toward the nearest player.
//  * The boss wraps around the screen borders, like the players do.
// =============================================================================

BOSS_PURPLE :: rl.Color{200, 90, 255, 255}

spawn_boss :: proc(g: ^Game) {
	e := spawn_enemy_at(g, .Boss, {})
	if e == nil do return
	// Start just *inside* a random edge: the boss wraps, so it must not begin
	// outside the screen (it would be teleported straight away).
	e.pos = edge_spawn_position(-12)
	e.angle = math.atan2(f32(SCREEN_H) * 0.5 - e.pos.y, f32(SCREEN_W) * 0.5 - e.pos.x)

	// Half the bosses are space whales (whale minions), half are motherships
	// (drone minions, bullets + raygun - see gunfire.odin).
	if rand.float32() < MOTHERSHIP_CHANCE {
		e.skin = .Mothership
		e.color = rl.Color{120, 90, 235, 255}
		e.gun_ticks = MOTHERSHIP_BULLET_FIRST_TICKS
		e.ray_cd = MOTHERSHIP_RAY_FIRST_TICKS
	}
	g.boss_warn = 2.5
	add_shake(g, 10)
}

any_player_in_radius :: proc(g: ^Game, e: Enemy, radius: f32) -> bool {
	for p in g.players {
		if p.dead do continue
		pc := player_center(p)
		if linalg.length(closest_wrapped_pos(e, pc) - pc) <= radius do return true
	}
	return false
}

boss_enrage :: proc(g: ^Game, e: ^Enemy) {
	e.enraged = true
	e.speed = min(e.speed * BOSS_ENRAGE_SPEED, PLAYER_MAX_SPEED * BOSS_ENRAGE_SPEED_CAP)
	e.repel_cd = min(e.repel_cd, 0.5)
	e.summon_cd = 0
	spawn_ring(g, e.pos, rl.Color{255, 60, 60, 255}, 60, 560, 0.6, 4)
	spawn_burst(g, e.pos, rl.Color{255, 120, 80, 255}, 60, 380, 5)
	add_shake(g, 16)
}

// Returns true while the boss should hold still or is lunging (normal chasing is skipped).
update_boss_ai :: proc(g: ^Game, e: ^Enemy, dt: f32) -> (hold_position: bool) {
	if e.repel_visual > 0 do e.repel_visual = max(0, e.repel_visual - dt)

	// A mothership stands still while it aims and fires the raygun.
	if e.ray_charge > 0 || e.ray_ticks > 0 do return true

	if !e.enraged && f32(e.hp) <= f32(e.max_hp) * BOSS_ENRAGE_FRACTION {
		boss_enrage(g, e)
	}

	// --- Lunge: aim (telegraph), then rocket forward in a straight line. ---
	if e.dash_windup > 0 {
		target, _, found := nearest_player(g, e.pos)
		if found {
			d := wrap_delta(e.pos, target)
			if linalg.length(d) > 0.001 {
				e.dash_dir = linalg.normalize(d)
				e.angle = math.atan2(e.dash_dir.y, e.dash_dir.x)
			}
		}
		e.dash_windup -= dt
		if e.dash_windup <= 0 {
			e.dash_windup = 0
			e.dash_t = BOSS_DASH_TIME
			add_shake(g, 7)
			spawn_burst(g, e.pos, rl.Color{255, 90, 200, 255}, 24, 320, 4)
		}
		return true
	}
	if e.dash_t > 0 {
		e.dash_t -= dt
		e.pos += e.dash_dir * BOSS_DASH_SPEED * dt
		e.angle = math.atan2(e.dash_dir.y, e.dash_dir.x)
		for _ in 0 ..< 3 {
			j := [2]f32{rand_signed(), rand_signed()}
			spawn_particle(g, e.pos + j * e.radius * 0.7, -e.dash_dir * 140 + j * 60, rl.Color{255, 80, 120, 255}, 0.4, 6)
		}
		if e.dash_t <= 0 {
			e.dash_t = 0
			e.dash_cd = BOSS_DASH_COOLDOWN * (0.65 if e.enraged else 1.0)
		}
		return true
	}
	if e.dash_cd > 0 do e.dash_cd -= dt

	if !e.can_repel do return false

	if e.repel_cd > 0  do e.repel_cd  -= dt
	if e.summon_cd > 0 do e.summon_cd -= dt

	// Telegraph phase: stand still, then fire.
	if e.charge > 0 {
		e.charge -= dt
		if e.charge <= 0 {
			e.charge = 0
			boss_fire_repel(g, e)
		}
		return true
	}

	// Start a lunge when a player is in range and the repel isn't about to go off.
	if e.dash_cd <= 0 {
		_, dist, found := nearest_player(g, e.pos)
		if found && dist <= BOSS_DASH_RANGE {
			e.dash_windup = BOSS_DASH_WINDUP * (0.7 if e.enraged else 1.0)
			spawn_ring(g, e.pos, rl.Color{255, 70, 70, 255}, 20, 140, 0.4, 3)
			return true
		}
	}

	if any_player_in_radius(g, e^, BOSS_REPEL_RADIUS) {
		if e.repel_cd <= 0 {
			e.charge = BOSS_REPEL_CHARGE
			spawn_ring(g, e.pos, BOSS_PURPLE, 24, 120, 0.4, 3)
		}
		return false
	}

	// Both players are away from the repel radius: send minions their way.
	_, _, found := nearest_player(g, e.pos)
	if found && e.summon_cd <= 0 && g.params.boss_summons {
		e.summon_cd = g.params.boss_summon_cd * (0.6 if e.enraged else 1.0)
		boss_summon(g, e)
	}
	return false
}

boss_fire_repel :: proc(g: ^Game, e: ^Enemy) {
	e.repel_cd = BOSS_REPEL_COOLDOWN
	e.repel_visual = BOSS_REPEL_VISUAL_TIME
	add_shake(g, 9)
	spawn_ring(g, e.pos, BOSS_PURPLE, 48, 520, 0.4, 4)

	for &p in g.players {
		if p.dead do continue
		offset := player_center(p) - closest_wrapped_pos(e^, player_center(p))
		dist := linalg.length(offset)
		if dist > BOSS_REPEL_RADIUS do continue

		dir := [2]f32{1, 0}
		if dist > 0.001 {
			dir = offset / dist
		} else {
			ang := rand.float32_range(0, 2 * math.PI)
			dir = {math.cos(ang), math.sin(ang)}
		}
		// Closer players are pushed harder.
		strength := BOSS_REPEL_FORCE * (1.0 - 0.4 * dist / BOSS_REPEL_RADIUS)
		p.knock = dir * strength
		spawn_burst(g, player_center(p), BOSS_PURPLE, 14, 200, 3)
	}
}

boss_summon :: proc(g: ^Game, e: ^Enemy) {
	target, _, found := nearest_player(g, e.pos)
	if !found do return
	delta := wrap_delta(e.pos, target)
	if linalg.length(delta) < 0.001 do return
	dir := linalg.normalize(delta)

	// A pod of baby whales fanned out toward the nearest player.
	count := BOSS_SUMMON_MINIONS + (2 if e.enraged else 0)
	for i in 0 ..< count {
		spread := (f32(i) - f32(count - 1) * 0.5) * 0.45
		d := rotate_vec(dir, spread)
		m := spawn_enemy_at(g, .Minion, e.pos + d * (e.radius + 10))
		if m != nil {
			m.heading = d
			m.angle = math.atan2(d.y, d.x)
			m.skin = e.skin // whale boss -> whale minions, mothership -> drones
			if e.skin == .Mothership do m.color = rl.Color{110, 220, 255, 255}
		}
	}
	spawn_burst(g, e.pos, BOSS_PURPLE, 22, 220, 3)
	add_shake(g, 3)
}
