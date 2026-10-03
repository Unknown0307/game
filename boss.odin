package main

import "core:math"
import "core:math/linalg"
import "core:math/rand"
import rl "vendor:raylib"

// =============================================================================
// boss.odin - boss spawning and the every-10th-level repel/summon behaviour.
//
//  * A boss spawns on every 5th level (see level_params).
//  * On every 10th level the boss also gets an ability:
//      - if a player is inside BOSS_REPEL_RADIUS it charges (telegraphed ring,
//        boss stands still) and then repels the players away from it;
//      - if BOTH players are outside that radius it summons either a pair of
//        Runners aimed at the nearest player, or one slow Sticky bomb.
// =============================================================================

BOSS_PURPLE :: rl.Color{200, 90, 255, 255}

spawn_boss :: proc(g: ^Game) {
	e := spawn_enemy_at_edge(g, .Boss)
	if e == nil do return
	g.boss_warn = 2.5
	add_shake(g, 10)
}

any_player_in_radius :: proc(g: ^Game, center: [2]f32, radius: f32) -> bool {
	for p in g.players {
		if p.dead do continue
		if linalg.length(player_center(p) - center) <= radius do return true
	}
	return false
}

// Returns true while the boss should hold still (charging its repel wave).
update_boss_ai :: proc(g: ^Game, e: ^Enemy, dt: f32) -> (hold_position: bool) {
	if e.repel_visual > 0 do e.repel_visual = max(0, e.repel_visual - dt)
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

	if any_player_in_radius(g, e.pos, BOSS_REPEL_RADIUS) {
		if e.repel_cd <= 0 {
			e.charge = BOSS_REPEL_CHARGE
			spawn_ring(g, e.pos, BOSS_PURPLE, 24, 120, 0.4, 3)
		}
		return false
	}

	// Both players are away from the repel radius: send minions their way.
	_, _, found := nearest_player(g, e.pos)
	if found && e.summon_cd <= 0 {
		e.summon_cd = g.params.boss_summon_cd
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
		offset := player_center(p) - e.pos
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
	dir := linalg.normalize(target - e.pos)

	if rand.float32() < BOSS_BOMB_CHANCE {
		// "Bomb" = the slow Sticky enemy.
		spawn_enemy_at(g, .Sticky, e.pos + dir * (e.radius + 12))
	} else {
		for i in 0 ..< BOSS_SUMMON_RUNNERS {
			spread := (f32(i) - f32(BOSS_SUMMON_RUNNERS - 1) * 0.5) * 0.35
			d := rotate_vec(dir, spread)
			r := spawn_enemy_at(g, .Runner, e.pos + d * (e.radius + 10))
			if r != nil do r.heading = d
		}
	}
	spawn_burst(g, e.pos, BOSS_PURPLE, 22, 220, 3)
	add_shake(g, 3)
}
