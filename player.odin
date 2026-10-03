package main

import "core:math"
import "core:math/linalg"
import "core:math/rand"
import rl "vendor:raylib"

// =============================================================================
// player.odin - players: construction, movement, health, shields, enhancements,
// and the repel-blast ability.
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
		p.color         = rl.BLUE
		p.hud_color     = rl.SKYBLUE
		p.ship          = .Fighter
		p.up, p.down, p.left, p.right = .W, .S, .A, .D
		p.ability_key   = .R
		p.start_pos     = {200, 300}
	case:
		p.name          = "P2"
		p.controls_text = "P2: Arrows"
		p.ready_text    = "READY [/]"
		p.color         = rl.GREEN
		p.hud_color     = rl.LIME
		p.ship          = .Interceptor
		p.up, p.down, p.left, p.right = .UP, .DOWN, .LEFT, .RIGHT
		p.ability_key   = .SLASH
		p.start_pos     = {600, 300}
	}
	p.pos = p.start_pos
	return p
}

// Brings a dead player back at the start of a new level.
revive_player :: proc(p: ^Player) {
	p.dead = false
	p.tag_count = 0
	p.shield_ticks = {}
	p.ability_cd = 0
	p.visual_timer = 0
	p.hurt_flash = 0
	p.angle = 0
	p.target_angle = 0
}

player_center :: proc(p: Player) -> [2]f32 {
	return p.pos + p.size * 0.5
}

player_rect :: proc(p: Player) -> rl.Rectangle {
	return rl.Rectangle{p.pos.x, p.pos.y, p.size.x, p.size.y}
}

// Share of tags a player has left before dying (1.0 = full, 0.0 = dead)
health_fraction :: proc(p: Player) -> f32 {
	return max(0, 1 - f32(p.tag_count) / f32(MAX_TAGS))
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
	case .None:      return ""
	}
	return ""
}

enhancement_label :: proc(kind: EnhancementKind) -> cstring {
	switch kind {
	case .Extension: return "EXT"
	case .Cooldown:  return "CD"
	case .Damage:    return "DMG"
	case .None:      return "?"
	}
	return "?"
}

enhancement_color :: proc(kind: EnhancementKind) -> rl.Color {
	switch kind {
	case .Extension: return rl.SKYBLUE
	case .Cooldown:  return rl.GOLD
	case .Damage:    return rl.VIOLET
	case .None:      return rl.Color{190, 210, 255, 255}
	}
	return rl.WHITE
}

random_enhancement_kind :: proc() -> EnhancementKind {
	r := rand.float32()
	if r >= 0.66 do return .Damage
	if r >= 0.33 do return .Cooldown
	return .Extension
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
		// Scale the running cooldown too so the pickup matters immediately.
		p.ability_cd *= 0.90
	case .Damage:
		// Computed dynamically from the stack count in hurt_player.
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

	// A barrier consumes the hit before health is touched.
	if consume_shield(g, p) {
		p.hurt_flash = 0.12
		return
	}

	reduction: f32 = 1.0
	for _ in 0 ..< count_enhancement(p^, .Damage) do reduction *= 0.90
	effective := max(1, i32(math.ceil(f32(amount) * reduction)))
	p.tag_count += effective
	p.hurt_flash = 0.3
	center := player_center(p^)
	spawn_burst(g, center, rl.RED, int(8 + effective * 2), 170, 3)
	add_shake(g, min(3 + f32(effective), 12))

	if p.tag_count >= MAX_TAGS {
		p.tag_count = MAX_TAGS
		p.dead = true
		p.shield_ticks = {}
		spawn_burst(g, center, p.color, 60, 320, 4)
		spawn_burst(g, center, rl.WHITE, 30, 220, 3)
		add_shake(g, 16)
	}
}

// --- Ability: repel blast (kills regular enemies in range, damages bosses) ---

fire_blast :: proc(g: ^Game, p: ^Player) {
	center := player_center(p^)
	p.ability_cd = ABILITY_COOLDOWN * ability_cooldown_multiplier(p^)
	p.visual_timer = BLAST_VISUAL_TIME
	add_shake(g, 4)
	spawn_ring(g, center, p.color, 40, 450, 0.3, 3)

	for &e in g.enemies {
		if !e.active do continue
		offset := e.pos - center
		dist := linalg.length(offset)
		if dist - e.radius >= REPULSION_RADIUS do continue

		if e.kind == .Boss {
			e.hp -= 1
			e.flash = 0.15
			spawn_burst(g, e.pos, rl.WHITE, 14, 260, 3)
			if e.hp <= 0 {
				kill_enemy(g, &e, p)
			} else {
				if dist > 0.001 do e.pos += offset / dist * 70 // knock-back
				add_shake(g, 6)
			}
		} else {
			kill_enemy(g, &e, p)
		}
	}
}

// --- Per-frame update ---

update_player_timers :: proc(p: ^Player, dt: f32) {
	if p.ability_cd > 0 do p.ability_cd = max(0, p.ability_cd - dt)
	if p.visual_timer > 0 do p.visual_timer = max(0, p.visual_timer - dt)
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

emit_trail :: proc(g: ^Game, p: ^Player) {
	c := player_center(p^)
	jitter := [2]f32{rand.float32_range(-1, 1), rand.float32_range(-1, 1)}
	spawn_particle(g, c + jitter * 8, jitter * 25, p.color, 0.35, 5)
}

update_player_movement :: proc(g: ^Game, p: ^Player, dt: f32) {
	if p.dead do return
	old := p.pos

	dir: [2]f32
	if rl.IsKeyDown(p.up)    do dir.y -= 1
	if rl.IsKeyDown(p.down)  do dir.y += 1
	if rl.IsKeyDown(p.left)  do dir.x -= 1
	if rl.IsKeyDown(p.right) do dir.x += 1
	if linalg.length(dir) > 0.001 {
		dir = linalg.normalize(dir)
		p.target_angle = math.atan2(dir.y, dir.x)
		p.pos += dir * p.speed * dt
	}

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
}
