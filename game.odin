package main

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

// =============================================================================
// game.odin - game lifecycle: init, phases, level progression, per-frame update.
// Each phase has its own small proc so adding a new phase is one new case.
// =============================================================================

game_init :: proc(g: ^Game) {
	g.shaders  = load_shaders()
	g.settings = Settings{shake = .Full}
	reset_run(g)
	open_menu(g) // the game starts on the title screen
}

game_shutdown :: proc(g: ^Game) {
	unload_shaders(g.shaders)
}

// --- Level / run lifecycle ---

set_level :: proc(g: ^Game, level: i32) {
	g.level  = level
	g.params = level_params(level)
	g.style  = level_style(level)
	g.backdrop = make_backdrop(level)
}

reset_level_timers :: proc(g: ^Game) {
	g.spawn_timer = 0
	g.coin_timer  = 1
	g.ally_timer  = 6
	g.asteroid_timer = 0
	g.tick_accum  = 0
	g.boss_warn   = 0
}

// Clears everything that belongs to a single level (enemies, pickups, fx).
reset_level_world :: proc(g: ^Game) {
	for &e in g.enemies     do e.active = false
	for &c in g.coins       do c.active = false
	for &a in g.allies      do a.active = false
	for &b in g.bullets     do b.active = false
	for &k in g.enh_pickups do k.active = false
	for &k in g.skill_pickups do k.active = false
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
	g.suck_t       = 0
	g.spit_t       = 0
	g.menu_page    = .Root
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
	for &b in g.bullets do b.active = false
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
	feed_black_hole(g, dt, 0.35 * g.portal_open)
	collect_enhancements(g)
	collect_skill_pickups(g)
	if all_surviving_players_in_portal(g) do begin_sucking(g)
}

update_game_over :: proc(g: ^Game) {
	if rl.IsKeyPressed(.SPACE) do reset_run(g)
	if rl.IsKeyPressed(.ESCAPE) {
		reset_run(g)
		open_menu(g)
	}
}

// --- Black hole transition ---
//
// Sucking: the black hole swells and feeds; both ships spiral into it while the
//          stars and dust around it are dragged into the whirl.
// Spit:    the next level is loaded the moment the ships have vanished, then the
//          hole flares, shrinks away and flings the ships back out to their
//          starting positions.

// Pulls a stream of dust/sparks toward the hole. `rate` 0..1 (1 = busiest).
feed_black_hole :: proc(g: ^Game, dt: f32, rate: f32) {
	pc := portal_center()
	n := rate * 90.0 * dt // particles this frame
	count := int(n)
	if rand.float32() < n - f32(count) do count += 1
	for _ in 0 ..< count {
		a := rand.float32_range(0, 2 * math.PI)
		r := rand.float32_range(150, 380)
		d := [2]f32{math.cos(a), math.sin(a)}
		tangent := [2]f32{-d.y, d.x}
		col := g.style.accent2
		switch rand.int31_max(3) {
		case 0: col = rl.Color{255, 215, 160, 255}
		case 1: col = g.style.accent
		}
		spawn_particle(g, pc + d * r, tangent * 90, col, 1.4, rand.float32_range(1.5, 3.0))
	}
}

begin_sucking :: proc(g: ^Game) {
	g.phase  = .Sucking
	g.suck_t = 0
	add_shake(g, 4)

	// Ring of sparks that rushes inward.
	pc := portal_center()
	for i in 0 ..< 40 {
		a := f32(i) / 40.0 * 2.0 * math.PI
		d := [2]f32{math.cos(a), math.sin(a)}
		spawn_particle(g, pc + d * 220, -d * 320, g.style.accent2, 0.9, 3.5)
	}
}

update_sucking :: proc(g: ^Game, dt: f32) {
	g.suck_t += dt
	u := clamp(g.suck_t / SUCK_TIME, 0, 1)
	pc := portal_center()

	pull_rate := 1.0 + 4.5 * u   // how fast ships fall toward the centre
	spin      := 2.5 + 12.0 * u  // how fast they orbit while falling
	for &p in g.players {
		if p.dead do continue
		d := player_center(p) - pc
		d = rotate_vec(d, spin * dt) * math.exp(-pull_rate * dt)
		p.pos          = pc + d - p.size * 0.5
		p.angle       += (4.0 + 20.0 * u) * dt
		p.target_angle = p.angle
		p.thrust       = 1
		p.trail_n      = 0

		// Fade out as the ship crosses the horizon (smoothstep over 15%..85%).
		k := clamp((u - 0.15) / 0.70, 0, 1)
		p.shrink = k * k * (3.0 - 2.0 * k)

		// Torn-off glow streaming into the hole.
		if rand.float32() < 0.7 {
			spawn_particle(g, player_center(p), -d * 1.5 + rotate_vec(d, 1.57) * 0.8, p.color, 0.35, 3)
		}
	}

	feed_black_hole(g, dt, 0.6 + 0.8 * u)
	add_shake(g, 1.5 + 4.0 * u)

	if g.suck_t >= SUCK_TIME {
		advance_level(g) // loads the next level while the ships are gone
		begin_spit(g)
	}
}

begin_spit :: proc(g: ^Game) {
	g.spit_t = SPIT_TIME
	g.suck_t = 0
	pc := portal_center()
	for &p in g.players {
		p.pos          = pc - p.size * 0.5
		p.shrink       = 1
		p.angle        = 0
		p.target_angle = 0
		p.thrust       = 1
		p.trail_n      = 0
	}
	spawn_ring(g, pc, g.style.accent, 56, 520, 0.7, 3.5)
	spawn_ring(g, pc, rl.WHITE, 28, 340, 0.5, 2.5)
	spawn_burst(g, pc, g.style.accent2, 50, 380, 3)
	add_shake(g, 9)
}

update_spit :: proc(g: ^Game, dt: f32) {
	g.spit_t = max(0, g.spit_t - dt)
	u := 1.0 - g.spit_t / SPIT_TIME // 0 -> 1
	e := 1.0 - (1.0 - u) * (1.0 - u) * (1.0 - u) // ease-out: shot out fast, then settles
	pc := portal_center()

	for &p in g.players {
		start_c := p.start_pos + p.size * 0.5
		p.pos          = pc + (start_c - pc) * e - p.size * 0.5
		p.shrink       = 1.0 - clamp(u * 5.0, 0, 1)
		p.angle        = -(1.0 - e) * 12.0          // tumbles out, then straightens up
		p.target_angle = 0
		p.thrust       = 1
		p.trail_n      = 0
		if u < 0.85 {
			spawn_particle(g, player_center(p), rand_vec2() * 40, p.color, 0.4, 3.5)
		}
	}

	if g.spit_t <= 0 {
		for &p in g.players {
			p.pos          = p.start_pos
			p.shrink       = 0
			p.angle        = 0
			p.target_angle = 0
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

	// Asteroids: a trickle normally, a flood while an asteroid belt drifts across the map.
	rate: f32 = ASTEROID_RATE_IDLE
	belt_pos, belt_r, has_belt := active_belt(g)
	if has_belt do rate = ASTEROID_RATE_BELT
	g.asteroid_timer += dt
	for g.asteroid_timer >= 1.0 / rate {
		g.asteroid_timer -= 1.0 / rate
		if has_belt {
			spawn_asteroid_from_belt(g, belt_pos, belt_r)
		} else {
			spawn_asteroid_at_edge(g)
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
		for &p in g.players {
			tick_shields(&p)
			tick_player_skills(&p)
		}
		tick_reflected_enemies(g)
		update_sticky_ticks(g)
		update_enemy_guns(g)
	}
}

resolve_collisions :: proc(g: ^Game) {
	for &p, i in g.players {
		enemy_hits_player(g, &p, i32(i))
	}
	enemies_hit_allies(g)
	for &p in g.players {
		collect_coins(g, &p)
		heal_from_allies(g, &p)
	}
	collect_enhancements(g)
	collect_skill_pickups(g)
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
	handle_player_actions(g)
	update_spawners(g, dt)
	update_ticks(g, dt)
	update_enemies(g, dt)
	update_bullets(g, dt)
	resolve_collisions(g)
	check_level_progress(g)
}

// --- Main per-frame update ---

game_update :: proc(g: ^Game, dt: f32) {
	// Menus and the pause screen freeze the whole simulation.
	if g.phase == .Menu || g.phase == .Paused {
		if g.phase == .Menu do g.backdrop.age += dt // the title screen drifts too
		update_menu(g)
		return
	}
	if should_pause(g) {
		pause_game(g)
		return
	}

	g.backdrop.age += dt
	for &p in g.players do update_player_timers(&p, dt)
	if g.boss_warn > 0 do g.boss_warn = max(0, g.boss_warn - dt)

	// Players can move during preparation, combat and the portal transition.
	// (not while being sucked into / spat out of the portal)
	if g.phase != .GameOver && g.phase != .Sucking && g.spit_t <= 0 {
		for &p in g.players do update_player_movement(g, &p, dt)
	}

	switch g.phase {
	case .Menu, .Paused: // handled above
	case .Countdown:     update_countdown(g, dt)
	case .Playing:       update_playing(g, dt)
	case .LevelComplete: update_level_complete(g, dt)
	case .Sucking:       update_sucking(g, dt)
	case .GameOver:      update_game_over(g)
	}
	if g.spit_t > 0 do update_spit(g, dt)

	// Pickups/FX keep animating during countdown and level transitions.
	update_pickups(g, dt)
	update_fx(g, dt)
}
