package main

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

	p.runner_turn_rate = RUNNER_TURN_RATE_BASE + RUNNER_TURN_RATE_STEP * t
	p.runner_cone      = min(RUNNER_CONE_BASE + RUNNER_CONE_STEP * t, RUNNER_CONE_MAX)

	p.is_boss_level    = level > 0 && level % BOSS_LEVEL_INTERVAL == 0
	p.boss_has_ability = level > 0 && level % BOSS_ABILITY_LEVEL_INTERVAL == 0
	tier := max(level / BOSS_LEVEL_INTERVAL, 1)
	p.boss_hp = BOSS_HP_BASE + (tier - 1) * BOSS_HP_PER_TIER
	p.boss_summon_cd = max(BOSS_SUMMON_COOLDOWN_BASE - BOSS_SUMMON_COOLDOWN_STEP * t, BOSS_SUMMON_COOLDOWN_MIN)
	p.boss_summons   = level != BOSS_NO_MINION_LEVEL // level 5: the boss fights alone
	return p
}

// Total score (both players combined) at which `level` ends.
// Level n asks for LEVEL_SCORE_BASE + GROWTH * (n - 1) points on top of the last.
level_goal_total :: proc(level: i32) -> i32 {
	n := level
	return n * LEVEL_SCORE_BASE + LEVEL_SCORE_GROWTH * (n * (n - 1) / 2)
}

// (Which enemy a regular spawn becomes: pick_enemy_kind in enemy_defs.odin.)
