package main

import "core:math"
import "core:math/linalg"
import "core:math/rand"
import rl "vendor:raylib"

// =============================================================================
// skills.odin - what the skills DO (their description/registry is in skill_defs.odin),
// plus the players' gun and the skill dice drops.
//
//  * Players start with NO skill. Skill dice drop from enemies (very rarely) and
//    from "10th level" bosses (25%). Touching a die rolls a random skill, which
//    becomes the taken skill. Owned skills can be cycled with the cycle key.
//  * The common ability of every player is the gun: hold the fire key to shoot
//    from the two wing guns. (Rocket skill: the gun fires rockets instead.)
//  * Skills:  Explosion    - the old repel blast (cooldown 120 ticks)
//             Repel        - 3 s cooldown: pushes every projectile, enemy and the other
//                            player 6 ship sizes away
//             Rocket       - passive while taken: rockets, 40 tick cooldown
//             Invisibility - 5 s (300 ticks) invulnerable, 10 s (600 ticks) cooldown
//             Surprise     - 40 ticks: everything that touches you is reflected
//                            (and can hurt the OTHER player), 15 s (900 ticks) cooldown
//             Freeze       - everything except the players freezes for 3 s, then the user is slowed
//                            for 3 s (50% speed) and a 30 s cooldown runs
//             Come Back    - teleport to where you were 5 s ago (health restored to that moment,
//                            cooldowns keep running, your minions are rewound too); once per level
//  * All cooldowns are counted in the fixed 60 Hz ticks (update_ticks in game.odin).
// =============================================================================

player_invulnerable :: proc(p: Player) -> bool {
	return p.invis_ticks > 0 || p.surprise_ticks > 0
}

// --- Owning / taking skills ---

grant_skill :: proc(g: ^Game, p: ^Player, kind: SkillKind) {
	if kind == .None do return
	p.skills_owned[kind] = true
	p.skill = kind
	c := player_center(p^)
	col := skill_color(kind)
	spawn_burst(g, c, col, 36, 240, 3.5)
	spawn_ring(g, c, rl.WHITE, 24, 200, 0.4, 3)
	add_float(g, c + [2]f32{0, -18}, i32(kind), .Skill)
}

// Takes the next owned skill (in wheel order).
cycle_skill :: proc(g: ^Game, p: ^Player) {
	start := 0
	for i in 0 ..< SKILL_COUNT {
		if skill_at(i) == p.skill do start = i
	}
	for step in 1 ..= SKILL_COUNT {
		k := skill_at((start + step) % SKILL_COUNT)
		if p.skills_owned[k] {
			if k != p.skill {
				p.skill = k
				spawn_burst(g, player_center(p^), skill_color(k), 12, 120, 2.5)
			}
			return
		}
	}
}

// --- Using skills ---

activate_skill :: proc(g: ^Game, p: ^Player, index: int) {
	if p.skill == .None || p.skill_cd[p.skill] > 0 do return
	use := skill_def(p.skill).use
	if use != nil do use(g, p, i32(index)) // passive skills (Rocket) have no use proc
}

// Invisibility: invulnerable for a few seconds.
use_invisibility :: proc(g: ^Game, p: ^Player, index: i32) {
	c := player_center(p^)
	p.invis_ticks = INVIS_DURATION_TICKS
	p.skill_cd[.Invisibility] = skill_cooldown(p^, INVIS_COOLDOWN_TICKS)
	spawn_ring(g, c, skill_color(.Invisibility), 30, 220, 0.4, 3)
	spawn_burst(g, c, rl.WHITE, 16, 160, 2.5)
}

// Surprise: for a short window everything that touches the player is reflected.
use_surprise :: proc(g: ^Game, p: ^Player, index: i32) {
	c := player_center(p^)
	p.surprise_ticks = SURPRISE_DURATION_TICKS
	p.skill_cd[.Surprise] = skill_cooldown(p^, SURPRISE_COOLDOWN_TICKS)
	spawn_ring(g, c, skill_color(.Surprise), 36, 300, 0.4, 3.5)
	add_shake(g, 3)
}

// Explosion: kills regular enemies in range, damages bosses (the old repel blast).
use_explosion :: proc(g: ^Game, p: ^Player, index: i32) {
	center := player_center(p^)
	p.skill_cd[.Explosion] = skill_cooldown(p^, EXPLOSION_COOLDOWN_TICKS)
	p.visual_timer = BLAST_VISUAL_TIME
	add_shake(g, 4)
	spawn_ring(g, center, skill_color(.Explosion), 40, 450, 0.3, 3)
	spawn_burst(g, center, skill_color(.Explosion), 30, 320, 3.5)
	spawn_burst(g, center, rl.Color{255, 235, 170, 255}, 16, 200, 3)

	for &e in g.enemies {
		if !e.active do continue
		offset := closest_wrapped_pos(e, center) - center // the boss may be across a screen border
		dist := linalg.length(offset)
		if dist - e.radius >= REPULSION_RADIUS do continue

		if enemy_def(e.kind).is_boss {
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

// --- Repel ---

repel_radius :: proc(p: Player) -> f32 {
	return REPEL_RADIUS_SHIPS * max(p.size.x, p.size.y)
}

// Everything within 6 ship sizes is thrown outward by 6 ship sizes:
//  * projectiles (enemy shots, reflected shots, the OTHER player's shots) turn
//    around and fly away from you; your own shots are left alone;
//  * enemies, minions and the boss get a knock-back impulse (they decay like the
//    boss repel, so total travel = impulse / KNOCK_DECAY = the repel radius);
//  * the other player is knocked back the same way.
use_repel :: proc(g: ^Game, p: ^Player, index: i32) {
	center := player_center(p^)
	radius := repel_radius(p^)
	push   := radius * KNOCK_DECAY // impulse whose total travel is `radius`
	col    := skill_color(.Repel)

	p.skill_cd[.Repel] = skill_cooldown(p^, REPEL_COOLDOWN_TICKS)
	p.repel_visual = REPEL_VISUAL_TIME
	add_shake(g, 5)
	spawn_ring(g, center, col, 48, radius * 3.0, 0.4, 3.5)
	spawn_ring(g, center, rl.WHITE, 24, radius * 2.2, 0.3, 2.5)

	// Projectiles
	for &b in g.bullets {
		if !b.active do continue
		if b.from_player && b.owner == index do continue // your own shots pass
		off := b.pos - center
		dist := linalg.length(off)
		if dist > radius do continue
		dir := off / dist if dist > 0.001 else linalg.normalize0(-b.vel)
		b.vel = dir * max(linalg.length(b.vel), BULLET_SPEED)
		b.pos = center + dir * (radius + 4) // clear of the shield, flying away
		if b.from_player {
			b.range_left = max(b.range_left, 200)
		} else {
			b.life = max(b.life, 0.8)
		}
		spawn_burst(g, b.pos, col, 4, 110, 2)
	}

	// Enemies (any kind, the boss included; armed sticky bombs are already counting down)
	for &e in g.enemies {
		if !e.active || enemy_inert(e) do continue
		epos := closest_wrapped_pos(e, center)
		off := epos - center
		dist := linalg.length(off)
		if dist - e.radius > radius do continue
		dir := off / dist if dist > 0.001 else [2]f32{1, 0}
		e.knock = dir * push
		if enemy_def(e.kind).is_boss {
			e.dash_t = 0
			e.dash_windup = 0
			e.charge = 0
		}
		spawn_burst(g, epos, col, 5, 150, 2.5)
	}

	// The other player
	for &q, qi in g.players {
		if i32(qi) == index || q.dead do continue
		off := player_center(q) - center
		dist := linalg.length(off)
		if dist > radius do continue
		dir := off / dist if dist > 0.001 else [2]f32{1, 0}
		q.knock = dir * push
		spawn_burst(g, player_center(q), col, 12, 190, 3)
	}
}

// --- Freeze ---

// Everything that is not a player stops for FREEZE_DURATION_TICKS: enemies (and their
// weapons), enemy bullets, asteroids and the spawners. Player shots keep flying, so a frozen
// enemy can still be shot. Frozen enemies are drawn through the ice shader (render.odin) and
// cannot hurt anyone. The 30 s cooldown starts after the thaw, so the timer is 3 s + 30 s.
use_freeze :: proc(g: ^Game, p: ^Player, index: i32) {
	c := player_center(p^)
	col := skill_color(.Freeze)
	g.freeze_ticks = FREEZE_DURATION_TICKS
	g.freeze_time  = g.time
	p.skill_cd[.Freeze] = FREEZE_DURATION_TICKS + skill_cooldown(p^, FREEZE_COOLDOWN_TICKS)
	p.slow_ticks = FREEZE_DURATION_TICKS + FREEZE_SLOW_TICKS // slowed for 3 s once the freeze has ended
	p.freeze_visual = FREEZE_VISUAL_TIME
	add_shake(g, 6)
	spawn_ring(g, c, col, 56, 700, 0.6, 3.5)
	spawn_ring(g, c, rl.WHITE, 28, 480, 0.45, 2.5)
	spawn_burst(g, c, col, 30, 260, 3)
	for &e in g.enemies {
		if e.active do spawn_burst(g, e.pos, col, 5, 90, 2.5)
	}
}

// 0..1: how solid the ice is (fades out over the last FREEZE_FADE_TICKS ticks).
freeze_amount :: proc(g: ^Game) -> f32 {
	return clamp(f32(g.freeze_ticks) / f32(FREEZE_FADE_TICKS), 0, 1)
}

// --- Come Back ---

// Called once per 60 Hz tick while playing: remembers where everybody was.
record_rewind :: proc(g: ^Game) {
	for &p, i in g.players {
		if p.dead do continue
		buf := &g.rewind[i]
		snap := RewindSnap{pos = p.pos, health_points = p.health_points}
		for &m in g.minions {
			if !m.exists || m.owner != i32(i) do continue
			snap.minions[m.slot] = RewindMinion{valid = true, alive = m.alive, pos = m.pos, taken = m.taken}
		}
		buf.snaps[buf.head] = snap
		buf.head = (buf.head + 1) % REWIND_TICKS
		buf.count = min(buf.count + 1, REWIND_TICKS)
	}
}

// Teleports the player back to where it was 5 s ago (the oldest memory if the level is younger
// than that) with the health it had then. Cooldowns keep running; timers are not restored.
// The player's minions are restored the same way (position, health, alive or dead).
// Usable once per level.
use_comeback :: proc(g: ^Game, p: ^Player, index: i32) {
	if p.comeback_used do return
	buf := &g.rewind[index]
	if buf.count == 0 do return // nothing recorded yet: keep the charge

	oldest := (buf.head - buf.count + REWIND_TICKS) % REWIND_TICKS
	snap := buf.snaps[oldest]
	col := skill_color(.ComeBack)

	from := player_center(p^)
	p.pos = snap.pos
	p.health_points = min(snap.health_points, player_max_health(p^) - 1)
	p.knock = {}
	p.trail_n = 0
	p.comeback_used = true
	p.rewind_visual = COMEBACK_VISUAL_TIME
	to := player_center(p^)

	comeback_effect(g, from, to, col)

	for &m in g.minions {
		if !m.exists || m.owner != index do continue
		rm := snap.minions[m.slot]
		if !rm.valid do continue // it did not exist yet 5 s ago
		mfrom := m.pos
		m.pos = rm.pos
		m.alive = rm.alive
		m.taken = rm.taken
		m.laser_ticks = 0
		m.hit_cd = 0
		comeback_effect(g, mfrom, m.pos, col)
	}
}

// A line of sparks from where you were to where you are now, plus a flash at both ends.
comeback_effect :: proc(g: ^Game, from, to: [2]f32, col: rl.Color) {
	steps :: 24
	for i in 0 ..< steps {
		k := f32(i) / f32(steps - 1)
		spawn_particle(g, from + (to - from) * k, rand_vec2() * 30, col, 0.55, 3)
	}
	spawn_ring(g, from, col, 28, 220, 0.4, 3)
	spawn_ring(g, to, rl.WHITE, 28, 260, 0.45, 3)
	spawn_burst(g, to, col, 24, 220, 3)
	add_shake(g, 5)
}

// --- The gun ---

// Muzzle position in ship-local pixels (x = forward, y = sideways). side = -1 / +1.
muzzle_local :: proc(p: Player, side: f32) -> [2]f32 {
	switch p.ship {
	case .Fighter:
		// The two shoulder guns of the Spear (the barbs' front corners).
		return {p.size.x * 0.5 * 0.5, side * p.size.y * 0.5 * 0.55}
	case .Interceptor:
		// The two nose-edge guns of the Hauler.
		u := max(p.size.x, p.size.y) * 0.5
		return {u * 0.95, side * u * 0.30}
	}
	return {}
}

muzzle_world :: proc(p: Player, side: f32) -> [2]f32 {
	return player_center(p) + rotate_vec(muzzle_local(p, side), p.angle)
}

add_bullet :: proc(g: ^Game, b: Bullet) {
	for &slot in g.bullets {
		if slot.active do continue
		slot = b
		slot.active = true
		return
	}
}

// One shot from the next wing gun (the guns alternate).
fire_gun :: proc(g: ^Game, p: ^Player, index: i32) {
	side: f32 = 1 if p.gun_flip else -1
	p.gun_flip = !p.gun_flip
	p.muzzle_flash[0 if side < 0 else 1] = 0.09

	muzzle := muzzle_world(p^, side)
	dir := [2]f32{math.cos(p.angle), math.sin(p.angle)} // no target: straight ahead
	// The gun always aims itself; skill shots (rockets) only do when auto-aim is on.
	aimed := p.skill != .Rocket || p.skill_aim
	if target, ok := nearest_front_enemy(g, p^); ok && aimed {
		d := target - muzzle
		if linalg.length(d) > 0.001 do dir = linalg.normalize(d)
	}
	col := p.color

	if p.skill == .Rocket {
		add_bullet(g, Bullet{
			pos = muzzle, vel = dir * ROCKET_SPEED, life = 4.0,
			from_player = true, rocket = true, homing = aimed, owner = index,
			range_left = ROCKET_RANGE,
		})
		p.fire_cd = skill_cooldown(p^, ROCKET_COOLDOWN_TICKS)
		spawn_burst(g, muzzle, skill_color(.Rocket), 6, 120, 2.5)
		add_shake(g, 1)
	} else {
		add_bullet(g, Bullet{
			pos = muzzle, vel = dir * PLAYER_BULLET_SPEED, life = 2.0,
			from_player = true, homing = true, owner = index,
			range_left = PLAYER_BULLET_RANGE,
		})
		p.fire_cd = PLAYER_FIRE_COOLDOWN_TICKS
		spawn_burst(g, muzzle, col, 3, 90, 2)
	}
}

// Regular enemies die, bosses lose `amount` hp.
damage_enemy :: proc(g: ^Game, e: ^Enemy, amount: i32, killer: ^Player, hit_pos: [2]f32) {
	if enemy_def(e.kind).is_boss {
		e.hp -= amount
		e.flash = 0.12
		spawn_burst(g, hit_pos, rl.WHITE, 6, 180, 2.5)
		if e.hp <= 0 {
			kill_enemy(g, e, killer)
		} else {
			add_shake(g, 2)
		}
	} else {
		kill_enemy(g, e, killer)
	}
}

rocket_explode :: proc(g: ^Game, pos: [2]f32, shooter: ^Player) {
	col := skill_color(.Rocket)
	spawn_burst(g, pos, col, 22, 260, 3.5)
	spawn_burst(g, pos, rl.Color{255, 220, 120, 255}, 12, 180, 3)
	spawn_ring(g, pos, col, 22, 230, 0.25, 3)
	add_shake(g, 3)

	for &e in g.enemies {
		if !e.active do continue
		epos := closest_wrapped_pos(e, pos)
		if linalg.length(epos - pos) - e.radius <= ROCKET_BLAST_RADIUS {
			damage_enemy(g, &e, ROCKET_BOSS_DAMAGE, shooter, epos)
		}
	}
}

// Nearest enemy on the map (the boss counts at its closest screen-wrapped copy).
// Enemies still off-screen are ignored.
// With `half_arc` < PI only enemies within that angle of `facing` count (a front slice).
nearest_enemy_to :: proc(g: ^Game, from: [2]f32, facing: f32 = 0, half_arc: f32 = math.PI) -> (pos: [2]f32, found: bool) {
	best: f32 = math.F32_MAX
	for e in g.enemies {
		if !e.active do continue
		epos := closest_wrapped_pos(e, from)
		if outside_play_area(epos, 0) do continue
		if half_arc < math.PI {
			off := epos - from
			if angle_gap(facing, math.atan2(off.y, off.x)) > half_arc do continue
		}
		d := linalg.length(epos - from)
		if d < best {
			best, pos, found = d, epos, true
		}
	}
	return
}

// The auto-fire target: nearest enemy inside the slice in front of the ship.
nearest_front_enemy :: proc(g: ^Game, p: Player) -> (pos: [2]f32, found: bool) {
	return nearest_enemy_to(g, player_center(p), p.angle, PLAYER_AUTOFIRE_ARC_DEG * 0.5 * math.RAD_PER_DEG)
}

// Turns the shot toward `target`, limited by PLAYER_BULLET_MIN_TURN_RADIUS (its curvature limit).
steer_player_shot :: proc(b: ^Bullet, target: [2]f32, dt: f32) {
	speed := linalg.length(b.vel)
	if speed < 0.001 do return
	cur  := math.atan2(b.vel.y, b.vel.x)
	want := math.atan2(target.y - b.pos.y, target.x - b.pos.x)
	max_turn := speed / PLAYER_BULLET_MIN_TURN_RADIUS * dt
	ang := turn_toward(cur, want, max_turn)
	b.vel = {math.cos(ang), math.sin(ang)} * speed
}

// Player shots hurt enemies only. Called from update_bullets.
update_player_shot :: proc(g: ^Game, b: ^Bullet, dt: f32) {
	if b.homing {
		if target, ok := nearest_enemy_to(g, b.pos); ok do steer_player_shot(b, target, dt)
	}
	b.pos += b.vel * dt
	b.range_left -= linalg.length(b.vel) * dt
	b.life -= dt
	shooter := &g.players[b.owner]

	r: f32 = PLAYER_BULLET_RADIUS
	if b.rocket do r = 5

	for &e in g.enemies {
		if !e.active do continue
		epos := closest_wrapped_pos(e, b.pos)
		if linalg.length(epos - b.pos) > e.radius + r do continue

		if b.rocket {
			rocket_explode(g, b.pos, shooter)
		} else {
			damage_enemy(g, &e, PLAYER_BULLET_BOSS_DAMAGE, shooter, b.pos)
			spawn_burst(g, b.pos, shooter.color, 4, 120, 2)
		}
		b.active = false
		return
	}

	if b.range_left <= 0 || b.life <= 0 {
		if b.rocket do rocket_explode(g, b.pos, shooter) // rockets detonate at the end of their range
		b.active = false
		return
	}
	if outside_play_area(b.pos, 0) do b.active = false
}

// --- Surprise: reflecting ---

reflect_bullet :: proc(g: ^Game, b: ^Bullet, p: ^Player, index: i32) {
	c := player_center(p^)
	dir := linalg.normalize0(b.pos - c)
	if linalg.length(dir) < 0.001 do dir = linalg.normalize0(-b.vel)
	b.vel = dir * max(linalg.length(b.vel), BULLET_SPEED) * 1.25
	b.pos += dir * 6
	b.reflected = true
	b.owner = index
	b.life = BULLET_LIFETIME
	spawn_burst(g, b.pos, p.color, 6, 160, 2.5)
}

// A reflected enemy flies away from the player as a missile. It will not hurt the
// player who reflected it, but it can hurt the other player. (Bosses are only knocked back.)
reflect_enemy :: proc(g: ^Game, e: ^Enemy, p: ^Player, index: i32, epos: [2]f32) {
	pc := player_center(p^)
	off := epos - pc
	dir := linalg.normalize0(off)
	if linalg.length(dir) < 0.001 {
		ang := rand.float32_range(0, 2 * math.PI)
		dir = {math.cos(ang), math.sin(ang)}
	}

	spawn_burst(g, pc + dir * 14, p.color, 14, 220, 3)
	spawn_ring(g, pc, skill_color(.Surprise), 18, 240, 0.3, 3)
	add_shake(g, 5)

	if enemy_def(e.kind).is_boss {
		e.hit_cd = BOSS_HIT_COOLDOWN
		e.dash_t = 0
		e.dash_windup = 0
		e.pos += dir * 160
		return
	}

	e.reflect_ticks = SURPRISE_REFLECT_TICKS
	e.reflect_owner = index
	e.reflect_vel = dir * SURPRISE_REFLECT_SPEED
	e.heading = dir
	e.angle = math.atan2(dir.y, dir.x)
	e.flash = 0.15
	e.pos = pc + dir * (max(p.size.x, p.size.y) * 0.5 + e.radius + 4)
}

// Per frame: reflected enemies fly on a straight line instead of chasing.
move_reflected_enemy :: proc(g: ^Game, e: ^Enemy, dt: f32) {
	e.pos += e.reflect_vel * dt
	e.angle = math.atan2(e.reflect_vel.y, e.reflect_vel.x)
	owner := &g.players[e.reflect_owner]
	spawn_particle(g, e.pos, {0, 0}, owner.color, 0.3, 4)
}

// --- Ticks ---

tick_player_skills :: proc(p: ^Player) {
	for k in SkillKind {
		if p.skill_cd[k] > 0 do p.skill_cd[k] -= 1
	}
	if p.fire_cd > 0        do p.fire_cd -= 1
	if p.invis_ticks > 0    do p.invis_ticks -= 1
	if p.surprise_ticks > 0 do p.surprise_ticks -= 1
	if p.slow_ticks > 0     do p.slow_ticks -= 1
}

tick_reflected_enemies :: proc(g: ^Game) {
	for &e in g.enemies {
		if e.active && e.reflect_ticks > 0 do e.reflect_ticks -= 1
	}
}

// Per-frame input: cycle, use skill, auto-fire (the fire key is a manual override).
handle_player_actions :: proc(g: ^Game) {
	for &p, i in g.players {
		if p.dead do continue
		if rl.IsKeyPressed(p.cycle_key) do cycle_skill(g, &p)
		if rl.IsKeyPressed(p.skill_key) do activate_skill(g, &p, i)
		// Auto-aim toggle: only meaningful for a skill that aims (Rocket); ignored otherwise.
		if skill_def(p.skill).has_aim_toggle && rl.IsKeyPressed(p.aim_key) {
			p.skill_aim = !p.skill_aim
			spawn_ring(g, player_center(p), skill_color(.Rocket), 14, 150, 0.3, 2.5)
		}

		// Auto-fire whenever an enemy is in the front slice. The fire key is disabled unless the taken
		// skill uses it (Rocket): then holding it also shoots, straight ahead if nothing is in the slice.
		// Rockets with auto-aim OFF never fire by themselves: they are fully manual.
		if p.fire_cd <= 0 {
			_, has_target := nearest_front_enemy(g, p)
			rocket := p.skill == .Rocket
			auto   := has_target && (!rocket || p.skill_aim)
			manual := rocket && rl.IsKeyDown(p.fire_key)
			if auto || manual do fire_gun(g, &p, i32(i))
		}
	}
}

// --- Skill dice pickups ---

spawn_skill_pickup :: proc(g: ^Game, pos: [2]f32) {
	for &pk in g.skill_pickups {
		if pk.active do continue
		pk = SkillPickup{
			pos    = {clamp(pos.x, 30, SCREEN_W - 30), clamp(pos.y, PLAY_MIN_Y + 15, SCREEN_H - 30)},
			life   = SKILL_PICKUP_LIFETIME,
			spin   = rand.float32_range(0, 6.28),
			active = true,
		}
		spawn_burst(g, pk.pos, rl.WHITE, 32, 170, 3)
		return
	}
}

// Very rare from any enemy; 25% from a boss on a "10th level".
roll_skill_drop :: proc(g: ^Game, pos: [2]f32, from_boss: bool) {
	chance: f32 = SKILL_DROP_CHANCE
	if from_boss {
		if g.level == SKILL_BOSS_GUARANTEED_LEVEL {
			chance = SKILL_BOSS_GUARANTEED_CHANCE // level 5: always (100%)
		} else if g.level % SKILL_BOSS_LEVEL_INTERVAL == 0 {
			chance = SKILL_BOSS_DROP_CHANCE
		}
	}
	if rand.float32() < chance do spawn_skill_pickup(g, pos + [2]f32{0, 40})
}

any_skill_pickup :: proc(g: ^Game) -> bool {
	for pk in g.skill_pickups {
		if pk.active do return true
	}
	return false
}

// Touching a die rolls a random skill, which becomes the player's taken skill.
collect_skill_pickups :: proc(g: ^Game) {
	for &pk in g.skill_pickups {
		if !pk.active do continue

		collector: ^Player = nil
		best: f32 = math.F32_MAX
		for &p in g.players {
			if p.dead do continue
			if !rl.CheckCollisionCircleRec(pk.pos, SKILL_PICKUP_RADIUS, player_rect(p)) do continue
			d := linalg.length(player_center(p) - pk.pos)
			if d < best {
				best = d
				collector = &p
			}
		}
		if collector == nil do continue

		grant_skill(g, collector, skill_at(int(rand.int31_max(SKILL_COUNT))))
		spawn_burst(g, pk.pos, rl.WHITE, 40, 240, 4)
		pk.active = false
	}
}

update_skill_pickups :: proc(g: ^Game, dt: f32) {
	// Like statuses, the timer pauses on the portal screen.
	for &pk in g.skill_pickups {
		if !pk.active do continue
		pk.spin += dt
		if g.phase != .LevelComplete && g.phase != .Sucking {
			pk.life -= dt
			if pk.life <= 0 do pk.active = false
		}
	}
}

DIE_PIPS :: [6]u16{16, 257, 273, 325, 341, 365} // bit n = cell n of a 3x3 grid

// A tumbling die: its faces keep rolling because the skill is decided on pickup.
draw_skill_pickups :: proc(g: ^Game) {
	t := g.time
	for pk in g.skill_pickups {
		if !pk.active do continue
		if pk.life < 3 && g.phase != .LevelComplete && g.phase != .Sucking && int(pk.life * 8) % 2 == 0 do continue

		hue := math.mod(t * 120 + pk.spin * 57, 360)
		col := rl.ColorFromHSV(hue, 0.65, 1.0)
		pulse := 1.0 + 0.1 * math.sin(t * 6 + pk.spin)

		rl.BeginBlendMode(.ADDITIVE)
		draw_glow(pk.pos, 34 * pulse, col, 0.5)
		rl.EndBlendMode()

		rot := t * 1.3 + pk.spin
		h := 11 * pulse
		corners := [4][2]f32{{-h, -h}, {h, -h}, {h, h}, {-h, h}}
		pts: [4][2]f32
		for c, i in corners do pts[i] = pk.pos + rotate_vec(c, rot)
		toon_quad(pts[0], pts[1], pts[2], pts[3], rl.Color{240, 240, 248, 255})

		pips := DIE_PIPS
		face := int(t * 9 + pk.spin * 3) % 6
		step := h * 0.55
		for cell in 0 ..< 9 {
			if pips[face] & (u16(1) << u16(cell)) == 0 do continue
			local := [2]f32{f32(cell % 3 - 1) * step, f32(cell / 3 - 1) * step}
			rl.DrawCircleV(pk.pos + rotate_vec(local, rot), h * 0.15, rl.Color{25, 25, 40, 255})
		}
	}
}
