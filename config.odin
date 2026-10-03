package main

// =============================================================================
// config.odin - every tunable number lives here. Gameplay code never uses
// magic numbers; change the feel of the game by editing this file only.
// =============================================================================

// --- Screen (logical canvas, stretched to the window) ---
SCREEN_W   :: 800
SCREEN_H   :: 600
PLAY_MIN_Y :: 110 // top edge of the playable area (below the HUD)

// --- Capacities (fixed pools, no allocation during play) ---
MAX_ENEMIES     :: 500
MAX_COINS       :: 24
MAX_ALLIES      :: 4
MAX_PARTICLES   :: 2000
MAX_FLOATS      :: 32
MAX_ENH_PICKUPS :: 6
PLAYER_COUNT    :: 2

// --- Timing ---
TICK_RATE        :: 60.0
TICK_DT          :: 1.0 / TICK_RATE
LEVEL_COUNTDOWN  :: 10.0
PORTAL_OPEN_TIME :: 1.25
PORTAL_RADIUS    :: 58.0

// --- Player ---
PLAYER_MAX_SPEED  :: 300.0
MAX_TAGS          :: 50 // a player dies after this many tags
REPULSION_RADIUS  :: 180.0
ABILITY_COOLDOWN  :: 2.0
BLAST_VISUAL_TIME :: 0.25
KNOCK_DECAY       :: 6.0 // how fast boss knock-back velocity fades (1/s)

// --- Shields / barriers ---
MAX_SHIELDS           :: 3
SHIELD_DURATION_TICKS :: 300
BARRIER_ALLY_CHANCE   :: 0.30

// --- Difficulty: every value below scales LINEARLY with (level - 1) ---
// See difficulty.odin. "clamp" values are safety ceilings so the game stays
// playable at very high levels; they are only reached after many levels.
BASE_ENEMY_SPEED_MULT :: 0.80  // was a flat 0.70
SPEED_MULT_PER_LEVEL  :: 0.045
MAX_ENEMY_SPEED_MULT  :: 1.80  // clamp (reached around level 23)

BASE_SPAWN_RATE       :: 2.0   // enemies per second at level 1
SPAWN_RATE_PER_LEVEL  :: 0.10

// Chance that a spawn is a special type (the rest are Normal).
STICKY_CHANCE_BASE    :: 0.09
STICKY_CHANCE_STEP    :: 0.004
STICKY_CHANCE_MAX     :: 0.18
BIG_CHANCE_BASE       :: 0.11
BIG_CHANCE_STEP       :: 0.004
BIG_CHANCE_MAX        :: 0.20
RUNNER_CHANCE_BASE    :: 0.25
RUNNER_CHANCE_STEP    :: 0.006
RUNNER_CHANCE_MAX     :: 0.40

// Runners become better at steering as levels rise.
RUNNER_TURN_RATE_BASE :: 0.85 // radians/second
RUNNER_TURN_RATE_STEP :: 0.04
RUNNER_CONE_BASE      :: 0.38 // radians; target must be inside this cone to steer
RUNNER_CONE_STEP      :: 0.010
RUNNER_CONE_MAX       :: 0.80
RUNNER_CULL_MARGIN    :: 150.0 // runners that fly this far off-screen are removed

// Score needed to finish a level. Each level asks for a bit more than the last.
LEVEL_SCORE_BASE   :: 1000
LEVEL_SCORE_GROWTH :: 100

// --- Sticky ("bomb") enemy ---
STICKY_STICK_TICKS      :: 5
STICKY_EXPLOSION_RADIUS :: 54.0
STICKY_EXPLOSION_DAMAGE :: 10

// --- Boss ---
BOSS_LEVEL_INTERVAL         :: 5  // a boss appears on every 5th level
BOSS_ABILITY_LEVEL_INTERVAL :: 10 // ...and has the repel ability on every 10th
BOSS_HP_BASE        :: 6
BOSS_HP_PER_TIER    :: 2          // +2 hp each time a boss appears
BOSS_RADIUS         :: 48.0
BOSS_BASE_SPEED     :: 190.0
BOSS_SPEED_CAP      :: 0.85       // fraction of player speed the boss can never exceed
BOSS_DAMAGE         :: 8
BOSS_HIT_COOLDOWN   :: 1.2
BOSS_SCORE          :: 200

// Boss repel ability (every 10th level)
BOSS_REPEL_RADIUS       :: 230.0
BOSS_REPEL_CHARGE       :: 0.7  // telegraph time; the boss stands still while charging
BOSS_REPEL_FORCE        :: 1100.0
BOSS_REPEL_COOLDOWN     :: 4.0
BOSS_REPEL_VISUAL_TIME  :: 0.35
BOSS_FIRST_REPEL_DELAY  :: 1.5
BOSS_FIRST_SUMMON_DELAY :: 2.0

// Boss summons (used only when both players are outside the repel radius)
BOSS_SUMMON_COOLDOWN_BASE :: 3.0
BOSS_SUMMON_COOLDOWN_STEP :: 0.05
BOSS_SUMMON_COOLDOWN_MIN  :: 1.2
BOSS_SUMMON_RUNNERS       :: 2
BOSS_BOMB_CHANCE          :: 0.40

// --- Enhancements ---
MAX_ENHANCEMENTS              :: 3
ENHANCEMENT_DROP_CHANCE       :: 0.0067 // any killed enemy
BOSS_DOUBLE_ENHANCEMENT_CHANCE :: 0.10  // a boss always drops one; 10% for a second
ENH_PICKUP_LIFETIME           :: 20.0
ENH_PICKUP_RADIUS             :: 13.0

// --- Pickups ---
COIN_RADIUS      :: 9.0
COIN_LIFETIME    :: 10.0
COIN_SCORE       :: 10
COIN_DROP_CHANCE :: 0.25
ALLY_RADIUS      :: 14.0
ALLY_HP          :: 3
ALLY_LIFETIME    :: 15.0
HEAL_AMOUNT      :: 10
