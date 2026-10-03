package main

import "core:math/rand"

// =============================================================================
// difficulty.odin - the one place that turns a level number into numbers.
// Everything scales linearly with t = level - 1 (up to the clamps in config).
// =============================================================================

level_params :: proc(level: i32) -> LevelParams {
	t := f32(max(level - 1, 0))
	p: LevelParams

	p.level          = level
	p.speed_mult     = min(BASE_ENEMY_SPEED_MULT + SPEED_MULT_PER_LEVEL * t, MAX_ENEMY_SPEED_MULT)
	p.spawn_interval = 1.0 / (BASE_SPAWN_RATE + SPAWN_RATE_PER_LEVEL * t)

	p.sticky_chance = min(STICKY_CHANCE_BASE + STICKY_CHANCE_STEP * t, STICKY_CHANCE_MAX)
	p.big_chance    = min(BIG_CHANCE_BASE + BIG_CHANCE_STEP * t, BIG_CHANCE_MAX)
	p.runner_chance = min(RUNNER_CHANCE_BASE + RUNNER_CHANCE_STEP * t, RUNNER_CHANCE_MAX)

	p.runner_turn_rate = RUNNER_TURN_RATE_BASE + RUNNER_TURN_RATE_STEP * t
	p.runner_cone      = min(RUNNER_CONE_BASE + RUNNER_CONE_STEP * t, RUNNER_CONE_MAX)

	p.is_boss_level    = level > 0 && level % BOSS_LEVEL_INTERVAL == 0
	p.boss_has_ability = level > 0 && level % BOSS_ABILITY_LEVEL_INTERVAL == 0
	tier := max(level / BOSS_LEVEL_INTERVAL, 1)
	p.boss_hp = BOSS_HP_BASE + (tier - 1) * BOSS_HP_PER_TIER
	p.boss_summon_cd = max(BOSS_SUMMON_COOLDOWN_BASE - BOSS_SUMMON_COOLDOWN_STEP * t, BOSS_SUMMON_COOLDOWN_MIN)
	return p
}

// Total score (both players combined) at which `level` ends.
// Level n asks for LEVEL_SCORE_BASE + GROWTH * (n - 1) points on top of the last.
level_goal_total :: proc(level: i32) -> i32 {
	n := level
	return n * LEVEL_SCORE_BASE + LEVEL_SCORE_GROWTH * (n * (n - 1) / 2)
}

// Picks which enemy type a regular spawn should be.
pick_enemy_kind :: proc(p: LevelParams) -> EnemyKind {
	roll := rand.float32()
	if roll < p.sticky_chance do return .Sticky
	roll -= p.sticky_chance
	if roll < p.big_chance do return .Big
	roll -= p.big_chance
	if roll < p.runner_chance do return .Runner
	return .Normal
}
