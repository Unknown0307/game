package main

import "core:math"
import "core:math/linalg"
import "core:math/rand"
import rl "vendor:raylib"

// =============================================================================
// pickups.odin - coins, allies and permanent enhancements.
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
		kind := AllyKind.Heal
		if rand.float32() < BARRIER_ALLY_CHANCE do kind = .Barrier

		hp: i32 = ALLY_HP
		if kind == .Barrier do hp = 1

		a = Ally{
			pos    = {rand.float32_range(60, SCREEN_W - 60), rand.float32_range(130, SCREEN_H - 60)},
			vel    = [2]f32{math.cos(ang), math.sin(ang)} * rand.float32_range(25, 45),
			radius = ALLY_RADIUS,
			hp     = hp,
			life   = ALLY_LIFETIME,
			kind   = kind,
			active = true,
		}
		burst_color := rl.LIME
		if kind == .Barrier do burst_color = SHIELD_COLOR
		spawn_burst(g, a.pos, burst_color, 20, 120, 3)
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

// Touching an ally heals (only if hurt, so heals aren't wasted) or adds a shield.
heal_from_allies :: proc(g: ^Game, p: ^Player) {
	if p.dead do return
	rect := player_rect(p^)
	for &a in g.allies {
		if !a.active || !rl.CheckCollisionCircleRec(a.pos, a.radius, rect) do continue

		if a.kind == .Barrier {
			add_shield(g, p)
			a.active = false
			continue
		}

		if p.health_points > 0 {
			healed := min(HEAL_AMOUNT, p.health_points)
			p.health_points -= healed
			a.active = false
			spawn_burst(g, a.pos, rl.LIME, 30, 220, 3.5)
			spawn_burst(g, player_center(p^), rl.LIME, 20, 140, 3)
			add_float(g, a.pos, healed, .Heal)
		}
	}
}

// --- Enhancements ---
// Dropped by killed enemies: ENHANCEMENT_DROP_CHANCE for any enemy, always one
// from a boss (plus a BOSS_DOUBLE_ENHANCEMENT_CHANCE for a second).

enhancement_space_available :: proc(g: ^Game) -> bool {
	for p in g.players {
		if p.enhancement_count < MAX_ENHANCEMENTS do return true
	}
	return false
}

any_enhancement_pickup :: proc(g: ^Game) -> bool {
	for pk in g.enh_pickups {
		if pk.active do return true
	}
	return false
}

spawn_enhancement_pickup :: proc(g: ^Game, pos: [2]f32) {
	for &pk in g.enh_pickups {
		if pk.active do continue
		pk = EnhancementPickup{
			pos    = {clamp(pos.x, 30, SCREEN_W - 30), clamp(pos.y, PLAY_MIN_Y + 15, SCREEN_H - 30)},
			life   = ENH_PICKUP_LIFETIME,
			pulse  = rand.float32_range(0, 6.28),
			kind   = random_enhancement_kind(),
			active = true,
		}
		spawn_burst(g, pk.pos, rl.WHITE, 32, 170, 3)
		return
	}
}

roll_enhancement_drop :: proc(g: ^Game, pos: [2]f32, from_boss: bool) {
	if !enhancement_space_available(g) do return

	count := 0
	if from_boss {
		count = 1
		if rand.float32() < BOSS_DOUBLE_ENHANCEMENT_CHANCE do count = 2
	} else if rand.float32() < ENHANCEMENT_DROP_CHANCE {
		count = 1
	}

	for i in 0 ..< count {
		offset: [2]f32
		if count > 1 do offset = {(f32(i) * 2 - 1) * 28, 0} // two pickups sit side by side
		spawn_enhancement_pickup(g, pos + offset)
	}
}

// Each pickup goes to the nearest living player that touches it and has a free slot.
collect_enhancements :: proc(g: ^Game) {
	for &pk in g.enh_pickups {
		if !pk.active do continue

		collector: ^Player = nil
		collector_index: i32 = 0
		best: f32 = math.F32_MAX
		for &p, pi in g.players {
			if p.dead || p.enhancement_count >= MAX_ENHANCEMENTS do continue
			if !rl.CheckCollisionCircleRec(pk.pos, ENH_PICKUP_RADIUS, player_rect(p)) do continue
			d := linalg.length(player_center(p) - pk.pos)
			if d < best {
				best = d
				collector = &p
				collector_index = i32(pi)
			}
		}
		if collector == nil do continue

		if apply_enhancement(collector, pk.kind) {
			if pk.kind == .Minion do spawn_player_minion(g, collector_index)
			spawn_burst(g, pk.pos, rl.WHITE, 45, 250, 4)
			add_float(g, player_center(collector^), collector.enhancement_count, .Enhancement)
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

	// Enhancement pickups pause their timer on the portal screen so players can
	// still grab them before leaving the level.
	for &pk in g.enh_pickups {
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
