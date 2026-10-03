package main

import rl "vendor:raylib"

// =============================================================================
// main.odin - window setup and the frame loop. Nothing game-specific lives here.
//
// Project layout (all files are `package main`; build with `odin run .`):
//   config.odin      tunable constants
//   types.odin       data structures (Game owns all state)
//   difficulty.odin  level number -> linear difficulty parameters
//   game.odin        lifecycle, phases, level progression, update loop
//   player.odin      players, shields, enhancements, blast ability
//   enemy.odin       enemy creation, steering, collisions, kills
//   boss.odin        boss spawning, repel + summon behaviour
//   pickups.odin     coins, allies, enhancement drops
//   fx.odin          particles, floating text, shake
//   shaders.odin     GLSL + loaders
//   style.odin       procedural level look, portal
//   render.odin      world drawing
//   hud.odin         HUD and menu screens
// =============================================================================

main :: proc() {
	rl.SetConfigFlags(rl.ConfigFlags{.WINDOW_RESIZABLE})
	rl.InitWindow(SCREEN_W, SCREEN_H, "Odin + Raylib: 2 Player Survival")
	rl.MaximizeWindow()
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	// Gameplay and HUD use a fixed 800x600 logical canvas, stretched to the window.
	canvas := rl.LoadRenderTexture(SCREEN_W, SCREEN_H)
	rl.SetTextureFilter(canvas.texture, .BILINEAR)
	defer rl.UnloadRenderTexture(canvas)

	// Game is large (enemy/particle pools), so keep it on the heap.
	g := new(Game)
	defer free(g)
	game_init(g)
	defer game_shutdown(g)

	for !rl.WindowShouldClose() {
		dt := min(rl.GetFrameTime(), 0.05)
		g.time = f32(rl.GetTime())

		if rl.IsKeyPressed(.F11) do rl.ToggleFullscreen()

		game_update(g, dt)

		rl.BeginDrawing()

		rl.BeginTextureMode(canvas)
		render_world(g)
		render_ui(g)
		rl.EndTextureMode()

		// Stretch the full logical canvas over the current client area.
		rl.ClearBackground(rl.BLACK)
		source := rl.Rectangle{0, 0, f32(SCREEN_W), -f32(SCREEN_H)}
		dest := rl.Rectangle{0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
		rl.DrawTexturePro(canvas.texture, source, dest, {0, 0}, 0, rl.WHITE)

		rl.EndDrawing()

		// Free the temporary strings made by fmt.ctprintf this frame.
		free_all(context.temp_allocator)
	}
}
