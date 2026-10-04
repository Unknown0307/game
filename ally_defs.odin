package main

import "core:math/rand"
import rl "vendor:raylib"

// =============================================================================
// ally_defs.odin - the ally registry: floating helpers a player collects by
// touching them (enemies can destroy them first).
//
// HOW TO ADD AN ALLY
//   1. Add a value to AllyKind (types.odin).
//   2. Add one `case` to ally_def() below: hit points, colours, how often it
//      spawns, what it does on touch, and how its icon is drawn.
//   Spawning, drifting, enemy damage, glow, drawing and the hit-point pips are
//   shared and need no changes.
// =============================================================================

AllyDef :: struct {
	hp:           i32,
	spawn_chance: f32,        // share of ally spawns (0..1); whatever is left over is Heal
	body_color:   rl.Color,   // toon disc colour
	glow_color:   rl.Color,   // additive glow + spawn / pickup sparkle colour

	// Called when a living player touches it. Return true to consume the ally.
	on_touch: proc(g: ^Game, p: ^Player, a: ^Ally) -> bool,
	// Draws the symbol on top of the body disc (optional).
	draw_icon: proc(a: Ally),
}

// The registry. One case per ally.
ally_def :: proc(kind: AllyKind) -> AllyDef {
	switch kind {
	case .Heal:
		return AllyDef{hp = ALLY_HP, body_color = rl.Color{60, 220, 100, 255}, glow_color = rl.LIME,
			on_touch = touch_heal, draw_icon = icon_heal}
	case .Barrier:
		return AllyDef{hp = 1, spawn_chance = BARRIER_ALLY_CHANCE, body_color = rl.Color{190, 198, 210, 255},
			glow_color = SHIELD_COLOR, on_touch = touch_barrier, draw_icon = icon_barrier}
	}
	return AllyDef{}
}

pick_ally_kind :: proc() -> AllyKind {
	roll := rand.float32()
	for kind in AllyKind {
		chance := ally_def(kind).spawn_chance
		if roll < chance do return kind
		roll -= chance
	}
	return .Heal
}

// --- on_touch hooks ---

// Heals, but only if the player is hurt (so heals aren't wasted).
touch_heal :: proc(g: ^Game, p: ^Player, a: ^Ally) -> bool {
	if p.health_points <= 0 do return false
	healed := min(HEAL_AMOUNT, p.health_points)
	p.health_points -= healed
	spawn_burst(g, a.pos, rl.LIME, 30, 220, 3.5)
	spawn_burst(g, player_center(p^), rl.LIME, 20, 140, 3)
	add_float(g, a.pos, healed, .Heal)
	return true
}

touch_barrier :: proc(g: ^Game, p: ^Player, a: ^Ally) -> bool {
	add_shield(g, p)
	return true
}

// --- draw_icon hooks ---

icon_heal :: proc(a: Ally) {
	// A chunky white plus with an ink edge.
	arm := a.radius * 0.7
	th := a.radius * 0.28
	rl.DrawRectangleV(a.pos - [2]f32{arm + 1.5, th + 1.5}, [2]f32{arm * 2 + 3, th * 2 + 3}, TOON_LINE)
	rl.DrawRectangleV(a.pos - [2]f32{th + 1.5, arm + 1.5}, [2]f32{th * 2 + 3, arm * 2 + 3}, TOON_LINE)
	rl.DrawRectangleV(a.pos - [2]f32{arm, th}, [2]f32{arm * 2, th * 2}, rl.WHITE)
	rl.DrawRectangleV(a.pos - [2]f32{th, arm}, [2]f32{th * 2, arm * 2}, rl.WHITE)
}

icon_barrier :: proc(a: Ally) {
	// A shield: a pale inner disc.
	toon_disc(a.pos, a.radius * 0.5, rl.Color{232, 236, 246, 255})
}
