package main

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

// =============================================================================
// skill_defs.odin - the skill registry: everything that DESCRIBES a skill.
// (What a skill DOES lives in skills.odin; the gun lives in gunfire/skills.)
//
// HOW TO ADD A SKILL
//   1. Add a value to SkillKind (types.odin). The enum order is the wheel order.
//   2. Add one `case` to skill_def() below (name, label, colour, cooldown, use).
//   3. Write the `use` proc (skills.odin or a new file): proc(g, p, index).
//   4. Optional: `progress` / `hud_status` for custom HUD wheel / text.
//   Dice drops, the HUD wheel, cycling, cooldown ticking and the Cooldown status
//   all work from this table, so nothing else needs to change.
// =============================================================================

SkillDef :: struct {
	name:  cstring,   // shown beside the wheel
	label: cstring,   // 3-letter tag inside the wheel slice
	color: rl.Color,

	// Ticks before the skill can be used again (shortened by Cooldown statuses).
	cooldown: i32,
	// Ticks added on top that Cooldown statuses do NOT shorten (e.g. Freeze's 3 s freeze).
	cooldown_extra: i32,

	// Runs when the key is pressed and the skill is off cooldown. nil = passive skill.
	use: proc(g: ^Game, p: ^Player, index: i32),

	// Skill has an auto-aim toggle (the aim key flips Player.skill_aim).
	has_aim_toggle: bool,

	// Optional HUD overrides. nil = generic cooldown display.
	progress:   proc(p: Player) -> f32,                                         // wheel fill, 0..1
	hud_status: proc(p: Player) -> (text: cstring, color: rl.Color, ok: bool), // line under the name; ok=false -> generic text
}

// The registry. One case per skill.
skill_def :: proc(kind: SkillKind) -> SkillDef {
	switch kind {
	case .Explosion:
		return SkillDef{name = "EXPLOSION", label = "EXP", color = rl.Color{255, 160, 50, 255},
			cooldown = EXPLOSION_COOLDOWN_TICKS, use = use_explosion}
	case .Repel:
		return SkillDef{name = "REPEL", label = "REP", color = rl.Color{90, 255, 190, 255},
			cooldown = REPEL_COOLDOWN_TICKS, use = use_repel}
	case .Rocket:
		// Passive: it changes what the gun fires (see fire_gun).
		return SkillDef{name = "ROCKET BULLETS", label = "RKT", color = rl.Color{255, 85, 85, 255},
			cooldown = ROCKET_COOLDOWN_TICKS, has_aim_toggle = true,
			progress = progress_rocket, hud_status = hud_status_rocket}
	case .Invisibility:
		return SkillDef{name = "INVISIBILITY", label = "INV", color = rl.Color{120, 230, 255, 255},
			cooldown = INVIS_COOLDOWN_TICKS, use = use_invisibility, hud_status = hud_status_invisibility}
	case .Surprise:
		return SkillDef{name = "SURPRISE", label = "SUR", color = rl.Color{230, 110, 255, 255},
			cooldown = SURPRISE_COOLDOWN_TICKS, use = use_surprise, hud_status = hud_status_surprise}
	case .Freeze:
		// The 30 s cooldown only starts once the 3 s freeze is over.
		return SkillDef{name = "FREEZE", label = "FRZ", color = rl.Color{110, 170, 255, 255},
			cooldown = FREEZE_COOLDOWN_TICKS, cooldown_extra = FREEZE_DURATION_TICKS,
			use = use_freeze, hud_status = hud_status_freeze}
	case .ComeBack:
		// No timer: once per level (Player.comeback_used).
		return SkillDef{name = "COME BACK", label = "CMB", color = rl.Color{255, 225, 90, 255},
			use = use_comeback, progress = progress_comeback, hud_status = hud_status_comeback}
	case .None:
		return SkillDef{name = "NO SKILL", label = "-", color = rl.Color{150, 150, 160, 255}}
	}
	return SkillDef{label = "-", color = rl.WHITE}
}

// --- Convenience wrappers (keep call sites short) ---

skill_name  :: proc(kind: SkillKind) -> cstring  { return skill_def(kind).name }
skill_label :: proc(kind: SkillKind) -> cstring  { return skill_def(kind).label }
skill_color :: proc(kind: SkillKind) -> rl.Color { return skill_def(kind).color }

// Skills in wheel order (SkillKind order, skipping None).
SKILL_COUNT :: len(_SKILL_PROBE) - 1
_SKILL_PROBE :: [SkillKind]u8{}

skill_at :: proc(i: int) -> SkillKind {
	return SkillKind(i + 1) // None is value 0
}

// Ticks between pressing the skill and having it ready again (what the HUD wheel counts down).
skill_total_cooldown :: proc(p: Player, kind: SkillKind) -> i32 {
	def := skill_def(kind)
	return def.cooldown_extra + skill_cooldown(p, def.cooldown)
}

// The Cooldown status (-10% per copy) shortens every skill cooldown.
skill_cooldown :: proc(p: Player, base: i32) -> i32 {
	return max(1, i32(math.round(f32(base) * ability_cooldown_multiplier(p))))
}

// --- HUD hooks ---

// Cooldown progress of a skill, 0 (just used) .. 1 (ready).
skill_progress :: proc(p: Player, kind: SkillKind) -> f32 {
	def := skill_def(kind)
	if def.progress != nil do return def.progress(p)
	cd := p.skill_cd[kind]
	if cd <= 0 do return 1
	return clamp(1 - f32(cd) / f32(skill_total_cooldown(p, kind)), 0, 1)
}

// The status line shown under the skill name (only called for the taken skill).
skill_status_text :: proc(p: Player) -> (text: cstring, color: rl.Color) {
	def := skill_def(p.skill)
	if def.hud_status != nil {
		if t, c, ok := def.hud_status(p); ok do return t, c
	}
	if p.skill_cd[p.skill] > 0 {
		return fmt.ctprintf("%.1fs", f32(p.skill_cd[p.skill]) / TICK_RATE), rl.LIGHTGRAY
	}
	return p.ready_text, rl.WHITE
}

progress_rocket :: proc(p: Player) -> f32 {
	if p.skill != .Rocket do return 1
	return 1 - f32(p.fire_cd) / f32(skill_cooldown(p, ROCKET_COOLDOWN_TICKS))
}

progress_comeback :: proc(p: Player) -> f32 {
	if p.comeback_used do return 0
	return 1
}

hud_status_rocket :: proc(p: Player) -> (text: cstring, color: rl.Color, ok: bool) {
	if p.fire_cd > 0 do return fmt.ctprintf("%.1fs", f32(p.fire_cd) / TICK_RATE), rl.LIGHTGRAY, true
	if p.skill_aim   do return "AUTO-AIM", rl.LIGHTGRAY, true
	return "MANUAL AIM", rl.LIGHTGRAY, true
}

hud_status_invisibility :: proc(p: Player) -> (text: cstring, color: rl.Color, ok: bool) {
	if p.invis_ticks <= 0 do return nil, {}, false
	return fmt.ctprintf("INVISIBLE %.1fs", f32(p.invis_ticks) / TICK_RATE), skill_color(.Invisibility), true
}

hud_status_surprise :: proc(p: Player) -> (text: cstring, color: rl.Color, ok: bool) {
	if p.surprise_ticks <= 0 do return nil, {}, false
	return "REFLECTING!", skill_color(.Surprise), true
}

hud_status_comeback :: proc(p: Player) -> (text: cstring, color: rl.Color, ok: bool) {
	if p.comeback_used do return "USED THIS LEVEL", rl.Fade(rl.LIGHTGRAY, 0.7), true
	return p.ready_text, rl.WHITE, true
}

hud_status_freeze :: proc(p: Player) -> (text: cstring, color: rl.Color, ok: bool) {
	thaw := skill_cooldown(p, FREEZE_COOLDOWN_TICKS)
	if p.skill_cd[.Freeze] > thaw {
		// still inside the 3 s freeze: the 30 s cooldown has not started yet
		return fmt.ctprintf("FROZEN %.1fs", f32(p.skill_cd[.Freeze] - thaw) / TICK_RATE), skill_color(.Freeze), true
	}
	if player_slowed(p) {
		return fmt.ctprintf("SLOWED %.1fs", f32(p.slow_ticks) / TICK_RATE), skill_color(.Freeze), true
	}
	return nil, {}, false
}
