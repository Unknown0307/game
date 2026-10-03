package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import rl "vendor:raylib"

// --- Configuration & Data Structures ---
SCREEN_W :: 800
SCREEN_H :: 600

MAX_ENEMIES :: 500
MAX_COINS :: 24
MAX_ALLIES :: 4
MAX_PARTICLES :: 2000
MAX_FLOATS :: 32

REPULSION_RADIUS :: 180.0
ABILITY_COOLDOWN :: 2.0
// Enemy pacing is intentionally gentler than the original build.
ENEMY_SPEED_MULT :: 0.70
LEVEL_SPEED_STEP :: 0.05
PLAYER_MAX_SPEED: f32 = 300.0
RUNNER_TURN_RATE: f32 = 0.85 // radians/second; intentionally gentle steering
RUNNER_MAX_CURVE_ANGLE: f32 = 0.38 // radians (~22 degrees) from the current heading
LEVEL_SCORE_STEP :: 1000 // every 1000 total score starts the next level
LEVEL_COUNTDOWN :: 10.0
PORTAL_OPEN_TIME :: 1.25
PORTAL_RADIUS :: 58.0
PORTAL_PULL_RADIUS :: 150.0
MAX_TAGS :: 50 // a player dies when enemies have tagged them this many times

// Shields / barriers
MAX_SHIELDS :: 3
SHIELD_DURATION_TICKS :: 300
BARRIER_ALLY_CHANCE: f32 = 0.30

// Sticky enemy
STICKY_STICK_TICKS :: 5
STICKY_EXPLOSION_RADIUS: f32 = 54.0
STICKY_EXPLOSION_DAMAGE :: 10

// Permanent enhancement slots
MAX_ENHANCEMENTS :: 3
ENHANCEMENT_SPAWN_CHANCE: f32 = 0.05

// Boss: every BOSS_CHECK_TICKS ticks there is a BOSS_CHANCE chance one spawns.
// One tick = 1/TICK_RATE seconds (60 ticks per second, same as the target FPS).
TICK_RATE :: 60.0
TICK_DT :: 1.0 / TICK_RATE
BOSS_CHECK_TICKS :: 300
BOSS_CHANCE :: 0.01
MAX_BOSSES :: 2 // safety cap so bosses can't pile up forever
BOSS_HP :: 6 // each blast that hits the boss does 1 damage
BOSS_RADIUS :: 48.0
BOSS_DAMAGE :: 8 // tags dealt to a player per boss hit
BOSS_HIT_COOLDOWN :: 1.2
BOSS_SCORE :: 200

// Pickups
COIN_RADIUS :: 9.0
COIN_LIFETIME :: 10.0
COIN_SCORE :: 10 // score added per coin collected
COIN_DROP_CHANCE :: 0.25 // chance a killed enemy drops a coin
ALLY_RADIUS :: 14.0
ALLY_HP :: 3
ALLY_LIFETIME :: 15.0
HEAL_AMOUNT :: 10 // tags removed from the player who grabs an ally

BG_COLOR :: rl.Color{16, 18, 28, 255}

Player :: struct {
	pos:              [2]f32,
	size:             [2]f32,
	speed:            f32,
	color:            rl.Color,
	up, down, left, right: rl.KeyboardKey,
	ability_key:      rl.KeyboardKey,
	kill_count:       i32, // Enemies killed by the blast
	tag_count:        i32, // Times an enemy has touched this player
	dead:             bool,
	coins:            i32,
	score:            i32,
	ability_cd:       f32, // Remaining cooldown time in seconds
	visual_timer:     f32, // Shockwave visual duration
	hurt_flash:       f32, // Blink timer after taking a hit
	angle:            f32, // Current ship facing angle in radians
	target_angle:     f32, // Desired facing angle from movement direction
	shield_ticks:     [MAX_SHIELDS]i32, // each shield has its own 300-tick lifetime
	enhancements:     [MAX_ENHANCEMENTS]EnhancementKind,
	enhancement_count: i32,
}

EnhancementKind :: enum {
	None,
	Extension, // player body radius/size +5%
	Cooldown,  // ability cooldown -10% per copy
	Damage,    // incoming damage -10% per copy
}

AllyKind :: enum {
	Heal,
	Barrier,
}

EnemyKind :: enum {
	Normal,
	Runner, // small and fast, but limited in turning curvature
	Big,    // large (random size) and slow, hits harder
	Sticky, // very slow, sticks, waits 5 ticks, then explodes
	Boss,   // huge, fast, lots of health
}

Enemy :: struct {
	pos:    [2]f32,
	radius: f32,
	speed:  f32,
	color:  rl.Color,
	active: bool,
	kind:   EnemyKind,
	hp:     i32,
	max_hp: i32,
	damage: i32, // tags dealt on contact
	points: i32, // score for the player that kills it
	hit_cd: f32, // boss only: time until it can hurt again
	flash:  f32, // white hit-flash timer
	heading: [2]f32, // runner heading for curvature-limited movement
	stuck: bool,
	stick_ticks: i32,
	stick_pos: [2]f32,
	stick_player: i32,
}

Ally :: struct {
	pos:    [2]f32,
	vel:    [2]f32,
	radius: f32,
	hp:     i32,
	life:   f32, // seconds until it wanders off
	pulse:  f32,
	flash:  f32,	
	kind:   AllyKind,
	active: bool,
}

EnhancementPickup :: struct {
	pos:   [2]f32,
	pulse: f32,
	spin:  f32,
	kind:  EnhancementKind,
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

FloatKind :: enum {
	Score,
	Coin,
	Heal,
	Shield,
	Enhancement,
	Boss,
}

FloatText :: struct {
	pos:   [2]f32,
	life:  f32,
	value: i32,
	kind:  FloatKind,
}

GamePhase :: enum {
    Countdown,
    Playing,
    LevelComplete,
    GameOver,
}

LevelStyle :: struct {
    background: rl.Color,
    background_alt: rl.Color,
    grid: rl.Color,
    accent: rl.Color,
    accent2: rl.Color,
    grid_spacing: i32,
    pattern: i32,
}

// --- World / FX state (package level so helper procs can reach it) ---
enemies:   [MAX_ENEMIES]Enemy
allies:    [MAX_ALLIES]Ally
coins:     [MAX_COINS]Coin
particles: [MAX_PARTICLES]Particle
floaters:  [MAX_FLOATS]FloatText

particle_next: int
float_next:    int
shake:         f32 // current screen-shake strength in pixels
enhancement_pickup: EnhancementPickup

// --- Blast Shader ---
// Fragment shader drawn over a quad around the player: a glowing ring at the wave
// front, a rippling glow filling the inside, all fading out as the blast ends.
BLAST_FS: cstring : `#version 330
out vec4 finalColor;

uniform vec2  center;     // blast centre in framebuffer pixels (origin bottom-left)
uniform float radius;     // current wave radius
uniform float maxRadius;  // full blast radius
uniform float progress;   // 0 -> 1 over the blast duration
uniform vec3  tint;       // player colour

void main() {
    float d = distance(gl_FragCoord.xy, center);
    float fade = 1.0 - progress;

    float edge   = 1.0 - smoothstep(0.0, 12.0, abs(d - radius));
    float inner  = (1.0 - smoothstep(0.0, maxRadius, d)) * step(d, radius);
    float ripple = 0.5 + 0.5 * sin(d * 0.35 - progress * 40.0);

    float a = clamp(edge * 1.2 + inner * (0.25 + 0.2 * ripple), 0.0, 1.0) * fade;
    vec3 col = mix(tint, vec3(1.0), edge * 0.6);
    finalColor = vec4(col, a);
}
`

BlastShader :: struct {
	shader:     rl.Shader,
	center_loc: i32,
	radius_loc: i32,
	max_loc:    i32,
	prog_loc:   i32,
	tint_loc:   i32,
}

load_blast_shader :: proc() -> BlastShader {
	sh := rl.LoadShaderFromMemory(nil, BLAST_FS) // nil = default vertex shader
	return BlastShader{
		shader     = sh,
		center_loc = rl.GetShaderLocation(sh, "center"),
		radius_loc = rl.GetShaderLocation(sh, "radius"),
		max_loc    = rl.GetShaderLocation(sh, "maxRadius"),
		prog_loc   = rl.GetShaderLocation(sh, "progress"),
		tint_loc   = rl.GetShaderLocation(sh, "tint"),
	}
}


// --- Player Ship Shader ---
// A lightweight procedural fragment shader gives the ships an animated energy skin
// without requiring sprite/image assets. Geometry is still custom-drawn per player.
SHIP_FS: cstring : `#version 330
in vec4 fragColor;
uniform float time;
uniform vec3 tint;
out vec4 finalColor;
void main() {
    float pulse = 0.5 + 0.5 * sin(time * 8.0);
    float scan = 0.5 + 0.5 * sin(gl_FragCoord.y * 0.16 - time * 10.0);
    vec3 base = mix(fragColor.rgb, tint, 0.45);
    vec3 energy = mix(base, vec3(1.0), 0.18 + 0.12 * pulse + 0.10 * scan);
    finalColor = vec4(energy, fragColor.a);
}
`

ShipShader :: struct {
    shader: rl.Shader,
    time_loc: i32,
    tint_loc: i32,
}

load_ship_shader :: proc() -> ShipShader {
    sh := rl.LoadShaderFromMemory(nil, SHIP_FS)
    return ShipShader{
        shader = sh,
        time_loc = rl.GetShaderLocation(sh, "time"),
        tint_loc = rl.GetShaderLocation(sh, "tint"),
    }
}

// progress: 0 at the moment of the blast, 1 when it has finished
draw_blast :: proc(b: BlastShader, center: [2]f32, progress: f32, tint: [3]f32, screen_h: f32) {
	c := [2]f32{center.x, screen_h - center.y} // gl_FragCoord has a bottom-left origin
	radius := progress * f32(REPULSION_RADIUS)
	max_radius := f32(REPULSION_RADIUS)
	p := progress
	t := tint

	rl.SetShaderValue(b.shader, i32(b.center_loc), &c, .VEC2)
	rl.SetShaderValue(b.shader, i32(b.radius_loc), &radius, .FLOAT)
	rl.SetShaderValue(b.shader, i32(b.max_loc), &max_radius, .FLOAT)
	rl.SetShaderValue(b.shader, i32(b.prog_loc), &p, .FLOAT)
	rl.SetShaderValue(b.shader, i32(b.tint_loc), &t, .VEC3)

	extent := i32(REPULSION_RADIUS) + 40
	rl.BeginBlendMode(.ADDITIVE)
	rl.BeginShaderMode(b.shader)
	rl.DrawRectangle(i32(center.x) - extent, i32(center.y) - extent, extent * 2, extent * 2, rl.WHITE)
	rl.EndShaderMode()
	rl.EndBlendMode()
}

// Health is the share of tags a player has left before dying (1.0 = full, 0.0 = dead)
health_fraction :: proc(p: Player) -> f32 {
	return max(0, 1 - f32(p.tag_count) / f32(MAX_TAGS))
}

shield_count :: proc(p: Player) -> i32 {
	n: i32 = 0
	for ticks in p.shield_ticks {
		if ticks > 0 do n += 1
	}
	return n
}

// Health plus a silver, segmented barrier overlay. Each silver segment is one shield.
draw_health_bar :: proc(x, y, w, h: i32, fraction: f32, color: rl.Color, p: Player) {
	rl.DrawRectangleLines(x, y, w, h, rl.GRAY)
	rl.DrawRectangle(x + 2, y + 2, i32(f32(w - 4) * fraction), h - 4, color)

	segment_w := f32(w - 4) / f32(MAX_SHIELDS)
	for i in 0 ..< MAX_SHIELDS {
		ticks := p.shield_ticks[i]
		if ticks <= 0 do continue
		fade := f32(ticks) / f32(SHIELD_DURATION_TICKS)
		alpha := 0.28 + 0.58 * fade
		sx := x + 2 + i32(f32(i) * segment_w)
		sw := max(1, i32(segment_w) - 2)
		rl.DrawRectangle(sx, y + 2, sw, h - 4, rl.Fade(rl.Color{215, 220, 228, 255}, alpha))
		rl.DrawRectangleLines(sx, y + 2, sw, h - 4, rl.Fade(rl.WHITE, 0.35))
	}
}

// --- FX helpers ---
add_shake :: proc(amount: f32) {
	shake = min(max(shake, amount), 20)
}

spawn_particle :: proc(pos, vel: [2]f32, color: rl.Color, life, size: f32) {
	particles[particle_next] = Particle{pos = pos, vel = vel, life = life, max_life = life, size = size, color = color}
	particle_next = (particle_next + 1) % MAX_PARTICLES
}

// Radial burst of sparks
spawn_burst :: proc(pos: [2]f32, color: rl.Color, count: int, speed: f32, size: f32 = 3.0) {
	for _ in 0 ..< count {
		ang := rand.float32_range(0, 2 * math.PI)
		spd := rand.float32_range(0.3, 1.0) * speed
		vel := [2]f32{math.cos(ang), math.sin(ang)} * spd
		spawn_particle(pos, vel, color, rand.float32_range(0.3, 0.7), rand.float32_range(size * 0.6, size * 1.4))
	}
}

add_float :: proc(pos: [2]f32, value: i32, kind: FloatKind) {
	p := [2]f32{clamp(pos.x, 20, SCREEN_W - 20), clamp(pos.y, 20, SCREEN_H - 20)}
	floaters[float_next] = FloatText{pos = p, life = 2.0 if kind == .Boss else 1.0, value = value, kind = kind}
	float_next = (float_next + 1) % MAX_FLOATS
}

// Soft additive glow built from a few stacked translucent circles (call inside additive blend mode)
draw_glow :: proc(pos: [2]f32, radius: f32, color: rl.Color, intensity: f32) {
	for i in 0 ..< 4 {
		k := f32(i) / 4.0
		rl.DrawCircleV(pos, radius * (1.0 - k * 0.75), rl.Fade(color, intensity * 0.25))
	}
}

draw_centered :: proc(text: cstring, y, size: i32, color: rl.Color) {
	w := rl.MeasureText(text, size)
	rl.DrawText(text, SCREEN_W / 2 - w / 2, y, size, color)
}

draw_centered_at :: proc(text: cstring, center_x, y, font_size: i32, color: rl.Color) {
	x := center_x - rl.MeasureText(text, font_size) / 2
	rl.DrawText(text, x, y, font_size, color)
}


// --- Spawning ---
spawn_coin_at :: proc(pos: [2]f32) {
	for &c in coins {
		if !c.active {
			c = Coin{
				pos    = {clamp(pos.x, 24, SCREEN_W - 24), clamp(pos.y, 110, SCREEN_H - 24)},
				life   = COIN_LIFETIME,
				spin   = rand.float32_range(0, 6.28),
				active = true,
			}
			return
		}
	}
}

count_active_coins :: proc() -> int {
	n := 0
	for c in coins {
		if c.active {
			n += 1
		}
	}
	return n
}

spawn_ally :: proc() {
	for &a in allies {
		if !a.active {
			ang := rand.float32_range(0, 2 * math.PI)
			kind := AllyKind.Heal
			if rand.float32() < BARRIER_ALLY_CHANCE {
				kind = .Barrier
			}
			a = Ally{
				pos    = {rand.float32_range(60, SCREEN_W - 60), rand.float32_range(130, SCREEN_H - 60)},
				vel    = [2]f32{math.cos(ang), math.sin(ang)} * rand.float32_range(25, 45),
				radius = ALLY_RADIUS,
				hp     = ALLY_HP if kind == .Heal else 1,
				life   = ALLY_LIFETIME,
				kind   = kind,
				active = true,
			}
			if kind == .Barrier {
				spawn_burst(a.pos, rl.Color{215, 220, 228, 255}, 20, 120, 3)
			} else {
				spawn_burst(a.pos, rl.LIME, 20, 120, 3)
			}
			return
		}
	}
}

count_active_allies :: proc() -> int {
	n := 0
	for a in allies {
		if a.active {
			n += 1
		}
	}
	return n
}

count_bosses :: proc() -> int {
	n := 0
	for e in enemies {
		if e.active && e.kind == .Boss {
			n += 1
		}
	}
	return n
}

// Spawns an enemy of the given kind just off a random screen edge
spawn_enemy :: proc(kind: EnemyKind, level_speed_mult: f32) {
	for &e in enemies {
		if e.active {
			continue
		}
		e = Enemy{kind = kind, active = true, hp = 1, max_hp = 1, damage = 1, points = 10}

		switch kind {
		case .Normal:
			e.radius = 12.0
			e.speed  = rand.float32_range(90.0, 150.0) * level_speed_mult
			e.color  = rl.RED
			e.points = 10
		case .Runner:
			e.radius = 8.0
			e.speed  = rand.float32_range(150.0, 210.0) * level_speed_mult
			e.color  = rl.ORANGE
			e.points = 15
		case .Big:
			// Random size: bigger ones are slower, hit harder and are worth more
			e.radius = rand.float32_range(20.0, 34.0)
			e.speed  = (75.0 - (e.radius - 20.0) * 2.5) * level_speed_mult
			e.color  = rl.Color{190, 35, 70, 255}
			e.damage = 2
			if e.radius >= 27.0 {
				e.damage = 3
			}
			e.points = i32(e.radius * 1.5)
		case .Sticky:
			e.radius = 10.0
			e.speed  = rand.float32_range(42.0, 62.0) * level_speed_mult
			e.color  = rl.Color{255, 80, 210, 255}
			e.damage = STICKY_EXPLOSION_DAMAGE
			e.points = 25
		case .Boss:
			e.radius = BOSS_RADIUS
			e.speed  = 190.0 * level_speed_mult
			e.color  = rl.Color{180, 60, 255, 255}
			e.hp     = BOSS_HP
			e.max_hp = BOSS_HP
			e.damage = BOSS_DAMAGE
			e.points = BOSS_SCORE
		}

		pad := e.radius + 10
		switch rand.int31_max(4) {
		case 0:
			e.pos = {rand.float32_range(0, SCREEN_W), -pad}
		case 1:
			e.pos = {SCREEN_W + pad, rand.float32_range(0, SCREEN_H)}
		case 2:
			e.pos = {rand.float32_range(0, SCREEN_W), SCREEN_H + pad}
		case:
			e.pos = {-pad, rand.float32_range(0, SCREEN_H)}
		}
		return
	}
}

// --- Gameplay helpers ---
kill_enemy :: proc(e: ^Enemy, killer: ^Player) {
	e.active = false
	killer.kill_count += 1
	killer.score += e.points

	fk := FloatKind.Score
	if e.kind == .Boss {
		fk = .Boss
	}
	add_float(e.pos, e.points, fk)
	spawn_burst(e.pos, e.color, 10 + int(e.radius), 220, 3)

	if e.kind == .Boss {
		spawn_burst(e.pos, rl.GOLD, 80, 420, 5)
		spawn_burst(e.pos, rl.WHITE, 40, 300, 4)
		add_shake(18)
		for _ in 0 ..< 8 {
			spawn_coin_at(e.pos + [2]f32{rand.float32_range(-50, 50), rand.float32_range(-50, 50)})
		}
	} else if rand.float32() < COIN_DROP_CHANCE {
		spawn_coin_at(e.pos)
	}
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
	for _ in 0 ..< count_enhancement(p, .Cooldown) {
		mult *= 0.90
	}
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
		p.size *= f32(1.05)
	case .Cooldown:
		// The next cast uses the new multiplier. Existing cooldown is scaled too
		// so the enhancement is immediately meaningful if picked up mid-countdown.
		p.ability_cd *= 0.90
	case .Damage:
		// Damage reduction is calculated dynamically from the stack count.
	case .None:
	}
	return true
}

consume_shield :: proc(p: ^Player) -> bool {
	slot: i32 = -1
	lowest: i32 = SHIELD_DURATION_TICKS + 1
	for i in 0 ..< MAX_SHIELDS {
		if p.shield_ticks[i] > 0 && p.shield_ticks[i] < lowest {
			lowest = p.shield_ticks[i]
			slot = i32(i)
		}
	}
	if slot < 0 {
		return false
	}

	p.shield_ticks[slot] = 0
	center := p.pos + p.size * 0.5
	spawn_burst(center, rl.Color{215, 220, 228, 255}, 18, 190, 3)
	add_float(center + [2]f32{0, -18}, 1, .Shield)
	add_shake(2.5)
	return true
}

add_shield :: proc(p: ^Player) {
	// Prefer an empty slot. If full, refresh the shield with the least time left.
	slot: i32 = -1
	lowest: i32 = SHIELD_DURATION_TICKS + 1
	for i in 0 ..< MAX_SHIELDS {
		if p.shield_ticks[i] <= 0 {
			slot = i32(i)
			break
		}
		if p.shield_ticks[i] < lowest {
			lowest = p.shield_ticks[i]
			slot = i32(i)
		}
	}
	if slot >= 0 {
		p.shield_ticks[slot] = SHIELD_DURATION_TICKS
		center := p.pos + p.size * 0.5
		spawn_burst(center, rl.Color{215, 220, 228, 255}, 28, 220, 3.5)
		add_float(center + [2]f32{0, -18}, 1, .Shield)
	}
}

refresh_shield_timers_tick :: proc(p: ^Player) {
	for i in 0 ..< MAX_SHIELDS {
		if p.shield_ticks[i] > 0 do p.shield_ticks[i] -= 1
	}
}

hurt_player :: proc(p: ^Player, amount: i32) {
	if p.dead || amount <= 0 {
		return
	}

	// A barrier consumes the hit before health is touched.
	if consume_shield(p) {
		p.hurt_flash = 0.12
		return
	}

	reduction: f32 = 1.0
	for _ in 0 ..< count_enhancement(p^, .Damage) {
		reduction *= 0.90
	}
	effective := max(1, i32(math.ceil(f32(amount) * reduction)))
	p.tag_count += effective
	p.hurt_flash = 0.3
	center := p.pos + p.size * 0.5
	spawn_burst(center, rl.RED, int(8 + effective * 2), 170, 3)
	add_shake(min(3 + f32(effective), 12))

	if p.tag_count >= MAX_TAGS {
		p.tag_count = MAX_TAGS
		p.dead = true
		for i in 0 ..< MAX_SHIELDS do p.shield_ticks[i] = 0
		spawn_burst(center, p.color, 60, 320, 4)
		spawn_burst(center, rl.WHITE, 30, 220, 3)
		add_shake(16)
	}
}

// Repel wave: kills regular enemies in range, damages bosses
fire_blast :: proc(p: ^Player, center: [2]f32) {
	p.ability_cd = ABILITY_COOLDOWN * ability_cooldown_multiplier(p^)
	p.visual_timer = 0.25
	add_shake(4)

	// Ring of sparks that travels out with the shader wave
	RING :: 40
	for i in 0 ..< RING {
		ang := f32(i) / RING * 2 * math.PI
		spawn_particle(center, [2]f32{math.cos(ang), math.sin(ang)} * 450, p.color, 0.3, 3)
	}

	for &e in enemies {
		if !e.active {
			continue
		}
		offset := e.pos - center
		dist := linalg.length(offset)
		if dist - e.radius >= REPULSION_RADIUS {
			continue
		}

		if e.kind == .Boss {
			e.hp -= 1
			e.flash = 0.15
			spawn_burst(e.pos, rl.WHITE, 14, 260, 3)
			if e.hp <= 0 {
				kill_enemy(&e, p)
			} else {
				if dist > 0.001 {
					e.pos += offset / dist * 70 // knockback
				}
				add_shake(6)
			}
		} else {
			kill_enemy(&e, p)
		}
	}
}

explode_sticky_enemy :: proc(e: ^Enemy, p1, p2: ^Player) {
	center := e.stick_pos
	for i in 0 ..< 2 {
		p := p1
		if i == 1 do p = p2
		if p.dead do continue
		rect := rl.Rectangle{p.pos.x, p.pos.y, p.size.x, p.size.y}
		if rl.CheckCollisionCircleRec(center, STICKY_EXPLOSION_RADIUS, rect) {
			hurt_player(p, e.damage)
		}
	}
	spawn_burst(center, rl.Color{255, 70, 220, 255}, 42, 250, 4)
	spawn_burst(center, rl.Color{255, 220, 120, 255}, 18, 180, 3)
	add_shake(8)
	e.active = false
}

update_sticky_ticks :: proc(p1, p2: ^Player) {
	for &e in enemies {
		if !e.active || e.kind != .Sticky || !e.stuck do continue
		e.stick_ticks -= 1
		if e.stick_ticks <= 0 {
			explode_sticky_enemy(&e, p1, p2)
		}
	}
}

enemy_hits_player :: proc(p: ^Player, player_id: i32) {
	if p.dead {
		return
	}
	rect := rl.Rectangle{p.pos.x, p.pos.y, p.size.x, p.size.y}
	for &e in enemies {
		if !e.active {
			continue
		}
		if e.kind == .Sticky && e.stuck {
			continue
		}
		if !rl.CheckCollisionCircleRec(e.pos, e.radius, rect) {
			continue
		}

		if e.kind == .Boss {
			// The boss isn't consumed: it hurts, then gets knocked back
			if e.hit_cd <= 0 {
				e.hit_cd = BOSS_HIT_COOLDOWN
				hurt_player(p, e.damage)
				offset := e.pos - (p.pos + p.size * 0.5)
				dist := linalg.length(offset)
				if dist > 0.001 {
					e.pos += offset / dist * 120
				}
			}
		} else if e.kind == .Sticky {
			// It does not deal damage on contact. It freezes at this exact position,
			// waits five gameplay ticks, then detonates there.
			e.stuck = true
			e.stick_ticks = STICKY_STICK_TICKS
			e.stick_pos = e.pos
			e.stick_player = player_id
			e.flash = 0.35
			spawn_burst(e.pos, rl.Color{255, 220, 90, 255}, 18, 130, 3)
			continue
		} else {
			e.active = false
			hurt_player(p, e.damage)
			spawn_burst(e.pos, e.color, 8, 150, 3)
		}

		if p.dead {
			return
		}
	}
}

// Enemies target allies too: contact damages the ally (a boss kills it outright)
enemies_hit_allies :: proc() {
	for &e in enemies {
		if !e.active {
			continue
		}
		for &a in allies {
			if !a.active {
				continue
			}
			if !rl.CheckCollisionCircles(e.pos, e.radius, a.pos, a.radius) {
				continue
			}

			if e.kind == .Boss {
				a.hp = 0
			} else {
				a.hp -= 1
				e.active = false
				spawn_burst(e.pos, e.color, 8, 150, 3)
			}
			a.flash = 0.2
			spawn_burst(a.pos, rl.LIME, 10, 140, 3)

			if a.hp <= 0 {
				a.active = false
				spawn_burst(a.pos, rl.LIME, 35, 260, 4)
				add_shake(5)
			}
			if !e.active {
				break
			}
		}
	}
}

collect_coins :: proc(p: ^Player) {
	if p.dead {
		return
	}
	rect := rl.Rectangle{p.pos.x, p.pos.y, p.size.x, p.size.y}
	for &c in coins {
		if c.active && rl.CheckCollisionCircleRec(c.pos, COIN_RADIUS, rect) {
			c.active = false
			p.coins += 1
			p.score += COIN_SCORE
			spawn_burst(c.pos, rl.GOLD, 12, 160, 2.5)
			add_float(c.pos, COIN_SCORE, .Coin)
		}
	}
}

// A player touching an ally heals (only if hurt, so allies aren't wasted)
heal_from_allies :: proc(p: ^Player) {
	if p.dead {
		return
	}
	rect := rl.Rectangle{p.pos.x, p.pos.y, p.size.x, p.size.y}
	for &a in allies {
		if !a.active || !rl.CheckCollisionCircleRec(a.pos, a.radius, rect) {
			continue
		}

		if a.kind == .Barrier {
			add_shield(p)
			a.active = false
			continue
		}

		if p.tag_count > 0 {
			healed := min(HEAL_AMOUNT, p.tag_count)
			p.tag_count -= healed
			a.active = false
			spawn_burst(a.pos, rl.LIME, 30, 220, 3.5)
			spawn_burst(p.pos + p.size * 0.5, rl.LIME, 20, 140, 3)
			add_float(a.pos, healed, .Heal)
		}
	}
}

emit_trail :: proc(p: ^Player) {
	c := p.pos + p.size * 0.5
	jitter := [2]f32{rand.float32_range(-1, 1), rand.float32_range(-1, 1)}
	spawn_particle(c + jitter * 8, jitter * 25, p.color, 0.35, 5)
}

update_pickups :: proc(dt: f32) {
	for &c in coins {
		if !c.active {
			continue
		}
		c.spin += dt * 5
		c.life -= dt
		if c.life <= 0 {
			c.active = false
		}
	}

	for &a in allies {
		if !a.active {
			continue
		}
		a.life -= dt
		a.pulse += dt
		if a.flash > 0 {
			a.flash -= dt
		}

		// Drift around the play area and bounce off the edges
		a.pos += a.vel * dt
		if a.pos.x < a.radius {
			a.pos.x = a.radius
			a.vel.x = abs(a.vel.x)
		}
		if a.pos.x > SCREEN_W - a.radius {
			a.pos.x = SCREEN_W - a.radius
			a.vel.x = -abs(a.vel.x)
		}
		if a.pos.y < 110 {
			a.pos.y = 110
			a.vel.y = abs(a.vel.y)
		}
		if a.pos.y > SCREEN_H - a.radius {
			a.pos.y = SCREEN_H - a.radius
			a.vel.y = -abs(a.vel.y)
		}

		if a.life <= 0 {
			a.active = false
			spawn_burst(a.pos, rl.LIME, 12, 100, 2)
		}
	}
}

update_fx :: proc(dt: f32) {
	for &p in particles {
		if p.life > 0 {
			p.life -= dt
			p.pos += p.vel * dt
			p.vel *= max(0, 1 - 2.5 * dt)
		}
	}
	enhancement_pickup.pulse += dt
	enhancement_pickup.spin += dt * 2.0

	for &f in floaters {
		if f.life > 0 {
			f.life -= dt
			f.pos.y -= 45 * dt
		}
	}
	shake = max(0, shake - 35 * dt)
}

// --- Drawing ---
level_speed_multiplier :: proc(level: i32) -> f32 {
	mult := ENEMY_SPEED_MULT * (1.0 + f32(max(level - 1, 0)) * LEVEL_SPEED_STEP)
	return mult
}

// Every level gets a deterministic style generated from the level number.
// Nothing is stored in a fixed background palette, so the arena keeps evolving.
style_byte :: proc(seed: f32, frequency, phase, low, high: f32) -> u8 {
	x := 0.5 + 0.5 * math.sin(seed * frequency + phase)
	value := low + x * (high - low)
	return u8(clamp(value, 0.0, 255.0))
}

level_style :: proc(level: i32) -> LevelStyle {
	s := f32(level)

	bg_r := style_byte(s, 1.173, 0.7, 7, 32)
	bg_g := style_byte(s, 0.731, 2.1, 10, 38)
	bg_b := style_byte(s, 0.947, 4.4, 18, 55)

	alt_r := style_byte(s, 1.611, 3.2, 10, 48)
	alt_g := style_byte(s, 0.857, 0.4, 14, 54)
	alt_b := style_byte(s, 1.329, 5.0, 28, 72)

	accent := rl.Color{
		style_byte(s, 1.913, 1.2, 80, 255),
		style_byte(s, 1.271, 3.8, 70, 230),
		style_byte(s, 1.587, 5.4, 100, 255),
		255,
	}
	accent2 := rl.Color{
		style_byte(s, 1.447, 4.6, 90, 255),
		style_byte(s, 1.109, 1.7, 80, 245),
		style_byte(s, 1.821, 2.9, 90, 255),
		255,
	}

	pattern: i32 = i32(abs(math.sin(s * 0.917)) * 4.0)
	spacing := i32(28 + int(abs(math.cos(s * 0.643)) * 44.0))

	return LevelStyle{
		background     = rl.Color{bg_r, bg_g, bg_b, 255},
		background_alt = rl.Color{alt_r, alt_g, alt_b, 255},
		grid           = rl.Fade(accent, 0.23),
		accent         = accent,
		accent2        = accent2,
		grid_spacing   = spacing,
		pattern        = pattern,
	}
}

draw_procedural_background :: proc(level: i32, t: f32) {
	style := level_style(level)

	// Broad animated bands give every level a different atmosphere without
	// loading image assets.
	bands: i32 = 24
	band_h: i32 = SCREEN_H / bands
	for i in 0 ..< bands {
		k := f32(i) / f32(bands - 1)
		wave := 0.5 + 0.5 * math.sin(k * 8.0 + t * 0.35 + f32(level) * 0.71)
		col := style.background
		if i % 2 == 1 {
			col = style.background_alt
		}
		shift := u8(clamp(wave * 18.0, 0.0, 18.0))
		col.r = min(u8(255), col.r + shift)
		col.g = min(u8(255), col.g + shift / 2)
		col.b = min(u8(255), col.b + shift)
		rl.DrawRectangle(0, i32(f32(i) * f32(band_h)), SCREEN_W, band_h + i32(2), rl.Fade(col, 0.92))
	}

	// Procedural floating "stars"/nodes. The formula is deterministic from
	// level + index, so each level has a reproducible but different field.
	star_count := 45 + (level % 5) * 12
	for i in 0 ..< star_count {
		fi := f32(i + 1)
		x := 18.0 + (0.5 + 0.5 * math.sin(fi * 12.731 + f32(level) * 1.913)) * (f32(SCREEN_W) - 36.0)
		y := 112.0 + (0.5 + 0.5 * math.sin(fi * 7.317 + f32(level) * 2.271)) * (f32(SCREEN_H) - 130.0)
		pulse := 0.35 + 0.35 * math.sin(t * (0.8 + f32(i % 4) * 0.23) + fi)
		radius := 1.0 + f32(i % 3)
		rl.DrawCircleV({x, y}, radius, rl.Fade(style.accent2, pulse))
	}
}

draw_grid :: proc(level: i32, t: f32) {
	style := level_style(level)
	step := style.grid_spacing

	// Primary grid.
	for x := i32(0); x <= SCREEN_W; x += step {
		phase := 0.45 + 0.25 * math.sin(t * 0.7 + f32(x) * 0.01)
		rl.DrawLine(x, 100, x, SCREEN_H, rl.Fade(style.grid, phase))
	}
	for y := i32(100); y <= SCREEN_H; y += step {
		phase := 0.35 + 0.25 * math.sin(t * 0.9 + f32(y) * 0.013)
		rl.DrawLine(0, y, SCREEN_W, y, rl.Fade(style.grid, phase))
	}

	// A second procedural pattern changes with the generated style.
	pattern := style.pattern
	switch pattern {
	case 0:
		for x := i32(-SCREEN_H); x < SCREEN_W; x += step * 2 {
			rl.DrawLine(x, SCREEN_H, x + SCREEN_H, 100, rl.Fade(style.accent, 0.10))
		}
	case 1:
		for x := i32(0); x <= SCREEN_W; x += step * 2 {
			rl.DrawCircleLines(x, SCREEN_H / 2, f32(18 + step / 3), rl.Fade(style.accent2, 0.10))
		}
	case 2:
		for y := i32(120); y < SCREEN_H; y += step * 2 {
			rl.DrawLine(0, y, SCREEN_W, y, rl.Fade(style.accent2, 0.12))
		}
	case 3:
		for x := i32(0); x <= SCREEN_W; x += step * 2 {
			rl.DrawCircleV({f32(x), 110}, 3.0, rl.Fade(style.accent, 0.22))
		}
	}
}

draw_portal :: proc(level: i32, open_progress, t: f32) {
	style := level_style(level)
	center := [2]f32{f32(SCREEN_W) * 0.5, f32(SCREEN_H) * 0.5}
	pulse := 1.0 + 0.10 * math.sin(t * 7.0)
	rotation := t * (1.0 + f32(level % 5) * 0.18)
	base := 34.0 + open_progress * (PORTAL_RADIUS - 34.0)

	rl.BeginBlendMode(.ADDITIVE)
	for i in 0 ..< 5 {
		k := f32(i) / 5.0
		r := base * (1.0 + k * 0.65) * pulse
		col := style.accent if i % 2 == 0 else style.accent2
		rl.DrawCircleLines(i32(center.x), i32(center.y), r, rl.Fade(col, (0.24 - k * 0.035) * open_progress))
	}
	for i in 0 ..< 16 {
		ang := rotation * (1.0 + f32(i % 3) * 0.22) + f32(i) * (2.0 * math.PI / 16.0)
		r := base * (1.05 + 0.25 * math.sin(ang * 2.0 + rotation))
		pos := center + [2]f32{math.cos(ang), math.sin(ang)} * r
		ray := 3.0 + 2.0 * pulse + f32(i % 3)
		rl.DrawCircleV(pos, ray, rl.Fade(style.accent2, 0.75 * open_progress))
	}
	rl.EndBlendMode()

	// Dark core keeps the portal readable over every generated background.
	rl.DrawCircleV(center, base * 0.72, rl.Color{5, 5, 12, 235})
	rl.DrawCircleLines(i32(center.x), i32(center.y), base * 0.72, rl.Fade(style.accent, 0.95))
	rl.DrawCircleLines(i32(center.x), i32(center.y), base * 0.52, rl.Fade(style.accent2, 0.55))

	label_y := i32(center.y - 10)
	draw_centered("PORTAL", label_y, 22, rl.WHITE)
}

portal_player_inside :: proc(p: Player) -> bool {
	if p.dead {
		return false
	}
	center := p.pos + p.size * 0.5
	portal_center := [2]f32{f32(SCREEN_W) * 0.5, f32(SCREEN_H) * 0.5}
	return linalg.length(center - portal_center) <= PORTAL_RADIUS
}

all_surviving_players_in_portal :: proc(p1, p2: Player) -> bool {
	// Both players must be inside when both are alive. If one died during the
	// finished level, the survivor alone can enter and trigger the transition.
	alive := 0
	inside := 0

	if !p1.dead {
		alive += 1
		if portal_player_inside(p1) {
			inside += 1
		}
	}
	if !p2.dead {
		alive += 1
		if portal_player_inside(p2) {
			inside += 1
		}
	}

	return alive > 0 && inside == alive
}

wrap_player_position :: proc(p: ^Player) -> bool {
	wrapped := false
	sw := f32(SCREEN_W)
	sh := f32(SCREEN_H)

	// Wait until the whole ship has crossed an edge, then place it just
	// outside the opposite edge so it naturally slides back into view.
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

reset_player_for_new_run :: proc(p: ^Player, start_pos: [2]f32) {
	p.pos = start_pos
	p.size = {30, 30}
	p.speed = PLAYER_MAX_SPEED
	p.kill_count = 0
	p.tag_count = 0
	p.dead = false
	p.coins = 0
	p.score = 0
	p.ability_cd = 0
	p.visual_timer = 0
	p.hurt_flash = 0
	p.angle = 0
	p.target_angle = 0
	p.enhancement_count = 0

	for i in 0 ..< MAX_SHIELDS {
		p.shield_ticks[i] = 0
	}
	for i in 0 ..< MAX_ENHANCEMENTS {
		p.enhancements[i] = .None
	}
}

reset_level_world :: proc() {
	for &e in enemies do e.active = false
	for &c in coins do c.active = false
	for &a in allies do a.active = false
	enhancement_pickup.active = false
	for &p in particles do p.life = 0
	for &f in floaters do f.life = 0
	shake = 0
	particle_next = 0
	float_next = 0
}

start_next_level :: proc(p1, p2: ^Player) {
	// A player who died during the previous level is resurrected here.
	if p1.dead {
		p1.dead = false
		p1.tag_count = 0
		for i in 0 ..< MAX_SHIELDS do p1.shield_ticks[i] = 0
		p1.ability_cd = 0
		p1.visual_timer = 0
		p1.hurt_flash = 0
		p1.angle = 0
		p1.target_angle = 0
	}
	if p2.dead {
		p2.dead = false
		p2.tag_count = 0
		for i in 0 ..< MAX_SHIELDS do p2.shield_ticks[i] = 0
		p2.ability_cd = 0
		p2.visual_timer = 0
		p2.hurt_flash = 0
		p2.angle = 0
		p2.target_angle = 0
	}

	// Both players enter the new arena from opposite sides.
	p1.pos = {200, 300}
	p2.pos = {600, 300}
}

enhancement_name :: proc(kind: EnhancementKind) -> cstring {
	switch kind {
	case .Extension:
		return "EXTENSION +5%"
	case .Cooldown:
		return "COOLDOWN -10%"
	case .Damage:
		return "DAMAGE TAKEN -10%"
	case .None:
		return ""
	}
	return ""
}

portal_usable_enhancement_space :: proc(p1, p2: Player) -> bool {
	return p1.enhancement_count < MAX_ENHANCEMENTS || p2.enhancement_count < MAX_ENHANCEMENTS
}

spawn_enhancement :: proc() {
	if enhancement_pickup.active do return
	if rand.float32() >= ENHANCEMENT_SPAWN_CHANCE do return

	kind := EnhancementKind.Extension
	r := rand.float32()
	if r >= 0.66 {
		kind = .Damage
	} else if r >= 0.33 {
		kind = .Cooldown
	}

	center := [2]f32{f32(SCREEN_W) * 0.5, f32(SCREEN_H) * 0.5}
	pos := [2]f32{f32(SCREEN_W) * 0.5, f32(SCREEN_H) * 0.5}
	for _ in 0 ..< 24 {
		pos = {rand.float32_range(70, SCREEN_W - 70), rand.float32_range(145, SCREEN_H - 70)}
		if linalg.length(pos - center) >= 120 do break
	}

	enhancement_pickup = EnhancementPickup{
		pos = pos,
		pulse = 0,
		spin = rand.float32_range(0, 6.28),
		kind = kind,
		active = true,
	}
	spawn_burst(pos, rl.WHITE, 32, 170, 3)
}

collect_enhancement :: proc(p1, p2: ^Player) {
	if !enhancement_pickup.active do return

	r1 := false
	r2 := false
	if !p1.dead && p1.enhancement_count < MAX_ENHANCEMENTS {
		r1 = rl.CheckCollisionCircleRec(enhancement_pickup.pos, 13, rl.Rectangle{p1.pos.x, p1.pos.y, p1.size.x, p1.size.y})
	}
	if !p2.dead && p2.enhancement_count < MAX_ENHANCEMENTS {
		r2 = rl.CheckCollisionCircleRec(enhancement_pickup.pos, 13, rl.Rectangle{p2.pos.x, p2.pos.y, p2.size.x, p2.size.y})
	}
	if !r1 && !r2 do return

	collector := p1
	if r2 && !r1 {
		collector = p2
	} else if r1 && r2 {
		d1 := linalg.length((p1.pos + p1.size * 0.5) - enhancement_pickup.pos)
		d2 := linalg.length((p2.pos + p2.size * 0.5) - enhancement_pickup.pos)
		if d2 < d1 do collector = p2
	}

	kind := enhancement_pickup.kind
	if apply_enhancement(collector, kind) {
		spawn_burst(enhancement_pickup.pos, rl.WHITE, 45, 250, 4)
		add_float(collector.pos + collector.size * 0.5, collector.enhancement_count, .Enhancement)
		enhancement_pickup.active = false
	}
}

draw_enhancement_slots :: proc(p: Player, x, y: i32, right_align: bool) {
	label := fmt.ctprintf("ENH %d/%d", p.enhancement_count, MAX_ENHANCEMENTS)
	slot_w: i32 = 28
	slot_gap: i32 = 4
	slots_width := MAX_ENHANCEMENTS * slot_w + (MAX_ENHANCEMENTS - 1) * slot_gap

	label_x := x
		slots_x := x
	if right_align {
		label_x = x - rl.MeasureText(label, 13)
		slots_x = x - slots_width
	}

	rl.DrawText(label, label_x, y, 13, rl.Fade(rl.LIGHTGRAY, 0.85))
	slot_y := y + 16
	for i in 0 ..< MAX_ENHANCEMENTS {
		ii := i32(i)
		sx := slots_x + ii * (slot_w + slot_gap)
		rl.DrawRectangleLines(sx, slot_y, slot_w, 24, rl.Fade(rl.WHITE, 0.35))
		if ii >= p.enhancement_count {
			continue
		}
		col := rl.SKYBLUE
		label2: cstring = "EXT"
		switch p.enhancements[i] {
		case .Extension:
			col = rl.SKYBLUE
			label2 = "EXT"
		case .Cooldown:
			col = rl.GOLD
			label2 = "CD"
		case .Damage:
			col = rl.VIOLET
			label2 = "DMG"
		case .None:
		}
		rl.DrawRectangle(sx + 2, slot_y + 2, slot_w - 4, 20, rl.Fade(col, 0.32))
		rl.DrawText(label2, sx + (slot_w - rl.MeasureText(label2, 10)) / 2, slot_y + 7, 10, rl.WHITE)
	}
}

draw_countdown :: proc(seconds_left: f32, level: i32) {
	whole := i32(math.ceil(max(seconds_left, 0.0)))
	if whole <= 0 {
		return
	}
	rl.DrawRectangle(0, 0, SCREEN_W, SCREEN_H, rl.Fade(rl.BLACK, 0.38))
	draw_centered("GET READY", 185, 28, rl.LIGHTGRAY)
	draw_centered(fmt.ctprintf("%d", whole), 225, 82, rl.WHITE)
	draw_centered(fmt.ctprintf("LEVEL %d", level), 325, 24, level_style(level).accent)
	draw_centered("Enemies spawn when the countdown ends", 360, 18, rl.LIGHTGRAY)
}

draw_level_complete :: proc(level: i32, open_progress, t: f32, p1, p2: Player) {
	style := level_style(level)
	rl.DrawRectangle(0, 0, SCREEN_W, SCREEN_H, rl.Fade(rl.BLACK, 0.12))
	draw_portal(level, open_progress, t)
	draw_centered(fmt.ctprintf("LEVEL %d COMPLETE", level), 62, 34, style.accent)
	draw_centered(fmt.ctprintf("LEVEL %d", level + 1), 505, 24, rl.WHITE)

	if open_progress < 1.0 {
		draw_centered("The portal is opening...", 535, 17, rl.LIGHTGRAY)
	} else {
		if enhancement_pickup.active {
			draw_centered(fmt.ctprintf("Enhancement: %s", enhancement_name(enhancement_pickup.kind)), 485, 17, rl.WHITE)
			draw_centered("Collect it before entering the portal", 507, 15, rl.LIGHTGRAY)
		}
		players_here := 0
		if portal_player_inside(p1) do players_here += 1
		if portal_player_inside(p2) do players_here += 1
		alive := 0
		if !p1.dead do alive += 1
		if !p2.dead do alive += 1

		if players_here == alive && alive > 0 {
			draw_centered("ENTERING NEXT LEVEL...", 535, 17, style.accent)
		} else if alive == 1 {
			draw_centered("Reach the portal to continue", 535, 17, rl.LIGHTGRAY)
		} else {
			draw_centered("Both players: reach the portal", 535, 17, rl.LIGHTGRAY)
		}
	}
}

// // Additive glow pass drawn underneath the solid shapes
draw_glows :: proc(p1, p2: Player, t: f32) {
	rl.BeginBlendMode(.ADDITIVE)

	for c in coins {
		if c.active {
			draw_glow(c.pos, 22, rl.GOLD, 0.35)
		}
	}
	for a in allies {
		if a.active {
			pulse := 0.5 + 0.5 * math.sin(a.pulse * 4)
			col := rl.LIME
			if a.kind == .Barrier do col = rl.Color{215, 220, 228, 255}
			draw_glow(a.pos, 36 + pulse * 8, col, 0.35 + 0.15 * pulse)
		}
	}
	for e in enemies {
		if !e.active {
			continue
		}
		if e.kind == .Boss {
			pulse := 0.5 + 0.5 * math.sin(t * 8)
			draw_glow(e.pos, e.radius * 2.0 + pulse * 10, rl.Color{255, 60, 200, 255}, 0.45)
		} else if e.kind == .Big {
			draw_glow(e.pos, e.radius * 1.6, rl.RED, 0.2)
		} else if e.kind == .Sticky {
			draw_glow(e.pos, e.radius * (1.8 if e.stuck else 1.3), rl.Color{255, 80, 210, 255}, 0.28)
		}
	}
	for p in ([2]Player{p1, p2}) {
		if !p.dead {
			draw_glow(p.pos + p.size * 0.5, 42, p.color, 0.3)
		}
	}

	rl.EndBlendMode()
}


rotate_ship_point :: proc(center: [2]f32, local: [2]f32, angle: f32) -> [2]f32 {
    c := math.cos(angle)
    s := math.sin(angle)
    return center + [2]f32{local.x * c - local.y * s, local.x * s + local.y * c}
}

update_ship_rotation :: proc(p: ^Player, dt: f32) {
    delta := p.target_angle - p.angle
    if delta > math.PI do delta -= 2 * math.PI
    if delta < -math.PI do delta += 2 * math.PI
    max_turn: f32 = 8.5 * dt
    p.angle += clamp(delta, -max_turn, max_turn)
}

draw_player :: proc(p: Player, ship_shader: ShipShader, t_in: f32) {
	t := t_in
    if p.dead {
        return
    }

    col := p.color
    if p.hurt_flash > 0 && int(p.hurt_flash * 30) % 2 == 0 {
        col = rl.WHITE
    }

    center := p.pos + p.size * 0.5
    half_w := p.size.x * 0.5
    half_h := p.size.y * 0.5

    // P1: pointed fighter/jet silhouette.
    if p.ability_key == .R {
        nose := rotate_ship_point(center, {half_w + 8, 0}, p.angle)
        wing_top := rotate_ship_point(center, {-half_w * 0.55, -half_h * 0.85}, p.angle)
        wing_bot := rotate_ship_point(center, {-half_w * 0.55, half_h * 0.85}, p.angle)
        tail_top := rotate_ship_point(center, {-half_w * 0.9, -half_h * 0.48}, p.angle)
        tail_bot := rotate_ship_point(center, {-half_w * 0.9, half_h * 0.48}, p.angle)

        rl.SetShaderValue(ship_shader.shader, ship_shader.time_loc, &t, .FLOAT)
        tint := [3]f32{f32(col.r) / 255.0, f32(col.g) / 255.0, f32(col.b) / 255.0}
        rl.SetShaderValue(ship_shader.shader, ship_shader.tint_loc, &tint, .VEC3)
        rl.BeginShaderMode(ship_shader.shader)
        rl.DrawTriangle(nose, wing_top, tail_top, col)
        rl.DrawTriangle(nose, tail_bot, wing_bot, col)
        rl.DrawTriangle(nose, tail_top, tail_bot, col)
        rl.EndShaderMode()
        rl.DrawTriangleLines(nose, wing_top, tail_top, rl.Fade(rl.WHITE, 0.55))
        rl.DrawTriangleLines(nose, tail_bot, wing_bot, rl.Fade(rl.WHITE, 0.55))

        // Cockpit and engine glow.
        cockpit := rotate_ship_point(center, {half_w * 0.18, 0}, p.angle)
        engine := rotate_ship_point(center, {-half_w * 0.85, 0}, p.angle)
        rl.DrawCircleV(cockpit, half_h * 0.25, rl.Fade(rl.WHITE, 0.72))
        rl.BeginBlendMode(.ADDITIVE)
        rl.DrawCircleV(engine, half_h * (0.28 + 0.06 * (0.5 + 0.5 * math.sin(t * 14))), rl.Fade(rl.SKYBLUE, 0.8))
        rl.EndBlendMode()
    } else {
        // P2: broader square-like interceptor with a rounded/narrowed nose.
        front := rotate_ship_point(center, {half_w + 5, 0}, p.angle)
        shoulder_top := rotate_ship_point(center, {half_w * 0.25, -half_h}, p.angle)
        rear_top := rotate_ship_point(center, {-half_w, -half_h}, p.angle)
        rear_bot := rotate_ship_point(center, {-half_w, half_h}, p.angle)
        shoulder_bot := rotate_ship_point(center, {half_w * 0.25, half_h}, p.angle)
        nose_top := rotate_ship_point(center, {half_w * 0.78, -half_h * 0.62}, p.angle)
        nose_bot := rotate_ship_point(center, {half_w * 0.78, half_h * 0.62}, p.angle)

        rl.SetShaderValue(ship_shader.shader, ship_shader.time_loc, &t, .FLOAT)
        tint := [3]f32{f32(col.r) / 255.0, f32(col.g) / 255.0, f32(col.b) / 255.0}
        rl.SetShaderValue(ship_shader.shader, ship_shader.tint_loc, &tint, .VEC3)
        rl.BeginShaderMode(ship_shader.shader)
        rl.DrawTriangle(front, shoulder_top, nose_top, col)
        rl.DrawTriangle(front, nose_bot, shoulder_bot, col)
        rl.DrawTriangle(shoulder_top, rear_top, rear_bot, col)
        rl.DrawTriangle(shoulder_top, rear_bot, shoulder_bot, col)
        rl.EndShaderMode()
        rl.DrawTriangleLines(front, shoulder_top, nose_top, rl.Fade(rl.WHITE, 0.55))
        rl.DrawTriangleLines(front, nose_bot, shoulder_bot, rl.Fade(rl.WHITE, 0.55))

        cockpit := rotate_ship_point(center, {half_w * 0.15, 0}, p.angle)
        engine := rotate_ship_point(center, {-half_w * 0.8, 0}, p.angle)
        rl.DrawCircleV(cockpit, half_h * 0.24, rl.Fade(rl.WHITE, 0.72))
        rl.BeginBlendMode(.ADDITIVE)
        rl.DrawCircleV(engine, half_h * (0.30 + 0.05 * (0.5 + 0.5 * math.sin(t * 12))), rl.Fade(rl.LIME, 0.8))
        rl.EndBlendMode()
    }

    // Shield shell around the ship.
    shields := shield_count(p)
    if shields > 0 {
        pulse := 0.9 + 0.1 * math.sin(t * 6.0)
        rl.DrawCircleLines(i32(center.x), i32(center.y), max(half_w, half_h) + 5 + f32(shields) * 2, rl.Fade(rl.Color{215, 220, 228, 255}, 0.45 * pulse))
    }
}

draw_enhancement_pickup :: proc(t: f32) {
	if !enhancement_pickup.active do return
	p := enhancement_pickup.pos
	pulse := 1.0 + 0.14 * math.sin(t * 6.0 + enhancement_pickup.pulse)
	col := rl.Color{190, 210, 255, 255}
	switch enhancement_pickup.kind {
	case .Extension:
		col = rl.SKYBLUE
	case .Cooldown:
		col = rl.GOLD
	case .Damage:
		col = rl.VIOLET
	case .None:
	}
	rl.BeginBlendMode(.ADDITIVE)
	draw_glow(p, 36 * pulse, col, 0.55)
	rl.EndBlendMode()
	rl.DrawCircleV(p, 12 * pulse, rl.Color{24, 28, 40, 245})
	rl.DrawCircleLines(i32(p.x), i32(p.y), 12 * pulse, col)
	rl.DrawCircleLines(i32(p.x), i32(p.y), 7, rl.Fade(rl.WHITE, 0.55))
	label: cstring = "EXT"
	switch enhancement_pickup.kind {
	case .Extension: label = "EXT"
	case .Cooldown: label = "CD"
	case .Damage: label = "DMG"
	case .None: label = "?"
	}
	rl.DrawText(label, i32(p.x) - rl.MeasureText(label, 11) / 2, i32(p.y) - 6, 11, rl.WHITE)
}

draw_entities :: proc(p1, p2: Player, ship_shader: ShipShader) {
	// Coins (spinning)
	for c in coins {
		if !c.active {
			continue
		}
		if c.life < 3 && int(c.life * 8) % 2 == 0 {
			continue // blink before expiring
		}
		w := max(abs(math.cos(c.spin)) * COIN_RADIUS, 1.5)
		cx := i32(c.pos.x)
		cy := i32(c.pos.y)
		rl.DrawEllipse(cx, cy, w, COIN_RADIUS, rl.GOLD)
		rl.DrawEllipse(cx, cy, w * 0.6, COIN_RADIUS * 0.6, rl.YELLOW)
	}

	// Allies: green healing allies or silver barrier allies.
	for a in allies {
		if !a.active {
			continue
		}
		if a.life < 3 && int(a.life * 8) % 2 == 0 {
			continue
		}
		col := rl.Color{60, 220, 100, 255}
		if a.kind == .Barrier {
			col = rl.Color{190, 198, 210, 255}
		}
		if a.flash > 0 {
			col = rl.Color{255, 120, 120, 255}
		}
		rl.DrawCircleV(a.pos, a.radius, col)
		rl.DrawCircleLines(i32(a.pos.x), i32(a.pos.y), a.radius, rl.WHITE)
		if a.kind == .Barrier {
			// Simple shield glyph.
			rl.DrawCircleLines(i32(a.pos.x), i32(a.pos.y), a.radius * 0.55, rl.WHITE)
			rl.DrawLine(i32(a.pos.x) - 5, i32(a.pos.y), i32(a.pos.x) + 5, i32(a.pos.y), rl.WHITE)
			rl.DrawLine(i32(a.pos.x), i32(a.pos.y) - 5, i32(a.pos.x), i32(a.pos.y) + 5, rl.WHITE)
		} else {
			arm := a.radius * 0.7
			th := a.radius * 0.28
			rl.DrawRectangleV(a.pos - [2]f32{arm, th}, [2]f32{arm * 2, th * 2}, rl.WHITE)
			rl.DrawRectangleV(a.pos - [2]f32{th, arm}, [2]f32{th * 2, arm * 2}, rl.WHITE)
		}
		for i in 0 ..< int(a.hp) {
			px := a.pos.x + (f32(i) - f32(a.hp - 1) / 2) * 8
			rl.DrawCircleV([2]f32{px, a.pos.y - a.radius - 8}, 2.5, rl.LIME)
		}
	}

	draw_enhancement_pickup(f32(rl.GetTime()))

	// Enemies
	for e in enemies {
		if !e.active {
			continue
		}
		col := e.color
		if e.flash > 0 {
			col = rl.WHITE
		}
		rl.DrawCircleV(e.pos, e.radius, col)
		rl.DrawCircleLines(i32(e.pos.x), i32(e.pos.y), e.radius, rl.Fade(rl.BLACK, 0.5))
		if e.kind == .Big || e.kind == .Boss {
			rl.DrawCircleV(e.pos, e.radius * 0.45, rl.Fade(rl.WHITE, 0.15))
		}
		if e.kind == .Sticky {
			if e.stuck {
				blink := 0.55 + 0.45 * math.sin(f32(e.stick_ticks) * 5.0)
				rl.DrawCircleLines(i32(e.pos.x), i32(e.pos.y), STICKY_EXPLOSION_RADIUS, rl.Fade(rl.Color{255, 90, 210, 255}, 0.35 + 0.25 * blink))
				rl.DrawText(fmt.ctprintf("%d", e.stick_ticks), i32(e.pos.x) - 4, i32(e.pos.y) - 6, 12, rl.WHITE)
			} else {
				rl.DrawCircleLines(i32(e.pos.x), i32(e.pos.y), e.radius + 5, rl.Fade(rl.Color{255, 210, 100, 255}, 0.65))
			}
		}
		if e.kind == .Boss {
			draw_health_bar(i32(e.pos.x) - 40, i32(e.pos.y - e.radius) - 18, 80, 10, f32(e.hp) / f32(e.max_hp), rl.RED, Player{})
		}
	}

	draw_player(p1, ship_shader, f32(rl.GetTime()))
	draw_player(p2, ship_shader, f32(rl.GetTime()))
}

draw_particles :: proc() {
	rl.BeginBlendMode(.ADDITIVE)
	for p in particles {
		if p.life > 0 {
			t := p.life / p.max_life
			rl.DrawCircleV(p.pos, p.size * (0.3 + 0.7 * t), rl.Fade(p.color, t))
		}
	}
	rl.EndBlendMode()
}

draw_floaters :: proc() {
	for f in floaters {
		if f.life <= 0 {
			continue
		}
		text: cstring
		color := rl.WHITE
		size: i32 = 18
		switch f.kind {
		case .Score:
			text = fmt.ctprintf("+%d", f.value)
		case .Coin:
			text = fmt.ctprintf("+%d", f.value)
			color = rl.GOLD
			size = 16
		case .Heal:
			text = fmt.ctprintf("+%d HP", f.value)
			color = rl.LIME
		case .Shield:
			text = "SHIELD"
			color = rl.Color{215, 220, 228, 255}
			size = 15
		case .Enhancement:
			text = fmt.ctprintf("ENH %d/3", f.value)
			color = rl.SKYBLUE
			size = 15
		case .Boss:
			text = fmt.ctprintf("+%d!", f.value)
			color = rl.GOLD
			size = 32
		}
		a := min(f.life / 0.5, 1.0)
		rl.DrawText(text, i32(f.pos.x) - rl.MeasureText(text, size) / 2, i32(f.pos.y), size, rl.Fade(color, a))
	}
}

main :: proc() {
	screenWidth: i32 = SCREEN_W
	screenHeight: i32 = SCREEN_H

	rl.SetConfigFlags(rl.ConfigFlags{.WINDOW_RESIZABLE})
	rl.InitWindow(screenWidth, screenHeight, "Odin + Raylib: 2 Player Survival")
	rl.MaximizeWindow()
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)

	// Keep gameplay and HUD coordinates on a stable 800x600 logical canvas.
	// The complete canvas is stretched into the current window/fullscreen size,
	// so the HUD positions remain deterministic at every window size.
	game_target := rl.LoadRenderTexture(SCREEN_W, SCREEN_H)
	rl.SetTextureFilter(game_target.texture, .BILINEAR)
	defer rl.UnloadRenderTexture(game_target)

	blast := load_blast_shader()
	defer rl.UnloadShader(blast.shader)
	ship_shader := load_ship_shader()
	defer rl.UnloadShader(ship_shader.shader)

	// Initialize Player 1 (Blue - WASD + R Ability)
	player1 := Player{
		pos         = {200, 300},
		size        = {30, 30},
		speed       = PLAYER_MAX_SPEED,
		color       = rl.BLUE,
		up          = .W,
		down        = .S,
		left        = .A,
		right       = .D,
		ability_key = .R,
		kill_count  = 0,
		angle       = 0,
		target_angle = 0,
	}

	// Initialize Player 2 (Green - Arrows + / Ability)
	player2 := Player{
		pos         = {600, 300},
		size        = {30, 30},
		speed       = PLAYER_MAX_SPEED,
		color       = rl.GREEN,
		up          = .UP,
		down        = .DOWN,
		left        = .LEFT,
		right       = .RIGHT,
		ability_key = .SLASH,
		kill_count  = 0,
		angle       = 0,
		target_angle = 0,
	}

	spawn_timer: f32 = 0.0
	coin_timer: f32 = 1.0
	ally_timer: f32 = 6.0
	tick_accum: f32 = 0.0
	ticks: i32 = 0
	boss_warn: f32 = 0.0
	survive_time: f32 = 0.0

	level: i32 = 1
	phase := GamePhase.Countdown
	countdown: f32 = LEVEL_COUNTDOWN
	portal_timer: f32 = 0.0
	portal_open: f32 = 0.0
	enhancement_pickup = EnhancementPickup{}

	for !rl.WindowShouldClose() {
		dt := min(rl.GetFrameTime(), 0.05)
		t := f32(rl.GetTime())

		if rl.IsKeyPressed(.F11) do rl.ToggleFullscreen()

		// --- PHASE UPDATE ---
		switch phase {
		case .Countdown:
			countdown -= dt
			if countdown <= 0 {
				countdown = 0
				phase = .Playing
				spawn_timer = 0
				coin_timer = 1
				ally_timer = 6
			}
		case .LevelComplete:
			// The portal opens visually, but the level does NOT advance on a timer.
			// Players have to physically enter it first.
			portal_open = min(1.0, portal_open + dt / PORTAL_OPEN_TIME)

			if all_surviving_players_in_portal(player1, player2) {
				level += 1

				// A player who died in the finished level is resurrected now.
				start_next_level(&player1, &player2)
				reset_level_world()

				spawn_timer = 0
				coin_timer = 1
				ally_timer = 6
				tick_accum = 0
				ticks = 0
				boss_warn = 0

				countdown = LEVEL_COUNTDOWN
				portal_open = 0
				phase = .Countdown
			}
		case .Playing:
			survive_time += dt
		case .GameOver:
			// Hold the final score screen until Space restarts the entire run.
			if rl.IsKeyPressed(.SPACE) {
				reset_level_world()
				reset_player_for_new_run(&player1, {200, 300})
				reset_player_for_new_run(&player2, {600, 300})

				spawn_timer = 0
				coin_timer = 1
				ally_timer = 6
				tick_accum = 0
				ticks = 0
				boss_warn = 0
				survive_time = 0
				level = 1
				countdown = LEVEL_COUNTDOWN
				portal_timer = 0
				portal_open = 0
				phase = .Countdown
			}
		}

		// Update Cooldowns & Timers during active gameplay/countdown.
		if player1.ability_cd > 0 do player1.ability_cd = max(0, player1.ability_cd - dt)
		if player2.ability_cd > 0 do player2.ability_cd = max(0, player2.ability_cd - dt)
		if player1.visual_timer > 0 do player1.visual_timer = max(0, player1.visual_timer - dt)
		if player2.visual_timer > 0 do player2.visual_timer = max(0, player2.visual_timer - dt)
		if player1.hurt_flash > 0 do player1.hurt_flash = max(0, player1.hurt_flash - dt)
		if player2.hurt_flash > 0 do player2.hurt_flash = max(0, player2.hurt_flash - dt)
		if boss_warn > 0 do boss_warn = max(0, boss_warn - dt)

		old1 := player1.pos
		old2 := player2.pos
		wrapped1 := false
		wrapped2 := false

		// Players can move during preparation, combat, and the portal transition.
		if phase == .Countdown || phase == .Playing || phase == .LevelComplete {
			if !player1.dead {
				dir1: [2]f32 = {0, 0}
				if rl.IsKeyDown(player1.up) do dir1.y -= 1
				if rl.IsKeyDown(player1.down) do dir1.y += 1
				if rl.IsKeyDown(player1.left) do dir1.x -= 1
				if rl.IsKeyDown(player1.right) do dir1.x += 1
				if linalg.length(dir1) > 0.001 {
					dir1 = linalg.normalize(dir1)
					player1.target_angle = math.atan2(dir1.y, dir1.x)
					player1.pos += dir1 * player1.speed * dt
				}
			}

			if !player2.dead {
				dir2: [2]f32 = {0, 0}
				if rl.IsKeyDown(player2.up) do dir2.y -= 1
				if rl.IsKeyDown(player2.down) do dir2.y += 1
				if rl.IsKeyDown(player2.left) do dir2.x -= 1
				if rl.IsKeyDown(player2.right) do dir2.x += 1
				if linalg.length(dir2) > 0.001 {
					dir2 = linalg.normalize(dir2)
					player2.target_angle = math.atan2(dir2.y, dir2.x)
					player2.pos += dir2 * player2.speed * dt
				}
			}
		}

		// Smoothly rotate each ship toward its latest movement/target direction.
		update_ship_rotation(&player1, dt)
		update_ship_rotation(&player2, dt)

		// Screen-wrap instead of clamping. The ship must fully leave an edge
		// before it is placed just outside the opposite edge.
		if phase == .Countdown || phase == .Playing || phase == .LevelComplete {
			if !player1.dead do wrapped1 = wrap_player_position(&player1)
			if !player2.dead do wrapped2 = wrap_player_position(&player2)
		}

		// Movement trails. Suppress a trail on the frame of a screen wrap so
		// the teleport does not draw a giant streak across the arena.
		if (phase == .Countdown || phase == .Playing || phase == .LevelComplete) {
			if !player1.dead && !wrapped1 && linalg.length(player1.pos - old1) > 0.01 do emit_trail(&player1)
			if !player2.dead && !wrapped2 && linalg.length(player2.pos - old2) > 0.01 do emit_trail(&player2)
		}

		p1_center := player1.pos + (player1.size * 0.5)
		p2_center := player2.pos + (player2.size * 0.5)

		if phase == .LevelComplete {
			collect_enhancement(&player1, &player2)
		}

		// --- ABILITIES (Repel Wave) ---
		if phase == .Playing {
			if !player1.dead && rl.IsKeyPressed(player1.ability_key) && player1.ability_cd <= 0 {
				fire_blast(&player1, p1_center)
			}
			if !player2.dead && rl.IsKeyPressed(player2.ability_key) && player2.ability_cd <= 0 {
				fire_blast(&player2, p2_center)
			}
		}

		// --- SPAWNERS + ENEMY SIMULATION ---
		if phase == .Playing {
			level_mult := level_speed_multiplier(level)

			// Regular enemies: mix of normal, runner and big
			spawn_timer += dt
			if spawn_timer > 0.5 {
				spawn_timer = 0.0
				roll := rand.float32()
				kind := EnemyKind.Normal
				if roll > 0.91 {
					kind = .Sticky
				} else if roll > 0.80 {
					kind = .Big
				} else if roll > 0.55 {
					kind = .Runner
				}
				spawn_enemy(kind, level_mult)
			}

			// Boss: 10% chance every 120 ticks (1 tick = 1/60 s)
			tick_accum = min(tick_accum + dt, 0.25)
			for tick_accum >= TICK_DT {
				tick_accum -= TICK_DT
				ticks += 1
				refresh_shield_timers_tick(&player1)
				refresh_shield_timers_tick(&player2)
				update_sticky_ticks(&player1, &player2)
				if ticks % BOSS_CHECK_TICKS == 0 && rand.float32() < BOSS_CHANCE && count_bosses() < MAX_BOSSES {
					spawn_enemy(.Boss, level_mult)
					boss_warn = 2.0
					add_shake(10)
				}
			}

			// Coins
			coin_timer -= dt
			if coin_timer <= 0 {
				coin_timer = rand.float32_range(1.0, 2.0)
				if count_active_coins() < 10 {
					spawn_coin_at({rand.float32_range(40, SCREEN_W - 40), rand.float32_range(120, SCREEN_H - 40)})
				}
			}

			// Allies
			ally_timer -= dt
			if ally_timer <= 0 {
				ally_timer = rand.float32_range(9.0, 15.0)
				if count_active_allies() < 3 {
					spawn_ally()
				}
			}

			// Enemy Movement Logic: chase the nearest living player OR ally.
			// Runners turn gradually rather than snapping their velocity directly at the target.
			for &e in enemies {
				if !e.active {
					continue
				}
				if e.hit_cd > 0 do e.hit_cd -= dt
				if e.flash > 0 do e.flash -= dt

				if e.kind == .Sticky && e.stuck {
					e.pos = e.stick_pos
					continue
				}

				best: f32 = math.F32_MAX
				target: [2]f32

				if !player1.dead {
					d := linalg.length(p1_center - e.pos)
					if d < best {
						best = d
						target = p1_center
					}
				}
				if !player2.dead {
					d := linalg.length(p2_center - e.pos)
					if d < best {
						best = d
						target = p2_center
					}
				}
				for a in allies {
					if a.active {
						d := linalg.length(a.pos - e.pos)
						if d < best {
							best = d
							target = a.pos
						}
					}
				}

				if best < math.F32_MAX && best > 0.001 {
					direction := (target - e.pos) / best
					if e.kind == .Runner {
						if linalg.length(e.heading) <= 0.001 {
							e.heading = direction
						} else {
							current_angle := math.atan2(e.heading.y, e.heading.x)
							desired_angle := math.atan2(direction.y, direction.x)
							delta := desired_angle - current_angle
							if delta > math.PI do delta -= 2 * math.PI
							if delta < -math.PI do delta += 2 * math.PI

							// Runner steering is deliberately one-directional. It may curve
							// only while the target is inside a narrow forward cone. If the
							// target is behind it, the runner does NOT turn around.
							if abs(delta) <= RUNNER_MAX_CURVE_ANGLE {
								turn := clamp(delta, -RUNNER_TURN_RATE * dt, RUNNER_TURN_RATE * dt)
								cs := math.cos(turn)
								sn := math.sin(turn)
								e.heading = {
									e.heading.x * cs - e.heading.y * sn,
									e.heading.x * sn + e.heading.y * cs,
								}
							}
						}
						move_speed := e.speed
						e.pos += e.heading * move_speed * dt
					} else {
						move_speed := e.speed
						e.pos += direction * move_speed * dt
					}
				}

				// Trails
				if e.kind == .Runner && rand.float32() < 0.5 {
					spawn_particle(e.pos, {0, 0}, rl.ORANGE, 0.3, 4)
				} else if e.kind == .Sticky {
					spawn_particle(e.pos, {0, 0}, rl.Color{255, 80, 210, 255}, 0.4, 3)
				} else if e.kind == .Boss {
					jitter := [2]f32{rand.float32_range(-1, 1), rand.float32_range(-1, 1)}
					spawn_particle(e.pos + jitter * (e.radius * 0.6), jitter * 40, rl.Color{255, 90, 200, 255}, 0.5, 6)
				}
			}

			// Collisions & pickups
			enemy_hits_player(&player1, 1)
			enemy_hits_player(&player2, 2)
			enemies_hit_allies()
			collect_coins(&player1)
			collect_coins(&player2)
			heal_from_allies(&player1)
			heal_from_allies(&player2)

			// Both dead before reaching the milestone means the run is over.
			if player1.dead && player2.dead {
				phase = .GameOver
			} else {
				// Level milestones use the combined score of both players.
				total_score := player1.score + player2.score
				next_milestone := level * LEVEL_SCORE_STEP
				if total_score >= next_milestone {
					phase = .LevelComplete
					portal_open = 0
					boss_warn = 0
					if portal_usable_enhancement_space(player1, player2) {
						spawn_enhancement()
					}
					// The arena is now safe. The portal is the only thing that
					// advances the game.
					for &e in enemies do e.active = false
					for &c in coins do c.active = false
					for &a in allies do a.active = false
				}
			}
		}

		// Pickups/FX still animate during countdown and level transitions.
		update_pickups(dt)
		update_fx(dt)

		// --- DRAW TO FIXED LOGICAL CANVAS ---
		rl.BeginDrawing()
		rl.BeginTextureMode(game_target)
		rl.ClearBackground(level_style(level).background)
		draw_procedural_background(level, t)

		// World (affected by screen shake)
		shake_off := [2]f32{rand.float32_range(-1, 1), rand.float32_range(-1, 1)} * shake
		camera := rl.Camera2D{offset = shake_off, zoom = 1.0}
		rl.BeginMode2D(camera)
		draw_grid(level, t)
		draw_glows(player1, player2, t)
		draw_entities(player1, player2, ship_shader)
		draw_particles()
		draw_floaters()
		rl.EndMode2D()

		// Ability Shockwave (shader effect), in screen space so it follows the shake.
		if player1.visual_timer > 0 {
			draw_blast(blast, p1_center + shake_off, (0.25 - player1.visual_timer) / 0.25, {0.3, 0.6, 1.0}, f32(SCREEN_H))
		}
		if player2.visual_timer > 0 {
			draw_blast(blast, p2_center + shake_off, (0.25 - player2.visual_timer) / 0.25, {0.4, 1.0, 0.4}, f32(SCREEN_H))
		}

		// Boss warning
		if boss_warn > 0 {
			pulse := 0.5 + 0.5 * math.sin(t * 12)
			rl.DrawRectangle(0, 0, SCREEN_W, SCREEN_H, rl.Fade(rl.RED, 0.07 * pulse))
			draw_centered("!! BOSS INCOMING !!", 110, 34, rl.Fade(rl.RED, 0.5 + 0.5 * pulse))
		}

		// Draw UI
		UI_MARGIN :: 10
		BAR_W :: 200
		BAR_H :: 16

		// P1 UI (left side)
		rl.DrawText("P1: WASD", UI_MARGIN, 10, 20, rl.LIGHTGRAY)
		p1_status := "DEAD" if player1.dead else ("READY [R]" if player1.ability_cd <= 0 else fmt.ctprintf("%.1fs", player1.ability_cd))
		rl.DrawText(fmt.ctprintf("P1 Kills: %d | Blast: %s", player1.kill_count, p1_status), UI_MARGIN, 35, 18, rl.SKYBLUE)
		draw_health_bar(UI_MARGIN, 60, BAR_W, BAR_H, health_fraction(player1), rl.BLUE, player1)
		rl.DrawText(fmt.ctprintf("Score: %d | Coins: %d | Shields: %d/3", player1.score, player1.coins, shield_count(player1)), UI_MARGIN, 82, 16, rl.GOLD)
		draw_enhancement_slots(player1, UI_MARGIN, 103, false)

		// P2 UI (right side, right-aligned)
		p2_title: cstring = "P2: Arrows"
		rl.DrawText(p2_title, SCREEN_W - UI_MARGIN - rl.MeasureText(p2_title, 20), 10, 20, rl.LIGHTGRAY)
		p2_status := "DEAD" if player2.dead else ("READY [/]" if player2.ability_cd <= 0 else fmt.ctprintf("%.1fs", player2.ability_cd))
		p2_text := fmt.ctprintf("P2 Kills: %d | Blast: %s", player2.kill_count, p2_status)
		rl.DrawText(p2_text, SCREEN_W - UI_MARGIN - rl.MeasureText(p2_text, 18), 35, 18, rl.LIME)
		draw_health_bar(SCREEN_W - UI_MARGIN - BAR_W, 60, BAR_W, BAR_H, health_fraction(player2), rl.GREEN, player2)
		p2_score := fmt.ctprintf("Score: %d | Coins: %d | Shields: %d/3", player2.score, player2.coins, shield_count(player2))
		rl.DrawText(p2_score, SCREEN_W - UI_MARGIN - rl.MeasureText(p2_score, 16), 82, 16, rl.GOLD)
		draw_enhancement_slots(player2, SCREEN_W - UI_MARGIN, 103, true)

		// Center level HUD
		level_title := fmt.ctprintf("LEVEL %d", level)
		draw_centered(level_title, 12, 18, rl.WHITE)

		total_score := player1.score + player2.score
		next_milestone := level * LEVEL_SCORE_STEP
		level_score_remaining := max(0, next_milestone - total_score)
		draw_centered(fmt.ctprintf("Next portal: %d pts", level_score_remaining), 35, 14, rl.LIGHTGRAY)

		// Fullscreen hint
		rl.DrawText("F11: Fullscreen", 10, SCREEN_H - 24, 14, rl.Fade(rl.LIGHTGRAY, 0.65))

		if phase == .Countdown {
			draw_countdown(countdown, level)
		}

		if phase == .LevelComplete {
			draw_level_complete(level, portal_open, t, player1, player2)
		}

		// Game over: final score screen once both players are dead.
		if phase == .GameOver {
			rl.DrawRectangle(0, 0, SCREEN_W, SCREEN_H, rl.Fade(rl.BLACK, 0.70))
			draw_centered("GAME OVER", 105, 56, rl.RED)
			draw_centered(fmt.ctprintf("TOTAL SCORE  %d", player1.score + player2.score), 175, 30, rl.GOLD)

			// Show each player's result directly. No winner/loser label.
			p1_box := rl.Rectangle{90, 235, 290, 105}
			p2_box := rl.Rectangle{420, 235, 290, 105}
			rl.DrawRectangleLinesEx(p1_box, 2, rl.Fade(rl.SKYBLUE, 0.60))
			rl.DrawRectangleLinesEx(p2_box, 2, rl.Fade(rl.LIME, 0.60))

			draw_centered_at("PLAYER 1", 235, 250, 20, rl.SKYBLUE)
			draw_centered_at(fmt.ctprintf("Score: %d", player1.score), 235, 277, 24, rl.WHITE)
			draw_centered_at(fmt.ctprintf("Kills: %d   Coins: %d", player1.kill_count, player1.coins), 235, 310, 17, rl.LIGHTGRAY)

			draw_centered_at("PLAYER 2", 565, 250, 20, rl.LIME)
			draw_centered_at(fmt.ctprintf("Score: %d", player2.score), 565, 277, 24, rl.WHITE)
			draw_centered_at(fmt.ctprintf("Kills: %d   Coins: %d", player2.kill_count, player2.coins), 565, 310, 17, rl.LIGHTGRAY)

			draw_centered(fmt.ctprintf("Reached Level %d  |  Survived %.0f seconds", level, survive_time), 385, 18, rl.LIGHTGRAY)
			draw_centered("PRESS SPACE TO RESTART", 455, 28, rl.WHITE)
		}

		rl.EndTextureMode()

		// --- PRESENT LOGICAL CANVAS TO THE ACTUAL DISPLAY ---
		// Stretch the complete logical canvas to the current client area. This
		// intentionally does NOT preserve the 4:3 aspect ratio, because the user
		// wants fullscreen and resized windows to use every available pixel.
		rl.ClearBackground(rl.BLACK)

		display_w := f32(rl.GetScreenWidth())
		display_h := f32(rl.GetScreenHeight())
		source := rl.Rectangle{0, 0, f32(SCREEN_W), -f32(SCREEN_H)}
		dest := rl.Rectangle{0, 0, display_w, display_h}
		rl.DrawTexturePro(game_target.texture, source, dest, {0, 0}, 0, rl.WHITE)

		rl.EndDrawing()

		// Clear temporary string allocations created by fmt.ctprintf each frame.
		free_all(context.temp_allocator)
	}
}
