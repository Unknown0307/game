package main

import "core:math"
import "core:math/linalg"
import "core:math/rand"
import rl "vendor:raylib"

// =============================================================================
// pickups.odin - coins, allies and permanent statuses (what each ally does: ally_defs.odin;
// what each status does: status.odin).
// =============================================================================

// --- Coins ---

spawn_coin_at :: proc(g: ^Game, pos: [2]f32) {
	for &c in g.coins {
		if !c.active {
			c = Coin{
				pos    = {clamp(pos.x, 24, SCREEN_W - 24), clamp(pos.y, PLAY_MIN_Y, SCREEN_H - 24)},
				life   = COIN_LIFETIME,
				spin   = rand.float32_range(0, 6.28),
				active = true,
			}
			return
		}
	}
}

count_active_coins :: proc(g: ^Game) -> int {
	n := 0
	for c in g.coins {
		if c.active do n += 1
	}
	return n
}

collect_coins :: proc(g: ^Game, p: ^Player) {
	if p.dead do return
	rect := player_rect(p^)
	for &c in g.coins {
		if c.active && rl.CheckCollisionCircleRec(c.pos, COIN_RADIUS, rect) {
			c.active = false
			p.coins += 1
			p.score += COIN_SCORE
			spawn_burst(g, c.pos, rl.GOLD, 12, 160, 2.5)
			add_float(g, c.pos, COIN_SCORE, .Coin)
		}
	}
}

// --- Allies ---

spawn_ally :: proc(g: ^Game) {
	for &a in g.allies {
		if a.active do continue

		ang := rand.float32_range(0, 2 * math.PI)
		kind := pick_ally_kind()
		def := ally_def(kind)

		a = Ally{
			pos    = {rand.float32_range(60, SCREEN_W - 60), rand.float32_range(130, SCREEN_H - 60)},
			vel    = [2]f32{math.cos(ang), math.sin(ang)} * rand.float32_range(25, 45),
			radius = ALLY_RADIUS,
			hp     = def.hp,
			life   = ALLY_LIFETIME,
			kind   = kind,
			active = true,
		}
		spawn_burst(g, a.pos, def.glow_color, 20, 120, 3)
		return
	}
}

count_active_allies :: proc(g: ^Game) -> int {
	n := 0
	for a in g.allies {
		if a.active do n += 1
	}
	return n
}

// Touching an ally triggers its on_touch hook (see ally_defs.odin); a consumed ally disappears.
heal_from_allies :: proc(g: ^Game, p: ^Player) {
	if p.dead do return
	rect := player_rect(p^)
	for &a in g.allies {
		if !a.active || !rl.CheckCollisionCircleRec(a.pos, a.radius, rect) do continue
		on_touch := ally_def(a.kind).on_touch
		if on_touch != nil && on_touch(g, p, &a) do a.active = false
	}
}

// --- Statuses ---
// Dropped by killed enemies: STATUS_DROP_CHANCE for any enemy, always one
// from a boss (plus a BOSS_DOUBLE_STATUS_CHANCE for a second).

status_space_available :: proc(g: ^Game) -> bool {
	for p in g.players {
		if p.status_count < MAX_STATUSES do return true
	}
	return false
}

any_status_pickup :: proc(g: ^Game) -> bool {
	for pk in g.status_pickups {
		if pk.active do return true
	}
	return false
}

spawn_status_pickup :: proc(g: ^Game, pos: [2]f32) {
	for &pk in g.status_pickups {
		if pk.active do continue
		pk = StatusPickup{
			pos    = {clamp(pos.x, 30, SCREEN_W - 30), clamp(pos.y, PLAY_MIN_Y + 15, SCREEN_H - 30)},
			life   = STATUS_PICKUP_LIFETIME,
			pulse  = rand.float32_range(0, 6.28),
			kind   = random_status_kind(),
			active = true,
		}
		spawn_burst(g, pk.pos, rl.WHITE, 32, 170, 3)
		return
	}
}

roll_status_drop :: proc(g: ^Game, pos: [2]f32, from_boss: bool) {
	if !status_space_available(g) do return

	count := 0
	if from_boss {
		count = 1
		if rand.float32() < BOSS_DOUBLE_STATUS_CHANCE do count = 2
	} else if rand.float32() < STATUS_DROP_CHANCE {
		count = 1
	}

	for i in 0 ..< count {
		offset: [2]f32
		if count > 1 do offset = {(f32(i) * 2 - 1) * 28, 0} // two pickups sit side by side
		spawn_status_pickup(g, pos + offset)
	}
}

// Each pickup goes to the nearest living player that touches it and has a free slot.
collect_statuses :: proc(g: ^Game) {
	for &pk in g.status_pickups {
		if !pk.active do continue

		collector: ^Player = nil
		collector_index: i32 = 0
		best: f32 = math.F32_MAX
		for &p, pi in g.players {
			if p.dead || p.status_count >= MAX_STATUSES do continue
			if !rl.CheckCollisionCircleRec(pk.pos, STATUS_PICKUP_RADIUS, player_rect(p)) do continue
			d := linalg.length(player_center(p) - pk.pos)
			if d < best {
				best = d
				collector = &p
				collector_index = i32(pi)
			}
		}
		if collector == nil do continue

		if apply_status(g, collector, collector_index, pk.kind) {
			spawn_burst(g, pk.pos, rl.WHITE, 45, 250, 4)
			add_float(g, player_center(collector^), collector.status_count, .Status)
			pk.active = false
		}
	}
}

// --- Per-frame update ---

update_pickups :: proc(g: ^Game, dt: f32) {
	for &c in g.coins {
		if !c.active do continue
		c.spin += dt * 5
		c.life -= dt
		if c.life <= 0 do c.active = false
	}

	// Status pickups pause their timer on the portal screen so players can
	// still grab them before leaving the level.
	for &pk in g.status_pickups {
		if !pk.active do continue
		pk.pulse += dt
		if g.phase != .LevelComplete && g.phase != .Sucking {
			pk.life -= dt
			if pk.life <= 0 do pk.active = false
		}
	}

	update_skill_pickups(g, dt)

	for &a in g.allies {
		if !a.active do continue
		a.life -= dt
		a.pulse += dt
		if a.flash > 0 do a.flash -= dt

		// Drift around the play area and bounce off the edges.
		a.pos += a.vel * dt
		if a.pos.x < a.radius {
			a.pos.x = a.radius
			a.vel.x = abs(a.vel.x)
		}
		if a.pos.x > SCREEN_W - a.radius {
			a.pos.x = SCREEN_W - a.radius
			a.vel.x = -abs(a.vel.x)
		}
		if a.pos.y < PLAY_MIN_Y {
			a.pos.y = PLAY_MIN_Y
			a.vel.y = abs(a.vel.y)
		}
		if a.pos.y > SCREEN_H - a.radius {
			a.pos.y = SCREEN_H - a.radius
			a.vel.y = -abs(a.vel.y)
		}

		if a.life <= 0 {
			a.active = false
			spawn_burst(g, a.pos, rl.LIME, 12, 100, 2)
		}
	}
}
