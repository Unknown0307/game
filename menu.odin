package main

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

// =============================================================================
// menu.odin - main menu, pause menu, settings, controls and confirm dialogs.
// All pages share one tiny navigation helper (keyboard + mouse).
// =============================================================================

MENU_ITEM_W :: 340
MENU_ITEM_H :: 34

MenuInput :: struct {
	activate: bool, // Enter / Space / left click on an item
	step:     i32,  // -1 / +1 from Left / Right (A / D)
}

// --- Navigation helpers ---

// The mouse position in logical (800x600) canvas coordinates, even when the
// window is stretched or fullscreen.
mouse_logical :: proc() -> [2]f32 {
	m := rl.GetMousePosition()
	return {
		m.x * f32(SCREEN_W) / f32(rl.GetScreenWidth()),
		m.y * f32(SCREEN_H) / f32(rl.GetScreenHeight()),
	}
}

menu_item_rect :: proc(i, y0, spacing: i32) -> rl.Rectangle {
	return rl.Rectangle{
		f32(SCREEN_W / 2 - MENU_ITEM_W / 2),
		f32(y0 + i * spacing),
		MENU_ITEM_W,
		MENU_ITEM_H,
	}
}

// Moves the cursor (keys + mouse hover) and reports activation / value steps.
menu_navigate :: proc(g: ^Game, count: i32, y0, spacing: i32) -> MenuInput {
	res: MenuInput

	if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressed(.S) do g.menu_cursor = (g.menu_cursor + 1) % count
	if rl.IsKeyPressed(.UP)   || rl.IsKeyPressed(.W) do g.menu_cursor = (g.menu_cursor + count - 1) % count
	if rl.IsKeyPressed(.LEFT)  || rl.IsKeyPressed(.A) do res.step = -1
	if rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressed(.D) do res.step = 1
	if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.SPACE) do res.activate = true

	m := mouse_logical()
	delta := rl.GetMouseDelta()
	moved := delta.x != 0 || delta.y != 0
	for i in 0 ..< count {
		if !rl.CheckCollisionPointRec(m, menu_item_rect(i, y0, spacing)) do continue
		if moved do g.menu_cursor = i
		if rl.IsMouseButtonPressed(.LEFT) {
			g.menu_cursor = i
			res.activate = true
		}
	}
	return res
}

draw_menu_items :: proc(g: ^Game, labels: []cstring, y0, spacing: i32) {
	accent := g.style.accent
	for label, i in labels {
		ii := i32(i)
		r := menu_item_rect(ii, y0, spacing)
		selected := ii == g.menu_cursor
		if selected {
			pulse := 0.5 + 0.5 * math.sin(g.time * 6)
			rl.DrawRectangleRec(r, rl.Fade(accent, 0.16 + 0.08 * pulse))
			rl.DrawRectangleLinesEx(r, 2, rl.Fade(accent, 0.95))
			rl.DrawText(">", i32(r.x) + 12, i32(r.y) + 7, 20, accent)
			rl.DrawText("<", i32(r.x + r.width) - 24, i32(r.y) + 7, 20, accent)
		} else {
			rl.DrawRectangleLinesEx(r, 1, rl.Fade(rl.WHITE, 0.18))
		}
		col := rl.LIGHTGRAY
		if selected do col = rl.WHITE
		draw_centered(label, i32(r.y) + 7, 20, col)
	}
}

// --- Page / state helpers ---

open_menu :: proc(g: ^Game) {
	g.phase       = .Menu
	g.menu_page   = .Root
	g.menu_cursor = 0
}

open_page :: proc(g: ^Game, page: MenuPage) {
	g.menu_saved_cursor = g.menu_cursor
	g.menu_cursor = 0
	g.menu_page = page
}

close_page :: proc(g: ^Game) {
	g.menu_page   = .Root
	g.menu_cursor = g.menu_saved_cursor
}

open_confirm :: proc(g: ^Game, action: PendingAction) {
	g.pending = action
	open_page(g, .Confirm)
	g.menu_cursor = 1 // default to "NO"
}

execute_pending :: proc(g: ^Game) {
	switch g.pending {
	case .Restart:  reset_run(g)
	case .MainMenu: reset_run(g); open_menu(g)
	case .Quit:     g.quit = true
	}
}

pausable :: proc(g: ^Game) -> bool {
	switch g.phase {
	case .Countdown, .Playing, .LevelComplete:
		return g.spit_t <= 0 // not while being spat out of the portal
	case .Sucking, .GameOver, .Menu, .Paused:
		return false
	}
	return false
}

should_pause :: proc(g: ^Game) -> bool {
	if !pausable(g) do return false
	return rl.IsKeyPressed(.ESCAPE) || rl.IsKeyPressed(.P) || !rl.IsWindowFocused()
}

pause_game :: proc(g: ^Game) {
	g.resume_phase = g.phase
	g.phase        = .Paused
	g.menu_page    = .Root
	g.menu_cursor  = 0
}

resume_game :: proc(g: ^Game) {
	g.phase     = g.resume_phase
	g.menu_page = .Root
}

// --- Settings helpers ---

shake_scale :: proc(s: Settings) -> f32 {
	switch s.shake {
	case .Off:  return 0
	case .Low:  return 0.4
	case .Full: return 1
	}
	return 1
}

shake_name :: proc(k: ShakeLevel) -> cstring {
	switch k {
	case .Off:  return "OFF"
	case .Low:  return "LOW"
	case .Full: return "FULL"
	}
	return "FULL"
}

on_off :: proc(b: bool) -> cstring {
	if b do return "ON"
	return "OFF"
}

cycle_shake :: proc(k: ShakeLevel, step: i32) -> ShakeLevel {
	n: i32 = 3
	return ShakeLevel((i32(k) + step + n) % n)
}

// --- Updates ---

update_menu :: proc(g: ^Game) {
	switch g.menu_page {
	case .Root:
		if g.phase == .Menu {
			update_main_menu(g)
		} else {
			update_pause_menu(g)
		}
	case .Settings: update_settings_page(g)
	case .Controls: update_controls_page(g)
	case .Confirm:  update_confirm_page(g)
	}
}

update_main_menu :: proc(g: ^Game) {
	nav := menu_navigate(g, 4, 230, 48)
	if !nav.activate do return
	switch g.menu_cursor {
	case 0: reset_run(g) // starts the level-1 countdown
	case 1: open_page(g, .Controls)
	case 2: open_page(g, .Settings)
	case 3: g.quit = true
	}
}

update_pause_menu :: proc(g: ^Game) {
	if rl.IsKeyPressed(.ESCAPE) || rl.IsKeyPressed(.P) {
		resume_game(g)
		return
	}
	nav := menu_navigate(g, 6, 200, 46)
	if !nav.activate do return
	switch g.menu_cursor {
	case 0: resume_game(g)
	case 1: open_confirm(g, .Restart)
	case 2: open_page(g, .Controls)
	case 3: open_page(g, .Settings)
	case 4: open_confirm(g, .MainMenu)
	case 5: open_confirm(g, .Quit)
	}
}

update_settings_page :: proc(g: ^Game) {
	if rl.IsKeyPressed(.ESCAPE) {
		close_page(g)
		return
	}
	nav := menu_navigate(g, 4, 220, 52)
	changed := nav.activate || nav.step != 0
	step := nav.step
	if step == 0 do step = 1

	switch g.menu_cursor {
	case 0: if changed do g.settings.shake = cycle_shake(g.settings.shake, step)
	case 1: if changed do g.settings.show_fps = !g.settings.show_fps
	case 2: if changed do rl.ToggleFullscreen()
	case 3: if nav.activate do close_page(g)
	}
}

update_controls_page :: proc(g: ^Game) {
	nav := menu_navigate(g, 1, 510, 46)
	if nav.activate || rl.IsKeyPressed(.ESCAPE) do close_page(g)
}

update_confirm_page :: proc(g: ^Game) {
	if rl.IsKeyPressed(.ESCAPE) {
		close_page(g)
		return
	}
	nav := menu_navigate(g, 2, 300, 48)
	if !nav.activate do return
	if g.menu_cursor == 0 {
		execute_pending(g)
	} else {
		close_page(g)
	}
}

// --- Drawing ---

draw_settings_page :: proc(g: ^Game) {
	draw_centered("SETTINGS", 90, 40, rl.WHITE)
	labels := [?]cstring{
		fmt.ctprintf("SCREEN SHAKE: %s", shake_name(g.settings.shake)),
		fmt.ctprintf("SHOW FPS: %s", on_off(g.settings.show_fps)),
		fmt.ctprintf("FULLSCREEN: %s", on_off(rl.IsWindowFullscreen())),
		"BACK",
	}
	draw_menu_items(g, labels[:], 220, 52)
	draw_centered("Left / Right or Enter to change   |   Esc: back", 480, 16, rl.Fade(rl.LIGHTGRAY, 0.8))
}

draw_controls_page :: proc(g: ^Game) {
	draw_centered("CONTROLS", 50, 40, rl.WHITE)

	box_w: f32 = 300
	gap: f32 = 40
	start_x := (f32(SCREEN_W) - (box_w * 2 + gap)) * 0.5
	names    := [2]cstring{"PLAYER 1", "PLAYER 2"}
	moves    := [2]cstring{"Move:  W A S D", "Move:  Arrow keys"}
	fires    := [2]cstring{"Auto-fire (F: manual)", "Auto-fire (.: manual)"}
	skills   := [2]cstring{"Skill:  R   Next skill:  E", "Skill:  /   Next skill:  ,"}
	for i in 0 ..< 2 {
		bx := start_x + f32(i) * (box_w + gap)
		col := g.players[i].hud_color
		rl.DrawRectangleLinesEx(rl.Rectangle{bx, 110, box_w, 140}, 2, rl.Fade(col, 0.7))
		cx := i32(bx + box_w * 0.5)
		draw_centered_at(names[i], cx, 120, 22, col)
		draw_centered_at(moves[i], cx, 154, 20, rl.WHITE)
		draw_centered_at(fires[i], cx, 180, 20, rl.WHITE)
		draw_centered_at(skills[i], cx, 206, 18, rl.WHITE)
	}

	draw_centered("Pause:  Esc or P        Fullscreen:  F11", 268, 20, rl.WHITE)

	draw_centered("Score together to fill the level goal, then both players", 308, 17, rl.LIGHTGRAY)
	draw_centered("fly into the portal. A dead player returns next level.", 330, 17, rl.LIGHTGRAY)
	draw_centered("Guns auto-fire with homing shots. Skill dice (rare) roll a skill into your wheel:", 362, 17, rl.LIGHTGRAY)
	draw_centered("Explosion, Repel (3s), Rocket Bullets, Invisibility, Surprise (reflects).", 384, 17, rl.LIGHTGRAY)
	draw_centered("Reflected enemies and bullets can hurt the OTHER player!", 406, 17, rl.LIGHTGRAY)
	draw_centered("Coins add score. Green allies heal, grey allies grant shields.", 432, 17, rl.LIGHTGRAY)
	draw_centered("Up to 3 enhancements can be collected per player.", 454, 17, rl.LIGHTGRAY)

	labels := [?]cstring{"BACK"}
	draw_menu_items(g, labels[:], 515, 46)
}

draw_confirm_page :: proc(g: ^Game) {
	title: cstring
	switch g.pending {
	case .Restart:  title = "Restart the run?"
	case .MainMenu: title = "Return to the main menu?"
	case .Quit:     title = "Quit the game?"
	}
	draw_centered(title, 190, 34, rl.WHITE)
	draw_centered("Your current progress will be lost.", 240, 18, rl.LIGHTGRAY)
	labels := [?]cstring{"YES", "NO"}
	draw_menu_items(g, labels[:], 300, 48)
}

draw_main_menu :: proc(g: ^Game) {
	rl.DrawRectangle(0, 0, SCREEN_W, SCREEN_H, rl.Fade(rl.BLACK, 0.55))
	switch g.menu_page {
	case .Root:
		draw_centered("2 PLAYER SURVIVAL", 85, 46, rl.WHITE)
		draw_centered("Survive together. Score. Reach the portal.", 145, 18, rl.LIGHTGRAY)
		labels := [?]cstring{"START GAME", "CONTROLS", "SETTINGS", "QUIT"}
		draw_menu_items(g, labels[:], 230, 48)
		draw_centered("W / S or mouse to navigate   |   Enter to select", 520, 16, rl.Fade(rl.LIGHTGRAY, 0.8))
	case .Settings: draw_settings_page(g)
	case .Controls: draw_controls_page(g)
	case .Confirm:  draw_confirm_page(g)
	}
}

draw_pause_menu :: proc(g: ^Game) {
	rl.DrawRectangle(0, 0, SCREEN_W, SCREEN_H, rl.Fade(rl.BLACK, 0.68))
	switch g.menu_page {
	case .Root:
		draw_centered("PAUSED", 90, 46, rl.WHITE)
		draw_centered(fmt.ctprintf("Level %d   |   Score %d", g.level, total_score(g)), 150, 18, rl.LIGHTGRAY)
		labels := [?]cstring{"RESUME", "RESTART RUN", "CONTROLS", "SETTINGS", "MAIN MENU", "QUIT GAME"}
		draw_menu_items(g, labels[:], 200, 46)
		draw_centered("Esc or P to resume", 500, 16, rl.Fade(rl.LIGHTGRAY, 0.8))
	case .Settings: draw_settings_page(g)
	case .Controls: draw_controls_page(g)
	case .Confirm:  draw_confirm_page(g)
	}
}

draw_fps :: proc(g: ^Game) {
	if !g.settings.show_fps do return
	text := fmt.ctprintf("%d FPS", rl.GetFPS())
	rl.DrawText(text, SCREEN_W - rl.MeasureText(text, 14) - 10, SCREEN_H - 24, 14, rl.Fade(rl.LIME, 0.85))
}
