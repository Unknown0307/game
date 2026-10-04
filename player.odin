package main

import "core:math"
import "core:math/linalg"
import "core:math/rand"
import rl "vendor:raylib"

// =============================================================================
// player.odin - players: construction, movement, health, shields, enhancements,
// and invulnerability checks. (Skills + the gun live in skills.odin.)
// =============================================================================

SHIELD_COLOR :: rl.Color{215, 220, 228, 255}

make_player :: proc(index: int) -> Player {
	p := Player{
		size  = {30, 30},
		speed = PLAYER_MAX_SPEED,
	}
	switch index {
	case 0:
		p.name          = "P1"
		p.controls_text = "P1: WASD"
		p.ready_text    = "READY [R]"
		p.color         = rl.Color{70, 150, 255, 255}
		p.hud_color     = rl.SKYBLUE
		p.ship          = .Fighter
		p.up, p.down, p.left, p.right = .W, .S, .A, .D
		p.fire_key      = .F
		p.skill_key     = .R
		p.cycle_key     = .E
		p.aim_key       = .Q
		p.start_pos     = {200, 300}
	case:
		p.name          = "P2"
		p.controls_text = "P2: Arrows"
		p.ready_text    = "READY [/]"
		p.color         = rl.Color{60, 230, 110, 255}
		p.hud_color     = rl.LIME
		p.ship          = .Interceptor
		p.up, p.down, p.left, p.right = .UP, .DOWN, .LEFT, .RIGHT
		p.fire_key      = .PERIOD
		p.skill_key     = .SLASH
		p.cycle_key     = .COMMA
		p.aim_key       = .M
		p.start_pos     = {600, 300}
	}
	p.pos = p.start_pos
	for k in SkillKind do p.wheel_w[k] = 1
	p.skill_aim = true
	return p
}

// The Freeze skill leaves its user slowed once the freeze is over.
player_slowed :: proc(p: Player) -> bool {
	return p.slow_ticks > 0 && p.slow_ticks <= FREEZE_SLOW_TICKS
}

// Brings a dead player back at the start of a new level.
revive_player :: proc(p: ^Player) {
	p.dead = false
	p.health_points = 0
	p.shield_ticks = {}
	p.skill_cd = {}
	p.fire_cd = 0
	p.invis_ticks = 0
	p.surprise_ticks = 0
	p.visual_timer = 0
	p.repel_visual = 0
	p.freeze_visual = 0
	p.slow_ticks = 0
	p.rewind_visual = 0
	p.comeback_used = false
	p.hurt_flash = 0
	p.angle = 0
	p.target_angle = 0
	p.thrust = 0
	p.shrink = 0
	p.trail_n = 0
}

player_center :: proc(p: Player) -> [2]f32 {
	return p.pos + p.size * 0.5
}

player_rect :: proc(p: Player) -> rl.Rectangle {
	return rl.Rectangle{p.pos.x, p.pos.y, p.size.x, p.size.y}
}

// Total health: MAX_HEALTH plus 10% of it per "Max health" enhancement.
player_max_health :: proc(p: Player) -> i32 {
	bonus := MAX_HEALTH_BONUS_PER_COPY * f32(count_enhancement(p, .MaxHealth))
	return i32(math.round(f32(MAX_HEALTH) * (1.0 + bonus)))
}

// Share of tags a player has left before dying (1.0 = full, 0.0 = dead)
health_fraction :: proc(p: Player) -> f32 {
	return max(0, 1 - f32(p.health_points) / f32(player_max_health(p)))
}

total_score :: proc(g: ^Game) -> i32 {
	total: i32 = 0
	for p in g.players do total += p.score
	return total
}

all_players_dead :: proc(g: ^Game) -> bool {
	for p in g.players {
		if !p.dead do return false
	}
	return true
}

// --- Enhancements ---

enhancement_name :: proc(kind: EnhancementKind) -> cstring {
	switch kind {
	case .Extension: return "EXTENSION +5%"
	case .Cooldown:  return "COOLDOWN -10%"
	case .Damage:    return "DAMAGE TAKEN -10%"
	case .MaxHealth: return "MAX HEALTH +10%"
	case .Minion:    return "MINION"
	case .None:      return ""
	}
	return ""
}

enhancement_label :: proc(kind: EnhancementKind) -> cstring {
	switch kind {
	case .Extension: return "EXT"
	case .Cooldown:  return "CD"
	case .Damage:    return "DMG"
	case .MaxHealth: return "HP+"
	case .Minion:    return "MIN"
	case .None:      return "?"
	}
	return "?"
}

enhancement_color :: proc(kind: EnhancementKind) -> rl.Color {
	switch kind {
	case .Extension: return rl.SKYBLUE
	case .Cooldown:  return rl.GOLD
	case .Damage:    return rl.VIOLET
	case .MaxHealth: return rl.Color{255, 100, 120, 255}
	case .Minion:    return rl.Color{110, 255, 170, 255}
	case .None:      return rl.Color{190, 210, 255, 255}
	}
	return rl.WHITE
}

random_enhancement_kind :: proc() -> EnhancementKind {
	all := [5]EnhancementKind{.Extension, .Cooldown, .Damage, .MaxHealth, .Minion}
	return all[rand.int31_max(i32(len(all)))]
}

count_enhancement :: proc(p: Player, kind: EnhancementKind) -> i32 {
	n: i32 = 0
	for i in 0 ..< p.enhancement_count {
		if p.enhancements[i] == kind do n += 1
	}
	return n
}

ability_cooldown_multiplier :: proc(p: Player) -> f32 {
	mult: f32 = 1.0
	for _ in 0 ..< count_enhancement(p, .Cooldown) do mult *= 0.90
	return mult
}

apply_enhancement :: proc(p: ^Player, kind: EnhancementKind) -> bool {
	if p.enhancement_count >= MAX_ENHANCEMENTS || kind == .None {
		return false
	}
	p.enhancements[p.enhancement_count] = kind
	p.enhancement_count += 1

	switch kind {
	case .Extension:
		p.size *= 1.05
	case .Cooldown:
		// Scale the running cooldowns too so the pickup matters immediately.
		for k in SkillKind do p.skill_cd[k] = i32(f32(p.skill_cd[k]) * 0.90)
	case .Damage:
		// Computed dynamically from the stack count in hurt_player.
	case .MaxHealth:
		// Computed dynamically (player_max_health): the extra 10% is simply more room before dying.
	case .Minion:
		// The drone itself is created by collect_enhancements (it needs the Game).
	case .None:
	}
	return true
}

// --- Shields ---

shield_count :: proc(p: Player) -> i32 {
	n: i32 = 0
	for ticks in p.shield_ticks {
		if ticks > 0 do n += 1
	}
	return n
}

consume_shield :: proc(g: ^Game, p: ^Player) -> bool {
	slot: int = -1
	lowest: i32 = SHIELD_DURATION_TICKS + 1
	for i in 0 ..< MAX_SHIELDS {
		if p.shield_ticks[i] > 0 && p.shield_ticks[i] < lowest {
			lowest = p.shield_ticks[i]
			slot = i
		}
	}
	if slot < 0 do return false

	p.shield_ticks[slot] = 0
	center := player_center(p^)
	spawn_burst(g, center, SHIELD_COLOR, 18, 190, 3)
	add_float(g, center + [2]f32{0, -18}, 1, .Shield)
	add_shake(g, 2.5)
	return true
}

add_shield :: proc(g: ^Game, p: ^Player) {
	// Prefer an empty slot. If full, refresh the shield with the least time left.
	slot: int = -1
	lowest: i32 = SHIELD_DURATION_TICKS + 1
	for i in 0 ..< MAX_SHIELDS {
		if p.shield_ticks[i] <= 0 {
			slot = i
			break
		}
		if p.shield_ticks[i] < lowest {
			lowest = p.shield_ticks[i]
			slot = i
		}
	}
	if slot >= 0 {
		p.shield_ticks[slot] = SHIELD_DURATION_TICKS
		center := player_center(p^)
		spawn_burst(g, center, SHIELD_COLOR, 28, 220, 3.5)
		add_float(g, center + [2]f32{0, -18}, 1, .Shield)
	}
}

tick_shields :: proc(p: ^Player) {
	for i in 0 ..< MAX_SHIELDS {
		if p.shield_ticks[i] > 0 do p.shield_ticks[i] -= 1
	}
}

// --- Damage ---

hurt_player :: proc(g: ^Game, p: ^Player, amount: i32) {
	if p.dead || amount <= 0 do return

	// Invisibility and Surprise make the player immune to all damage.
	if player_invulnerable(p^) do return

	// A barrier consumes the hit before health is touched.
	if consume_shield(g, p) {
		p.hurt_flash = 0.12
		return
	}

	reduction: f32 = 1.0
	for _ in 0 ..< count_enhancement(p^, .Damage) do reduction *= 0.90
	effective := max(1, i32(math.ceil(f32(amount) * reduction)))
	p.health_points += effective
	p.hurt_flash = 0.3
	center := player_center(p^)
	spawn_burst(g, center, rl.RED, int(8 + effective * 2), 170, 3)
	add_shake(g, min(3 + f32(effective), 12))

	if p.health_points >= player_max_health(p^) {
		p.health_points = player_max_health(p^)
		p.dead = true
		p.shield_ticks = {}
		p.invis_ticks = 0
		p.surprise_ticks = 0
		p.slow_ticks = 0
		spawn_burst(g, center, p.color, 60, 320, 4)
		spawn_burst(g, center, rl.WHITE, 30, 220, 3)
		add_shake(g, 16)
	}
}

// --- Per-frame update ---

update_player_timers :: proc(p: ^Player, dt: f32) {
	if p.visual_timer > 0 do p.visual_timer = max(0, p.visual_timer - dt)
	if p.repel_visual > 0 do p.repel_visual = max(0, p.repel_visual - dt)
	if p.freeze_visual > 0 do p.freeze_visual = max(0, p.freeze_visual - dt)
	if p.rewind_visual > 0 do p.rewind_visual = max(0, p.rewind_visual - dt)
	for i in 0 ..< 2 {
		if p.muzzle_flash[i] > 0 do p.muzzle_flash[i] = max(0, p.muzzle_flash[i] - dt)
	}
	// The wheel slices glide toward their target size (taken skill = biggest).
	for k in SKILLS {
		target: f32 = SKILL_WHEEL_BIG if p.skill == k else 1.0
		p.wheel_w[k] += (target - p.wheel_w[k]) * min(1.0, 12.0 * dt)
	}
	if p.hurt_flash > 0 do p.hurt_flash = max(0, p.hurt_flash - dt)
}

update_ship_rotation :: proc(p: ^Player, dt: f32) {
	delta := p.target_angle - p.angle
	if delta > math.PI do delta -= 2 * math.PI
	if delta < -math.PI do delta += 2 * math.PI
	max_turn: f32 = 8.5 * dt
	p.angle += clamp(delta, -max_turn, max_turn)
}

// Screen-wrap: the whole ship must leave an edge before it re-enters opposite.
wrap_player_position :: proc(p: ^Player) -> bool {
	wrapped := false
	sw := f32(SCREEN_W)
	sh := f32(SCREEN_H)

	if p.pos.x + p.size.x < 0 {
		p.pos.x = sw
		wrapped = true
	} else if p.pos.x > sw {
		p.pos.x = -p.size.x
		wrapped = true
	}

	if p.pos.y + p.size.y < 0 {
		p.pos.y = sh
		wrapped = true
	} else if p.pos.y > sh {
		p.pos.y = -p.size.y
		wrapped = true
	}
	return wrapped
}

// Engine sparks thrown out behind the ship. Each ship has its own colours.
emit_trail :: proc(g: ^Game, p: ^Player) {
	c := player_center(p^)
	face := [2]f32{math.cos(p.angle), math.sin(p.angle)}
	side := [2]f32{-face.y, face.x}
	back := c - face * (p.size.x * 0.5)
	j := rand_vec2()

	switch p.ship {
	case .Fighter:
		cols := [2]rl.Color{{150, 220, 255, 255}, {255, 255, 255, 255}}
		spawn_particle(g, back + j * 2, -face * rand.float32_range(70, 150) + j * 30, cols[rand.int31_max(2)], 0.38, rand.float32_range(2.5, 4.5))
	case .Interceptor:
		// Two nacelle jets, alternating lime and amber.
		sgn: f32 = 1 if rand.int31_max(2) == 0 else -1
		pos := back + side * (p.size.y * 0.36 * sgn)
		col := rl.Color{255, 190, 60, 255} if sgn > 0 else rl.Color{150, 255, 120, 255}
		spawn_particle(g, pos + j * 1.5, -face * rand.float32_range(50, 120) + j * 25, col, 0.42, rand.float32_range(3.0, 5.0))
	}
}

update_player_movement :: proc(g: ^Game, p: ^Player, dt: f32) {
	if p.dead do return
	old := p.pos

	dir: [2]f32
	thrust_target: f32 = 0
	if rl.IsKeyDown(p.up)    do dir.y -= 1
	if rl.IsKeyDown(p.down)  do dir.y += 1
	if rl.IsKeyDown(p.left)  do dir.x -= 1
	if rl.IsKeyDown(p.right) do dir.x += 1
	if linalg.length(dir) > 0.001 {
		dir = linalg.normalize(dir)
		p.target_angle = math.atan2(dir.y, dir.x)
		speed := p.speed
		if player_slowed(p^) do speed *= FREEZE_SLOW_MULT
		p.pos += dir * speed * dt
		thrust_target = 1
	}
	p.thrust += (thrust_target - p.thrust) * min(1.0, 9.0 * dt)

	// Boss repel knock-back: an impulse that fades out.
	if linalg.length(p.knock) > 1 {
		p.pos += p.knock * dt
		p.knock *= max(0, 1 - KNOCK_DECAY * dt)
	} else {
		p.knock = {}
	}

	update_ship_rotation(p, dt)
	wrapped := wrap_player_position(p)

	// No trail on the frame of a screen wrap (avoids a streak across the arena).
	if !wrapped && linalg.length(p.pos - old) > 0.01 {
		emit_trail(g, p)
	}

	// Ribbon history for the ship art; a screen wrap would draw a streak across the arena.
	if wrapped {
		p.trail_n = 0
	} else {
		push_trail(p)
	}
}
