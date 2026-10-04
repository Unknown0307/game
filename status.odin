package main

import "core:math/rand"
import rl "vendor:raylib"

// =============================================================================
// status.odin - permanent upgrades a player can pick up (up to MAX_STATUSES).
//
// HOW TO ADD A STATUS
//   1. Add a value to StatusKind (types.odin).
//   2. Add one `case` to status_def() below. Passive stat changes are plain
//      numbers in the StatusDef; anything fancier goes in `on_apply`.
//   That is all: pickups, HUD slots, drop rolls and stacking pick it up
//   automatically.
// =============================================================================

StatusDef :: struct {
	name:  cstring,   // HUD / long text
	label: cstring,   // 3-letter tag shown in the slot
	color: rl.Color,

	// Chance weight when a status drop is rolled (0 = never drops).
	drop_weight: f32,

	// Passive modifiers, applied PER COPY. 0 means "no effect".
	size_bonus:         f32, // +fraction of body size   (0.05 = +5%)
	cooldown_reduction: f32, // -fraction of every skill cooldown (0.10 = -10%)
	damage_reduction:   f32, // -fraction of incoming damage
	max_health_bonus:   f32, // +fraction of the base max health

	// Optional: runs once when a copy is picked up (player_index = slot in g.players).
	on_apply: proc(g: ^Game, p: ^Player, player_index: i32),
}

// The registry. One case per status.
status_def :: proc(kind: StatusKind) -> StatusDef {
	switch kind {
	case .Extension:
		return StatusDef{name = "EXTENSION +5%", label = "EXT", color = rl.SKYBLUE,
			drop_weight = 1, size_bonus = 0.05}
	case .Cooldown:
		return StatusDef{name = "COOLDOWN -10%", label = "CD", color = rl.GOLD,
			drop_weight = 1, cooldown_reduction = 0.10}
	case .Damage:
		return StatusDef{name = "DAMAGE TAKEN -10%", label = "DMG", color = rl.VIOLET,
			drop_weight = 1, damage_reduction = 0.10}
	case .MaxHealth:
		return StatusDef{name = "MAX HEALTH +10%", label = "HP+", color = rl.Color{255, 100, 120, 255},
			drop_weight = 1, max_health_bonus = MAX_HEALTH_BONUS_PER_COPY}
	case .Minion:
		return StatusDef{name = "MINION", label = "MIN", color = rl.Color{110, 255, 170, 255},
			drop_weight = 1, on_apply = status_apply_minion}
	case .None:
		return StatusDef{name = "", label = "?", color = rl.Color{190, 210, 255, 255}}
	}
	return StatusDef{label = "?", color = rl.WHITE}
}

// The Minion status spawns its drone (it needs the Game, so it is an on_apply hook).
status_apply_minion :: proc(g: ^Game, p: ^Player, player_index: i32) {
	spawn_player_minion(g, player_index)
}

// --- Convenience wrappers (keep call sites short) ---

status_name  :: proc(kind: StatusKind) -> cstring  { return status_def(kind).name }
status_label :: proc(kind: StatusKind) -> cstring  { return status_def(kind).label }
status_color :: proc(kind: StatusKind) -> rl.Color { return status_def(kind).color }

// Weighted random pick among statuses that can drop.
random_status_kind :: proc() -> StatusKind {
	total: f32 = 0
	for k in StatusKind do total += status_def(k).drop_weight
	if total <= 0 do return .None
	roll := rand.float32() * total
	for k in StatusKind {
		w := status_def(k).drop_weight
		if w <= 0 do continue
		if roll < w do return k
		roll -= w
	}
	return .None
}

count_status :: proc(p: Player, kind: StatusKind) -> i32 {
	n: i32 = 0
	for i in 0 ..< p.status_count {
		if p.statuses[i] == kind do n += 1
	}
	return n
}

// Product of (1 - reduction) over every owned status copy; pick the field with `which`.
// Used for the "-10% per copy" style modifiers.
status_reduction_mult :: proc(p: Player, field: StatusModifier) -> f32 {
	mult: f32 = 1.0
	for i in 0 ..< p.status_count {
		d := status_def(p.statuses[i])
		r: f32
		switch field {
		case .Cooldown: r = d.cooldown_reduction
		case .Damage:   r = d.damage_reduction
		}
		mult *= 1.0 - r
	}
	return mult
}

StatusModifier :: enum {
	Cooldown,
	Damage,
}

// Sum of the additive bonuses ("+10% per copy").
status_max_health_bonus :: proc(p: Player) -> f32 {
	sum: f32 = 0
	for i in 0 ..< p.status_count do sum += status_def(p.statuses[i]).max_health_bonus
	return sum
}

// Every skill cooldown is multiplied by this (see skill_cooldown).
ability_cooldown_multiplier :: proc(p: Player) -> f32 {
	return status_reduction_mult(p, .Cooldown)
}

// Incoming damage is multiplied by this (see hurt_player).
damage_taken_multiplier :: proc(p: Player) -> f32 {
	return status_reduction_mult(p, .Damage)
}

apply_status :: proc(g: ^Game, p: ^Player, player_index: i32, kind: StatusKind) -> bool {
	if p.status_count >= MAX_STATUSES || kind == .None {
		return false
	}
	p.statuses[p.status_count] = kind
	p.status_count += 1

	def := status_def(kind)
	if def.size_bonus != 0 do p.size *= 1.0 + def.size_bonus
	if def.cooldown_reduction != 0 {
		// Scale the running cooldowns too so the pickup matters immediately.
		for k in SkillKind do p.skill_cd[k] = i32(f32(p.skill_cd[k]) * (1.0 - def.cooldown_reduction))
	}
	// damage_reduction and max_health_bonus are computed dynamically from the stack count.
	if def.on_apply != nil do def.on_apply(g, p, player_index)
	return true
}

