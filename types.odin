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

// Skills are separate from enhancements: found as dice, kept in a wheel.
SkillKind :: enum {
	None,
	Explosion,    // the old repel blast
	Rocket,       // gun fires rockets (small blast) while this skill is the taken one
	Invisibility, // invulnerable for 5 s
	Surprise,     // 40 ticks: everything that touches you is reflected, you take no damage
	Repel,        // 3 s cooldown: shoves every projectile, enemy and the other player 6 ship sizes away
}

SKILLS :: [5]SkillKind{.Explosion, .Repel, .Rocket, .Invisibility, .Surprise}

// What the boss looks like (the whale is the original; the mothership shoots).
BossSkin :: enum {
	Whale,
	Mothership,
}

AllyKind :: enum {
	Heal,
	Barrier,
}

EnemyKind :: enum {
	Normal,
	Runner, // small and fast, limited turning
	Big,    // large, slow, hits harder; shoots bullets (or a short laser for the laser variant)
	Sticky, // the slow "bomb": sticks, waits a few ticks, explodes
	Minion, // baby whale summoned by the boss (runner-like steering)
	Boss,   // huge space whale, lots of health, wraps around the screen
	Asteroid, // drifting rock: flies straight, never chases, drops nothing
}

FloatKind :: enum {
	Score,
	Coin,
	Heal,
	Shield,
	Enhancement,
	Skill,
	Boss,
}

GamePhase :: enum {
	Menu,   // title screen
	Paused, // pause overlay (resumes into `resume_phase`)
	Countdown,
	Playing,
	LevelComplete,
	Sucking, // players + screen are pulled into the portal vortex
	GameOver,
}

MenuPage :: enum {
	Root,     // the main / pause list itself
	Settings,
	Controls,
	Confirm,
}

PendingAction :: enum {
	Restart,
	MainMenu,
	Quit,
}

ShakeLevel :: enum {
	Off,
	Low,
	Full,
}

Settings :: struct {
	shake:    ShakeLevel,
	show_fps: bool,
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
	fire_key:      rl.KeyboardKey, // hold: shoot (bullets, or rockets with the Rocket skill)
	skill_key:     rl.KeyboardKey, // use the taken skill
	cycle_key:     rl.KeyboardKey, // take the next owned skill
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
	fire_cd:       i32, // ticks until the gun may fire again
	skill:         SkillKind,          // the taken skill (None at the start of a run)
	skills_owned:  [SkillKind]bool,
	skill_cd:      [SkillKind]i32,     // per-skill cooldown, in ticks
	invis_ticks:   i32,
	surprise_ticks: i32,
	wheel_w:       [SkillKind]f32,     // animated wheel weights (taken skill = biggest)
	gun_flip:      bool,
	muzzle_flash:  [2]f32,             // seconds left of the flash on each wing gun
	visual_timer:  f32,
	repel_visual:  f32, // seconds left of the Repel shockwave
	hurt_flash:    f32,
	angle:         f32,
	target_angle:  f32,
	thrust:        f32, // 0..1 smoothed engine power (drives the exhaust flame)
	shrink:        f32, // 0 = normal size, 1 = vanished (portal transitions)
	trail:         [PLAYER_TRAIL_LENGTH][2]f32, // recent centre positions, newest first (ship ribbon)
	trail_n:       int,
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
	heading:  [2]f32, // runner / minion heading
	angle:    f32,    // facing, for drawing the ship
	stuck:    bool,   // sticky bomb state
	spin:     f32,    // asteroid tumble (rad/s)
	knock:    [2]f32, // Repel knock-back velocity, decays over time

	// Big enemy weapons
	laser:       bool, // Big variant: fires a short laser instead of bullets
	gun_ticks:   i32,  // ticks until the next shot is allowed
	laser_ticks: i32,  // > 0 while the beam is on
	gun_flip:    bool, // which turret fires next
	stick_ticks: i32,
	stick_pos:   [2]f32,

	// Reflected by the Surprise skill: flies away as a missile that only hurts the *other* player
	reflect_ticks: i32,
	reflect_vel:   [2]f32,
	reflect_owner: i32,

	// Boss skin + mothership weapons (gun_ticks doubles as the bullet cooldown)
	skin:        BossSkin, // minions inherit the skin of the boss that summoned them
	ray_cd:      i32,
	ray_charge:  i32,  // > 0 while aiming the raygun
	ray_ticks:   i32,  // > 0 while the beam is on
	ray_angle:   f32,  // beam direction, locked when it fires

	// Boss ability state (only used when can_repel is true)
	can_repel:    bool,
	repel_cd:     f32,
	summon_cd:    f32,
	charge:       f32, // > 0 while telegraphing the repel wave
	repel_visual: f32, // > 0 while the repel shockwave is drawn
	enraged:      bool,
	dash_cd:      f32,
	dash_windup:  f32, // > 0 while aiming the lunge
	dash_t:       f32, // > 0 while lunging
	dash_dir:     [2]f32,
}

Bullet :: struct {
	pos, vel: [2]f32,
	life:     f32,
	active:   bool,

	// Player shots / reflected shots
	from_player: bool,  // fired by a player's gun: hurts enemies, never players
	rocket:      bool,
	range_left:  f32,   // player shots end after this much travel
	reflected:   bool,  // an enemy bullet turned around by Surprise: hurts the *other* player
	owner:       i32,   // player index (shooter, or the player who reflected it)
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

SkillPickup :: struct {
	pos:    [2]f32,
	life:   f32,
	spin:   f32,
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

// --- Space backdrop ---
BodyKind :: enum {
	Planet,
	GasGiant, // banded, always has rings
	Sun,
	Pulsar,
}

CelestialBody :: struct {
	kind:       BodyKind,
	origin:     [2]f32, // position at age 0
	vel:        [2]f32, // slow drift (px/s)
	radius:     f32,
	color_a:    rl.Color,
	color_b:    rl.Color,
	belt:       bool,   // surrounded by an asteroid belt (=> lots of asteroid spawns)
	belt_scale: f32,    // belt radius / body radius
	belt_speed: f32,    // orbit speed (rad/s)
	spin:       f32,    // pulsar beam / sun ray rotation (rad/s)
	phase:      f32,
	seed:       u32,
}

Backdrop :: struct {
	bodies: [MAX_BODIES]CelestialBody,
	count:  int,
	age:    f32, // seconds since the level began (drives all drifting)
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
	bullets:     [MAX_BULLETS]Bullet,
	coins:       [MAX_COINS]Coin,
	enh_pickups: [MAX_ENH_PICKUPS]EnhancementPickup,
	skill_pickups: [MAX_SKILL_PICKUPS]SkillPickup,
	fx:          Fx,
	shaders:     Shaders,
	backdrop:    Backdrop,

	phase:        GamePhase,
	level:        i32,
	params:       LevelParams,
	style:        LevelStyle,
	time:         f32, // wall-clock seconds, for animation
	survive_time: f32,
	countdown:    f32,
	portal_open:  f32,
	suck_t:       f32, // seconds elapsed in the suck transition
	spit_t:       f32, // seconds remaining in the spit-out transition

	spawn_timer: f32,
	coin_timer:  f32,
	ally_timer:  f32,
	asteroid_timer: f32,
	tick_accum:  f32,
	boss_warn:   f32,

	// Menus / settings
	settings:          Settings,
	menu_page:         MenuPage,
	menu_cursor:       i32,
	menu_saved_cursor: i32,
	pending:           PendingAction,
	resume_phase:      GamePhase,
	quit:              bool,
}
