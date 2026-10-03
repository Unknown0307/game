package main

import rl "vendor:raylib"

// =============================================================================
// types.odin - plain data. No behaviour lives here.
// =============================================================================

ShipStyle :: enum {
	Fighter,
	Interceptor,
}

EnhancementKind :: enum {
	None,
	Extension, // player body size +5%
	Cooldown,  // ability cooldown -10% per copy
	Damage,    // incoming damage -10% per copy
}

AllyKind :: enum {
	Heal,
	Barrier,
}

EnemyKind :: enum {
	Normal,
	Runner, // small and fast, limited turning
	Big,    // large, slow, hits harder
	Sticky, // the slow "bomb": sticks, waits a few ticks, explodes
	Boss,   // huge, lots of health
}

FloatKind :: enum {
	Score,
	Coin,
	Heal,
	Shield,
	Enhancement,
	Boss,
}

GamePhase :: enum {
	Countdown,
	Playing,
	LevelComplete,
	GameOver,
}

Player :: struct {
	// Identity / controls (set once by make_player)
	name:          cstring,
	controls_text: cstring,
	ready_text:    cstring,
	hud_color:     rl.Color,
	color:         rl.Color,
	ship:          ShipStyle,
	up, down, left, right: rl.KeyboardKey,
	ability_key:   rl.KeyboardKey,
	start_pos:     [2]f32,

	// Run state
	pos, size:     [2]f32,
	speed:         f32,
	knock:         [2]f32, // knock-back velocity (boss repel), decays over time
	kill_count:    i32,
	tag_count:     i32,
	dead:          bool,
	coins:         i32,
	score:         i32,
	ability_cd:    f32,
	visual_timer:  f32,
	hurt_flash:    f32,
	angle:         f32,
	target_angle:  f32,
	shield_ticks:  [MAX_SHIELDS]i32,
	enhancements:  [MAX_ENHANCEMENTS]EnhancementKind,
	enhancement_count: i32,
}

Enemy :: struct {
	pos:      [2]f32,
	radius:   f32,
	speed:    f32,
	color:    rl.Color,
	active:   bool,
	kind:     EnemyKind,
	hp:       i32,
	max_hp:   i32,
	damage:   i32,
	points:   i32,
	hit_cd:   f32,
	flash:    f32,
	heading:  [2]f32, // runner heading
	stuck:    bool,   // sticky bomb state
	stick_ticks: i32,
	stick_pos:   [2]f32,

	// Boss ability state (only used when can_repel is true)
	can_repel:    bool,
	repel_cd:     f32,
	summon_cd:    f32,
	charge:       f32, // > 0 while telegraphing the repel wave
	repel_visual: f32, // > 0 while the repel shockwave is drawn
}

Ally :: struct {
	pos, vel: [2]f32,
	radius:   f32,
	hp:       i32,
	life:     f32,
	pulse:    f32,
	flash:    f32,
	kind:     AllyKind,
	active:   bool,
}

EnhancementPickup :: struct {
	pos:    [2]f32,
	life:   f32,
	pulse:  f32,
	kind:   EnhancementKind,
	active: bool,
}

Coin :: struct {
	pos:    [2]f32,
	life:   f32,
	spin:   f32,
	active: bool,
}

Particle :: struct {
	pos, vel: [2]f32,
	life:     f32,
	max_life: f32,
	size:     f32,
	color:    rl.Color,
}

FloatText :: struct {
	pos:   [2]f32,
	life:  f32,
	value: i32,
	kind:  FloatKind,
}

LevelStyle :: struct {
	background:     rl.Color,
	background_alt: rl.Color,
	grid:           rl.Color,
	accent:         rl.Color,
	accent2:        rl.Color,
	grid_spacing:   i32,
	pattern:        i32,
}

// Everything that depends on the current level number, computed in one place.
LevelParams :: struct {
	level:          i32,
	speed_mult:     f32,
	spawn_interval: f32,
	sticky_chance:  f32,
	big_chance:     f32,
	runner_chance:  f32,
	runner_turn_rate: f32,
	runner_cone:    f32,
	is_boss_level:  bool,
	boss_hp:        i32,
	boss_has_ability: bool,
	boss_summon_cd: f32,
}

// Visual effects state
Fx :: struct {
	particles:     [MAX_PARTICLES]Particle,
	particle_next: int,
	floaters:      [MAX_FLOATS]FloatText,
	float_next:    int,
	shake:         f32,
}

// The single owner of all mutable game state. Systems receive ^Game; nothing
// is stored in package-level variables.
Game :: struct {
	players:     [PLAYER_COUNT]Player,
	enemies:     [MAX_ENEMIES]Enemy,
	allies:      [MAX_ALLIES]Ally,
	coins:       [MAX_COINS]Coin,
	enh_pickups: [MAX_ENH_PICKUPS]EnhancementPickup,
	fx:          Fx,
	shaders:     Shaders,

	phase:        GamePhase,
	level:        i32,
	params:       LevelParams,
	style:        LevelStyle,
	time:         f32, // wall-clock seconds, for animation
	survive_time: f32,
	countdown:    f32,
	portal_open:  f32,

	spawn_timer: f32,
	coin_timer:  f32,
	ally_timer:  f32,
	tick_accum:  f32,
	boss_warn:   f32,
}
