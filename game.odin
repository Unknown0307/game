package main

import "core:math/rand"
import rl "vendor:raylib"

// =============================================================================
// game.odin - game lifecycle: init, phases, level progression, per-frame update.
// Each phase has its own small proc so adding a new phase is one new case.
// =============================================================================

game_init :: proc(g: ^Game) {
	g.shaders = load_shaders()
	reset_run(g)
}

game_shutdown :: proc(g: ^Game) {
	unload_shaders(g.shaders)
}

// --- Level / run lifecycle ---

set_level :: proc(g: ^Game, level: i32) {
	g.level  = level
	g.params = level_params(level)
	g.style  = level_style(level)
}

reset_level_timers :: proc(g: ^Game) {
	g.spawn_timer = 0
	g.coin_timer  = 1
	g.ally_timer  = 6
	g.tick_accum  = 0
	g.boss_warn   = 0
}

// Clears everything that belongs to a single level (enemies, pickups, fx).
reset_level_world :: proc(g: ^Game) {
	for &e in g.enemies     do e.active = false
	for &c in g.coins       do c.active = false
	for &a in g.allies      do a.active = false
	for &k in g.enh_pickups do k.active = false
	clear_fx(g)
}

// Full restart (also used for the very first run).
reset_run :: proc(g: ^Game) {
	for i in 0 ..< PLAYER_COUNT do g.players[i] = make_player(i)
	reset_level_world(g)
	reset_level_timers(g)
	set_level(g, 1)
	g.survive_time = 0
	g.portal_open  = 0
	g.countdown    = LEVEL_COUNTDOWN
	g.phase        = .Countdown
}

advance_level :: proc(g: ^Game) {
	set_level(g, g.level + 1)

	for &p in g.players {
		// A player who died in the finished level is resurrected now.
		if p.dead do revive_player(&p)
		p.pos   = p.start_pos
		p.knock = {}
	}

	reset_level_world(g)
	reset_level_timers(g)
	g.portal_open = 0
	g.countdown   = LEVEL_COUNTDOWN
	g.phase       = .Countdown
}

begin_playing :: proc(g: ^Game) {
	g.countdown = 0
	g.phase     = .Playing
	reset_level_timers(g)
	if g.params.is_boss_level do spawn_boss(g)
}

begin_level_complete :: proc(g: ^Game) {
	g.phase       = .LevelComplete
	g.portal_open = 0
	g.boss_warn   = 0
	// The arena is now safe. Enhancement pickups are kept so they can still be
	// collected before entering the portal.
	for &e in g.enemies do e.active = false
	for &c in g.coins   do c.active = false
	for &a in g.allies  do a.active = false
}

// --- Portal helpers ---

portal_center :: proc() -> [2]f32 {
	return {f32(SCREEN_W) * 0.5, f32(SCREEN_H) * 0.5}
}

portal_player_inside :: proc(p: Player) -> bool {
	if p.dead do return false
	c := player_center(p)
	pc := portal_center()
	d := c - pc
	return d.x * d.x + d.y * d.y <= PORTAL_RADIUS * PORTAL_RADIUS
}

// Both players must be inside when both are alive. If one died, the survivor
// alone can enter.
all_surviving_players_in_portal :: proc(g: ^Game) -> bool {
	alive, inside := 0, 0
	for p in g.players {
		if p.dead do continue
		alive += 1
		if portal_player_inside(p) do inside += 1
	}
	return alive > 0 && inside == alive
}

// --- Phase updates ---

update_countdown :: proc(g: ^Game, dt: f32) {
	g.countdown -= dt
	if g.countdown <= 0 do begin_playing(g)
}

update_level_complete :: proc(g: ^Game, dt: f32) {
	// The portal opens visually, but the level only advances when players
	// physically enter it.
	g.portal_open = min(1.0, g.portal_open + dt / PORTAL_OPEN_TIME)
	collect_enhancements(g)
	if all_surviving_players_in_portal(g) do advance_level(g)
}

update_game_over :: proc(g: ^Game) {
	if rl.IsKeyPressed(.SPACE) do reset_run(g)
}

handle_abilities :: proc(g: ^Game) {
	for &p in g.players {
		if !p.dead && rl.IsKeyPressed(p.ability_key) && p.ability_cd <= 0 {
			fire_blast(g, &p)
		}
	}
}

update_spawners :: proc(g: ^Game, dt: f32) {
	// Regular enemies. Subtracting the interval (instead of resetting to 0)
	// keeps the spawn rate exact even when a frame runs long.
	g.spawn_timer += dt
	for g.spawn_timer >= g.params.spawn_interval {
		g.spawn_timer -= g.params.spawn_interval
		spawn_enemy_at_edge(g, pick_enemy_kind(g.params))
	}

	g.coin_timer -= dt
	if g.coin_timer <= 0 {
		g.coin_timer = rand.float32_range(1.0, 2.0)
		if count_active_coins(g) < 10 {
			spawn_coin_at(g, {rand.float32_range(40, SCREEN_W - 40), rand.float32_range(120, SCREEN_H - 40)})
		}
	}

	g.ally_timer -= dt
	if g.ally_timer <= 0 {
		g.ally_timer = rand.float32_range(9.0, 15.0)
		if count_active_allies(g) < 3 do spawn_ally(g)
	}
}

// Fixed 60 Hz tick: shield lifetimes and sticky-bomb fuses are tick based.
update_ticks :: proc(g: ^Game, dt: f32) {
	g.tick_accum = min(g.tick_accum + dt, 0.25)
	for g.tick_accum >= TICK_DT {
		g.tick_accum -= TICK_DT
		for &p in g.players do tick_shields(&p)
		update_sticky_ticks(g)
	}
}

resolve_collisions :: proc(g: ^Game) {
	for &p in g.players {
		enemy_hits_player(g, &p)
	}
	enemies_hit_allies(g)
	for &p in g.players {
		collect_coins(g, &p)
		heal_from_allies(g, &p)
	}
	collect_enhancements(g)
}

check_level_progress :: proc(g: ^Game) {
	if all_players_dead(g) {
		g.phase = .GameOver
		return
	}
	// On boss levels the boss must be defeated before the portal opens.
	reached_goal := total_score(g) >= level_goal_total(g.level)
	if reached_goal && count_bosses(g) == 0 {
		begin_level_complete(g)
	}
}

update_playing :: proc(g: ^Game, dt: f32) {
	g.survive_time += dt
	handle_abilities(g)
	update_spawners(g, dt)
	update_ticks(g, dt)
	update_enemies(g, dt)
	resolve_collisions(g)
	check_level_progress(g)
}

// --- Main per-frame update ---

game_update :: proc(g: ^Game, dt: f32) {
	for &p in g.players do update_player_timers(&p, dt)
	if g.boss_warn > 0 do g.boss_warn = max(0, g.boss_warn - dt)

	// Players can move during preparation, combat and the portal transition.
	if g.phase != .GameOver {
		for &p in g.players do update_player_movement(g, &p, dt)
	}

	switch g.phase {
	case .Countdown:     update_countdown(g, dt)
	case .Playing:       update_playing(g, dt)
	case .LevelComplete: update_level_complete(g, dt)
	case .GameOver:      update_game_over(g)
	}

	// Pickups/FX keep animating during countdown and level transitions.
	update_pickups(g, dt)
	update_fx(g, dt)
}
