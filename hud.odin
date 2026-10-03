package main

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

// =============================================================================
// hud.odin - everything drawn in screen space on top of the world: HUD bars,
// countdown, portal screen, boss warning and the game-over screen.
// =============================================================================

UI_MARGIN :: 10
BAR_W     :: 200
BAR_H     :: 16

// --- Text helpers ---

draw_centered :: proc(text: cstring, y, size: i32, color: rl.Color) {
	w := rl.MeasureText(text, size)
	rl.DrawText(text, SCREEN_W / 2 - w / 2, y, size, color)
}

draw_centered_at :: proc(text: cstring, center_x, y, font_size: i32, color: rl.Color) {
	x := center_x - rl.MeasureText(text, font_size) / 2
	rl.DrawText(text, x, y, font_size, color)
}

draw_text_aligned :: proc(text: cstring, x, y, size: i32, color: rl.Color, right_align: bool) {
	px := x
	if right_align do px = x - rl.MeasureText(text, size)
	rl.DrawText(text, px, y, size, color)
}

// --- Bars ---

draw_bar :: proc(x, y, w, h: i32, fraction: f32, color: rl.Color) {
	rl.DrawRectangleLines(x, y, w, h, rl.GRAY)
	rl.DrawRectangle(x + 2, y + 2, i32(f32(w - 4) * clamp(fraction, 0, 1)), h - 4, color)
}

// Health bar with a silver segmented overlay; each segment is one shield.
draw_player_bar :: proc(x, y, w, h: i32, p: Player) {
	draw_bar(x, y, w, h, health_fraction(p), p.color)

	segment_w := f32(w - 4) / f32(MAX_SHIELDS)
	for i in 0 ..< MAX_SHIELDS {
		ticks := p.shield_ticks[i]
		if ticks <= 0 do continue
		fade := f32(ticks) / f32(SHIELD_DURATION_TICKS)
		alpha := 0.28 + 0.58 * fade
		sx := x + 2 + i32(f32(i) * segment_w)
		sw := max(1, i32(segment_w) - 2)
		rl.DrawRectangle(sx, y + 2, sw, h - 4, rl.Fade(SHIELD_COLOR, alpha))
		rl.DrawRectangleLines(sx, y + 2, sw, h - 4, rl.Fade(rl.WHITE, 0.35))
	}
}

draw_enhancement_slots :: proc(p: Player, x, y: i32, right_align: bool) {
	label := fmt.ctprintf("ENH %d/%d", p.enhancement_count, MAX_ENHANCEMENTS)
	slot_w: i32 = 28
	slot_gap: i32 = 4
	slots_width := i32(MAX_ENHANCEMENTS) * slot_w + i32(MAX_ENHANCEMENTS - 1) * slot_gap

	slots_x := x
	if right_align do slots_x = x - slots_width

	draw_text_aligned(label, x, y, 13, rl.Fade(rl.LIGHTGRAY, 0.85), right_align)

	slot_y := y + 16
	for i in 0 ..< MAX_ENHANCEMENTS {
		ii := i32(i)
		sx := slots_x + ii * (slot_w + slot_gap)
		rl.DrawRectangleLines(sx, slot_y, slot_w, 24, rl.Fade(rl.WHITE, 0.35))
		if ii >= p.enhancement_count do continue

		kind := p.enhancements[i]
		tag := enhancement_label(kind)
		rl.DrawRectangle(sx + 2, slot_y + 2, slot_w - 4, 20, rl.Fade(enhancement_color(kind), 0.32))
		rl.DrawText(tag, sx + (slot_w - rl.MeasureText(tag, 10)) / 2, slot_y + 7, 10, rl.WHITE)
	}
}

// --- In-game HUD ---

draw_player_hud :: proc(p: Player, right_align: bool) {
	x: i32 = UI_MARGIN
	bar_x: i32 = UI_MARGIN
	if right_align {
		x = SCREEN_W - UI_MARGIN
		bar_x = SCREEN_W - UI_MARGIN - BAR_W
	}

	status: cstring
	if p.dead {
		status = "DEAD"
	} else if p.ability_cd <= 0 {
		status = p.ready_text
	} else {
		status = fmt.ctprintf("%.1fs", p.ability_cd)
	}

	draw_text_aligned(p.controls_text, x, 10, 20, rl.LIGHTGRAY, right_align)
	draw_text_aligned(fmt.ctprintf("%s Kills: %d | Blast: %s", p.name, p.kill_count, status), x, 35, 18, p.hud_color, right_align)
	draw_player_bar(bar_x, 60, BAR_W, BAR_H, p)
	draw_text_aligned(fmt.ctprintf("Score: %d | Coins: %d | Shields: %d/%d", p.score, p.coins, shield_count(p), MAX_SHIELDS), x, 82, 16, rl.GOLD, right_align)
	draw_enhancement_slots(p, x, 103, right_align)
}

draw_center_hud :: proc(g: ^Game) {
	draw_centered(fmt.ctprintf("LEVEL %d", g.level), 12, 18, rl.WHITE)

	remaining := max(0, level_goal_total(g.level) - total_score(g))
	if remaining == 0 && count_bosses(g) > 0 {
		draw_centered("Defeat the boss!", 35, 14, BOSS_PURPLE)
	} else {
		draw_centered(fmt.ctprintf("Next portal: %d pts", remaining), 35, 14, rl.LIGHTGRAY)
	}

	if g.params.is_boss_level && g.phase != .LevelComplete {
		label: cstring = "BOSS LEVEL"
		if g.params.boss_has_ability do label = "BOSS LEVEL + REPEL"
		draw_centered(label, 54, 14, BOSS_PURPLE)
	}
}

draw_boss_warning :: proc(g: ^Game) {
	if g.boss_warn <= 0 do return
	pulse := 0.5 + 0.5 * math.sin(g.time * 12)
	rl.DrawRectangle(0, 0, SCREEN_W, SCREEN_H, rl.Fade(rl.RED, 0.07 * pulse))
	draw_centered("!! BOSS INCOMING !!", 110, 34, rl.Fade(rl.RED, 0.5 + 0.5 * pulse))
	if g.params.boss_has_ability {
		draw_centered("It repels intruders and summons minions", 150, 18, rl.Fade(BOSS_PURPLE, 0.6 + 0.4 * pulse))
	}
}

// --- Phase screens ---

draw_countdown :: proc(g: ^Game) {
	whole := i32(math.ceil(max(g.countdown, 0.0)))
	if whole <= 0 do return
	rl.DrawRectangle(0, 0, SCREEN_W, SCREEN_H, rl.Fade(rl.BLACK, 0.38))
	draw_centered("GET READY", 185, 28, rl.LIGHTGRAY)
	draw_centered(fmt.ctprintf("%d", whole), 225, 82, rl.WHITE)
	draw_centered(fmt.ctprintf("LEVEL %d", g.level), 325, 24, g.style.accent)
	if g.params.is_boss_level {
		draw_centered("A BOSS is waiting for you", 360, 18, BOSS_PURPLE)
	} else {
		draw_centered("Enemies spawn when the countdown ends", 360, 18, rl.LIGHTGRAY)
	}
}

draw_level_complete :: proc(g: ^Game) {
	style := g.style
	rl.DrawRectangle(0, 0, SCREEN_W, SCREEN_H, rl.Fade(rl.BLACK, 0.12))
	draw_portal(style, g.level, g.portal_open, g.time)
	draw_centered(fmt.ctprintf("LEVEL %d COMPLETE", g.level), 62, 34, style.accent)
	draw_centered(fmt.ctprintf("LEVEL %d", g.level + 1), 505, 24, rl.WHITE)

	if g.portal_open < 1.0 {
		draw_centered("The portal is opening...", 535, 17, rl.LIGHTGRAY)
		return
	}

	if any_enhancement_pickup(g) {
		draw_centered("Enhancement dropped - collect it before entering the portal", 485, 15, rl.WHITE)
	}

	alive, here := 0, 0
	for p in g.players {
		if p.dead do continue
		alive += 1
		if portal_player_inside(p) do here += 1
	}

	if here == alive && alive > 0 {
		draw_centered("ENTERING NEXT LEVEL...", 535, 17, style.accent)
	} else if alive == 1 {
		draw_centered("Reach the portal to continue", 535, 17, rl.LIGHTGRAY)
	} else {
		draw_centered("Both players: reach the portal", 535, 17, rl.LIGHTGRAY)
	}
}

draw_game_over :: proc(g: ^Game) {
	rl.DrawRectangle(0, 0, SCREEN_W, SCREEN_H, rl.Fade(rl.BLACK, 0.70))
	draw_centered("GAME OVER", 105, 56, rl.RED)
	draw_centered(fmt.ctprintf("TOTAL SCORE  %d", total_score(g)), 175, 30, rl.GOLD)

	// One result box per player. No winner/loser label.
	box_w: f32 = 290
	gap: f32 = 40
	start_x := (f32(SCREEN_W) - (box_w * f32(PLAYER_COUNT) + gap * f32(PLAYER_COUNT - 1))) * 0.5
	for p, i in g.players {
		bx := start_x + f32(i) * (box_w + gap)
		rl.DrawRectangleLinesEx(rl.Rectangle{bx, 235, box_w, 105}, 2, rl.Fade(p.hud_color, 0.60))
		cx := i32(bx + box_w * 0.5)
		draw_centered_at(fmt.ctprintf("PLAYER %d", i + 1), cx, 250, 20, p.hud_color)
		draw_centered_at(fmt.ctprintf("Score: %d", p.score), cx, 277, 24, rl.WHITE)
		draw_centered_at(fmt.ctprintf("Kills: %d   Coins: %d", p.kill_count, p.coins), cx, 310, 17, rl.LIGHTGRAY)
	}

	draw_centered(fmt.ctprintf("Reached Level %d  |  Survived %.0f seconds", g.level, g.survive_time), 385, 18, rl.LIGHTGRAY)
	draw_centered("PRESS SPACE TO RESTART", 455, 28, rl.WHITE)
}

// Draws the whole UI layer for the current phase.
render_ui :: proc(g: ^Game) {
	draw_boss_warning(g)

	for p, i in g.players do draw_player_hud(p, i == 1)
	draw_center_hud(g)
	rl.DrawText("F11: Fullscreen", 10, SCREEN_H - 24, 14, rl.Fade(rl.LIGHTGRAY, 0.65))

	switch g.phase {
	case .Countdown:     draw_countdown(g)
	case .LevelComplete: draw_level_complete(g)
	case .GameOver:      draw_game_over(g)
	case .Playing:
	}
}
