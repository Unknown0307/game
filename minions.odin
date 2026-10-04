package main

import "core:math"
import "core:math/linalg"
import rl "vendor:raylib"

// =============================================================================
// minions.odin - the "Minion" enhancement: an allied drone that looks and fights like a
// laser cruiser (see gunfire.odin) and follows its summoner.
//
//  * One minion per Minion enhancement copy (MAX_ENHANCEMENTS per player at most).
//  * Its max health is half of the summoner's max health (so Max health enhancements
//    make it tougher too). It takes damage from enemies, enemy bullets and beams.
//  * When it dies it stays dead for the rest of the level and resurrects with full health
//    at the start of the next one (revive_minions, called from advance_level).
//  * Enemies chase it like they chase players (nearest_target in enemy.odin).
//  * The beam starts at its centre and runs to the end of the map; every pulse damages
//    each enemy it touches (kills are credited to the summoner).
//  * Come Back (skills.odin) rewinds the minions of the player who uses it.
// =============================================================================

clamp_to_arena :: proc(v: [2]f32) -> [2]f32 {
	return {clamp(v.x, 10, f32(SCREEN_W) - 10), clamp(v.y, 10, f32(SCREEN_H) - 10)}
}

// Half of the summoner's max health.
minion_max_hp :: proc(owner: Player) -> i32 {
	return max(1, i32(f32(player_max_health(owner)) * MINION_HEALTH_SHARE))
}

// Where around the summoner this minion hovers (a slow orbit, one phase per minion).
minion_orbit_offset :: proc(t: f32, owner, slot: i32) -> [2]f32 {
	ang := t * 0.9 + f32(slot) * 2.1 + f32(owner) * 1.3
	r := MINION_FOLLOW_DIST + 8 * f32(slot)
	return {math.cos(ang), math.sin(ang)} * r
}

spawn_player_minion :: proc(g: ^Game, owner: i32) {
	p := &g.players[owner]
	slot: i32 = 0
	for m in g.minions {
		if m.exists && m.owner == owner do slot += 1
	}
	if slot >= MAX_ENHANCEMENTS do return

	for &m in g.minions {
		if m.exists do continue
		m = PlayerMinion{
			exists    = true,
			alive     = true,
			owner     = owner,
			slot      = slot,
			pos       = clamp_to_arena(player_center(p^) + minion_orbit_offset(g.time, owner, slot)),
			angle     = p.angle,
			max_hp    = minion_max_hp(p^),
			gun_ticks = LASER_COOLDOWN_TICKS,
		}
		spawn_burst(g, m.pos, p.color, 30, 220, 3.5)
		spawn_ring(g, m.pos, rl.WHITE, 20, 180, 0.4, 3)
		return
	}
}

// Dead minions resurrect (full health) next to their summoner at the start of the next level.
revive_minions :: proc(g: ^Game) {
	for &m in g.minions {
		if !m.exists do continue
		owner := g.players[m.owner]
		if !m.alive {
			m.alive = true
			m.taken = 0
			spawn_burst(g, player_center(owner), owner.color, 24, 200, 3)
		}
		m.pos = player_center(owner)
		m.laser_ticks = 0
		m.gun_ticks = LASER_COOLDOWN_TICKS
		m.hit_cd = 0
		m.shrink = owner.shrink
	}
}

hurt_minion :: proc(g: ^Game, m: ^PlayerMinion, amount: i32) {
	if !m.alive || amount <= 0 do return
	col := g.players[m.owner].color
	m.taken += amount
	m.flash = 0.25
	spawn_burst(g, m.pos, rl.RED, 6, 140, 2.5)
	if m.taken >= m.max_hp {
		m.taken = m.max_hp
		m.alive = false
		m.laser_ticks = 0
		spawn_burst(g, m.pos, col, 40, 280, 4)
		spawn_burst(g, m.pos, rl.WHITE, 20, 200, 3)
		add_shake(g, 5)
	}
}

// Per frame: follow the summoner, face the nearest enemy.
update_player_minions :: proc(g: ^Game, dt: f32) {
	swallowed := g.phase == .Sucking || g.spit_t > 0 // they travel through the portal with their summoner
	fighting  := g.phase == .Playing

	for &m in g.minions {
		if !m.exists do continue
		owner := &g.players[m.owner]
		m.max_hp = minion_max_hp(owner^)
		if m.flash > 0  do m.flash  = max(0, m.flash - dt)
		if m.hit_cd > 0 do m.hit_cd = max(0, m.hit_cd - dt)
		if !m.alive do continue

		oc := player_center(owner^)
		if swallowed {
			m.pos = oc
			m.shrink = owner.shrink
			continue
		}
		m.shrink = 0

		target := clamp_to_arena(oc + minion_orbit_offset(g.time, m.owner, m.slot))
		d := target - m.pos
		if linalg.length(d) > MINION_LEASH {
			// The summoner wrapped around the screen (or was repelled far away): catch up instantly.
			spawn_burst(g, m.pos, owner.color, 8, 120, 2.5)
			m.pos = target
			spawn_burst(g, m.pos, owner.color, 8, 120, 2.5)
		} else {
			vel := d * 6.0
			sp := linalg.length(vel)
			if sp > MINION_MAX_SPEED do vel = vel / sp * MINION_MAX_SPEED
			m.pos += vel * dt
		}

		want := owner.angle
		if fighting {
			if tp, ok := nearest_enemy_to(g, m.pos); ok {
				want = math.atan2(tp.y - m.pos.y, tp.x - m.pos.x)
			}
		}
		m.angle = turn_toward(m.angle, want, MINION_TURN_RATE * dt)
	}
}

minion_laser_length :: proc(m: PlayerMinion) -> f32 {
	dir := [2]f32{math.cos(m.angle), math.sin(m.angle)}
	return max(distance_to_map_edge(m.pos, dir), MINION_RADIUS * 2.0)
}

// One damage pulse of a minion's beam: every enemy touching the line takes damage.
minion_laser_hit :: proc(g: ^Game, m: ^PlayerMinion) {
	dir := [2]f32{math.cos(m.angle), math.sin(m.angle)}
	length := minion_laser_length(m^)
	shooter := &g.players[m.owner]
	half_w := LASER_WIDTH * 0.5

	for &e in g.enemies {
		if !e.active do continue
		epos := closest_wrapped_pos(e, m.pos)
		along := clamp(linalg.dot(epos - m.pos, dir), 0, length)
		nearest := m.pos + dir * along
		if linalg.length(epos - nearest) > e.radius + f32(half_w) do continue
		spawn_burst(g, nearest, shooter.color, 4, 120, 2.5)
		damage_enemy(g, &e, MINION_LASER_DAMAGE, shooter, epos)
	}
}

// Runs once per 60 Hz tick (update_ticks): fire when facing a target, then cool down.
tick_player_minions :: proc(g: ^Game) {
	for &m in g.minions {
		if !m.exists || !m.alive do continue

		if m.laser_ticks > 0 {
			if m.laser_ticks % LASER_HIT_INTERVAL_TICKS == 0 do minion_laser_hit(g, &m)
			m.laser_ticks -= 1
			if m.laser_ticks == 0 do m.gun_ticks = MINION_LASER_COOLDOWN_TICKS
			continue
		}
		if m.gun_ticks > 0 {
			m.gun_ticks -= 1
			continue
		}

		tp, ok := nearest_enemy_to(g, m.pos)
		if !ok do continue
		want := math.atan2(tp.y - m.pos.y, tp.x - m.pos.x)
		if angle_gap(m.angle, want) > MINION_AIM_TOLERANCE do continue
		m.laser_ticks = LASER_TICKS
		add_shake(g, 1)
	}
}

// Enemies that touch a minion hurt it (the boss only on its hit cooldown, and gets knocked back).
// Frozen enemies are harmless.
enemies_hit_minions :: proc(g: ^Game) {
	if g.freeze_ticks > 0 do return
	for &e in g.enemies {
		if !e.active do continue
		if e.kind == .Sticky && e.stuck do continue
		if e.reflect_ticks > 0 do continue // reflected missiles only hurt the other player
		for &m in g.minions {
			if !m.exists || !m.alive do continue
			epos := closest_wrapped_pos(e, m.pos)
			if !rl.CheckCollisionCircles(epos, e.radius, m.pos, MINION_RADIUS) do continue

			switch e.kind {
			case .Boss:
				if e.hit_cd <= 0 {
					e.hit_cd = BOSS_HIT_COOLDOWN
					e.dash_t = 0
					hurt_minion(g, &m, e.damage)
					off := epos - m.pos
					dist := linalg.length(off)
					if dist > 0.001 do e.pos += off / dist * 120
				}
			case .Sticky:
				e.stuck = true
				e.stick_ticks = STICKY_STICK_TICKS
				e.stick_pos = e.pos
				e.flash = 0.35
				spawn_burst(g, e.pos, rl.Color{255, 220, 90, 255}, 18, 130, 3)
			case .Normal, .Runner, .Big, .Minion, .Asteroid:
				e.active = false
				hurt_minion(g, &m, e.damage)
				spawn_burst(g, e.pos, e.color, 8, 150, 3)
			}
			if !e.active do break
		}
	}
}

// --- Drawing ---

draw_player_minions :: proc(g: ^Game) {
	t := g.time
	for m, i in g.minions {
		if !m.exists || !m.alive do continue
		s := 1.0 - clamp(m.shrink, 0, 1)
		if s <= 0.02 do continue
		owner := g.players[m.owner]
		col := tint_up(owner.color, 0.2)
		if m.flash > 0 && int(m.flash * 30) % 2 == 0 do col = rl.WHITE

		// Friendly glow and a faint tether to the summoner.
		rl.BeginBlendMode(.ADDITIVE)
		draw_glow(m.pos, MINION_RADIUS * 2.4 * s, owner.color, 0.35)
		rl.DrawLineEx(m.pos, player_center(owner), 1.2, rl.Fade(owner.color, 0.12))
		rl.EndBlendMode()

		// The body is the laser cruiser, so it also charges its nose emitter between beams.
		body := Enemy{
			pos = m.pos, angle = m.angle, radius = MINION_RADIUS * s, laser = true,
			gun_ticks = m.gun_ticks, laser_ticks = m.laser_ticks,
		}
		draw_cruiser(body, col, t, f32(i) * 1.7)

		// Friendly marker ring + health bar (half of the summoner's health).
		ring_r := MINION_RADIUS * 1.45 * s
		rl.DrawCircleLines(i32(m.pos.x), i32(m.pos.y), ring_r, rl.Fade(owner.color, 0.65))
		frac := clamp(1.0 - f32(m.taken) / f32(max(m.max_hp, 1)), 0, 1)
		bw: f32 = 30
		bx := m.pos.x - bw * 0.5
		by := m.pos.y - ring_r - 8
		rl.DrawRectangleV({bx, by}, {bw, 4}, rl.Fade(rl.BLACK, 0.6))
		rl.DrawRectangleV({bx, by}, {bw * frac, 4}, owner.color)
		rl.DrawRectangleLinesEx(rl.Rectangle{bx, by, bw, 4}, 1, rl.Fade(rl.WHITE, 0.5))
	}
}

draw_minion_lasers :: proc(g: ^Game) {
	for m in g.minions {
		if !m.exists || !m.alive || m.laser_ticks <= 0 do continue
		col := g.players[m.owner].color
		dir := [2]f32{math.cos(m.angle), math.sin(m.angle)}
		start := m.pos + dir * MINION_RADIUS
		end := m.pos + dir * minion_laser_length(m)

		grow := min(1.0, f32(LASER_TICKS - m.laser_ticks + 1) / 3.0)
		fade := min(1.0, f32(m.laser_ticks) / 4.0)
		w := LASER_WIDTH * min(grow, fade) * (0.85 + 0.15 * math.sin(g.time * 90))

		rl.BeginBlendMode(.ADDITIVE)
		rl.DrawLineEx(start, end, w * 2.2, rl.Fade(col, 0.25))
		rl.DrawLineEx(start, end, w * 1.2, rl.Fade(col, 0.6))
		rl.DrawLineEx(start, end, w * 0.45, rl.Fade(rl.WHITE, 0.95))
		draw_glow(end, w * 3.0, col, 0.7)
		rl.DrawCircleV(end, w * 0.7, rl.Fade(rl.WHITE, 0.9))
		rl.EndBlendMode()
	}
}
