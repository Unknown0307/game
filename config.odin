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
PORTAL_RADIUS    :: 62.0 // how close to the black hole a ship must be to enter
BLACK_HOLE_RADIUS :: 26.0 // event-horizon radius when fully open
SUCK_TIME        :: 1.6  // ships spiral into the black hole (seconds)
SPIT_TIME        :: 1.1  // ships are flung back out of the black hole (seconds)

// --- Player ---
PLAYER_MAX_SPEED  :: 300.0
MAX_HEALTH          :: 50 // a player dies after this many tags
REPULSION_RADIUS  :: 180.0

MAP_DIAGONAL :: 1000.0 // sqrt(SCREEN_W^2 + SCREEN_H^2): the longest straight line on the map
BLAST_VISUAL_TIME :: 0.25
KNOCK_DECAY       :: 6.0 // how fast boss knock-back velocity fades (1/s)

// --- Player gun (the common ability: always available) ---
PLAYER_FIRE_COOLDOWN_TICKS :: 18     // ticks between shots (alternates between the two wing guns)
PLAYER_BULLET_SPEED        :: 560.0
PLAYER_BULLET_RANGE        :: MAP_DIAGONAL // shots fly across the whole map (bullet life = 2 s = 1120 px, so the map edge ends them)
PLAYER_BULLET_RADIUS       :: 3.5
// Player shots (bullets and rockets) auto-fire and home in on the nearest enemy, but they
// cannot turn sharper than this circle: turn rate = speed / radius (bigger = wider curves).
// At 560 px/s, 140 px is 4 rad/s; try 70 for sharp homing or 300 for lazy arcs.
PLAYER_BULLET_MIN_TURN_RADIUS :: 140.0
// Auto-fire only picks targets inside this slice in front of the ship (total angle, centred on
// the way the ship faces). 360 = all around, 90 = a quarter-circle slice.
PLAYER_AUTOFIRE_ARC_DEG :: 90.0
PLAYER_BULLET_BOSS_DAMAGE  :: 1
PLAYER_TRAIL_LENGTH        :: 32     // P1's long fading ribbon (frames of history)
PLAYER2_TRAIL_LENGTH       :: 14

// --- Skills: found as dice pickups, one slot each in the player's wheel ---
// Every timer is in 60 Hz ticks. Seconds are converted with TICK_RATE.
EXPLOSION_COOLDOWN_TICKS :: i32(2 * TICK_RATE)   // 2 s  = 120 ticks (the old blast cooldown)
ROCKET_COOLDOWN_TICKS    :: 40                   // time between rockets
ROCKET_SPEED             :: 500.0
ROCKET_RANGE             :: MAP_DIAGONAL         // rockets also cross the whole map (never less than a normal shot)
ROCKET_BLAST_RADIUS      :: 40.0                 // small explosion
ROCKET_BOSS_DAMAGE       :: 4
INVIS_DURATION_TICKS     :: i32(5 * TICK_RATE)   // 5 s  = 300 ticks of invulnerability
INVIS_COOLDOWN_TICKS     :: i32(10 * TICK_RATE)  // 10 s = 600 ticks (counted from activation)
SURPRISE_DURATION_TICKS  :: 40                   // reflect window
SURPRISE_COOLDOWN_TICKS  :: i32(15 * TICK_RATE)  // 15 s = 900 ticks (counted from activation)
SURPRISE_REFLECT_SPEED   :: 440.0                // speed of a reflected enemy
SURPRISE_REFLECT_TICKS   :: 75                   // how long a reflected enemy stays a missile
REPEL_COOLDOWN_TICKS     :: i32(3 * TICK_RATE)   // 3 s  = 180 ticks
REPEL_RADIUS_SHIPS       :: 6.0                  // reach AND push distance, in ship sizes (30 px ship -> 180 px)
REPEL_VISUAL_TIME        :: 0.4
SKILL_WHEEL_BIG          :: 3.0                  // wheel weight of the taken skill (others = 1.0)

// --- Skill dice drops (rarer than enhancements) ---
SKILL_DROP_CHANCE          :: 0.002  // any killed enemy (enhancements: 0.0067)
SKILL_BOSS_DROP_CHANCE     :: 0.25   // boss on a "10th level"
SKILL_BOSS_LEVEL_INTERVAL  :: 10     // set to BOSS_LEVEL_INTERVAL to let every boss drop one
SKILL_PICKUP_LIFETIME      :: 20.0
SKILL_PICKUP_RADIUS        :: 14.0
MAX_SKILL_PICKUPS          :: 4
SKILL_GIFT_LEVEL           :: 4     // on this level every player is given one skill die at the start
SKILL_BOSS_GUARANTEED_LEVEL  :: 5   // the boss of this level ALWAYS drops a skill die...
SKILL_BOSS_GUARANTEED_CHANCE :: 1.0 // ...(100%; with two bosses each of them drops one)

// --- Freeze skill: everything except the players stops for 3 s ---
FREEZE_DURATION_TICKS :: i32(3 * TICK_RATE)   // 3 s  = 180 ticks frozen
FREEZE_COOLDOWN_TICKS :: i32(30 * TICK_RATE)  // 30 s = 1800 ticks, counted AFTER the freeze has ended
FREEZE_VISUAL_TIME    :: 0.6                  // seconds of the expanding frost wave
FREEZE_FADE_TICKS     :: 36                   // the ice melts away over the last 0.6 s

// --- Come Back skill: jump back to where you were 5 s ago (once per level) ---
REWIND_TICKS          :: 300                  // 5 s at 60 Hz of recorded history per player
COMEBACK_VISUAL_TIME  :: 0.5

// --- Mothership boss skin (the alternative to the space whale) ---
MOTHERSHIP_CHANCE                :: 0.5
MOTHERSHIP_BULLET_COOLDOWN_TICKS :: 40
MOTHERSHIP_BULLET_FIRST_TICKS    :: 90
MOTHERSHIP_GUN_RANGE             :: 620.0
MOTHERSHIP_RAY_COOLDOWN_TICKS    :: i32(10 * TICK_RATE) // 10 s = 600 ticks
MOTHERSHIP_RAY_FIRST_TICKS       :: i32(4 * TICK_RATE)  // first raygun comes a bit sooner
RAY_CHARGE_TICKS         :: 50     // telegraph: the mothership stops and aims
RAY_TICKS                :: 36     // how long the beam stays on
RAY_LENGTH               :: 560.0
RAY_WIDTH                :: 18.0
RAY_DAMAGE               :: 3
RAY_HIT_INTERVAL_TICKS   :: 6

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
BOSS_ABILITY_LEVEL_INTERVAL :: 5  // ...and every boss has the repel + summon + dash abilities
BOSS_HP_BASE        :: 24
BOSS_HP_PER_TIER    :: 10         // +10 hp each time a boss appears
BOSS_RADIUS         :: 48.0
BOSS_BASE_SPEED     :: 215.0
BOSS_SPEED_CAP      :: 0.92       // fraction of player speed the boss can never exceed
BOSS_DAMAGE         :: 10
BOSS_HIT_COOLDOWN   :: 0.9
BOSS_SCORE          :: 300

// Boss enrage: below this share of its health the boss gets faster and meaner.
BOSS_ENRAGE_FRACTION   :: 0.5
BOSS_ENRAGE_SPEED      :: 1.30
BOSS_ENRAGE_SPEED_CAP  :: 0.97  // fraction of player speed

// Boss lunge: it locks onto the nearest player, telegraphs, then rockets forward.
BOSS_DASH_RANGE        :: 430.0
BOSS_DASH_WINDUP       :: 0.65  // telegraph time (boss stands still, aiming)
BOSS_DASH_TIME         :: 0.50
BOSS_DASH_SPEED        :: 640.0
BOSS_DASH_COOLDOWN     :: 6.0
BOSS_DASH_FIRST_DELAY  :: 3.0

// Boss repel ability (every boss)
BOSS_REPEL_RADIUS       :: 230.0
BOSS_REPEL_CHARGE       :: 0.7  // telegraph time; the boss stands still while charging
BOSS_REPEL_FORCE        :: 1100.0
BOSS_REPEL_COOLDOWN     :: 3.2
BOSS_REPEL_VISUAL_TIME  :: 0.35
BOSS_FIRST_REPEL_DELAY  :: 1.5
BOSS_FIRST_SUMMON_DELAY :: 2.0

// Boss summons (used only when both players are outside the repel radius)
BOSS_SUMMON_COOLDOWN_BASE :: 3.0
BOSS_SUMMON_COOLDOWN_STEP :: 0.05
BOSS_SUMMON_COOLDOWN_MIN  :: 1.2
BOSS_SUMMON_MINIONS       :: 3 // baby whales per summon (+2 while enraged)
BOSS_NO_MINION_LEVEL      :: 5 // the boss of this level never summons minions
DOUBLE_BOSS_LEVEL         :: 5    // this level may spawn two bosses...
DOUBLE_BOSS_CHANCE        :: 0.10 // ...with this probability

// --- Big enemy weapons (tick based, 60 ticks = 1 second) ---
BIG_SHOOT_COOLDOWN_TICKS :: 20    // one bullet every 20 ticks (alternating turrets)
BIG_GUN_RANGE            :: 480.0 // only fires at a target this close
BIG_AIM_TOLERANCE        :: 0.45  // radians: must be roughly facing the target to fire
BIG_LASER_CHANCE         :: 0.35  // share of Big spawns that carry a laser instead of guns

BULLET_SPEED    :: 330.0
BULLET_RADIUS   :: 4.0
BULLET_DAMAGE   :: 1
BULLET_LIFETIME :: 3.0
MAX_BULLETS     :: 240

LASER_TICKS              :: 10    // how long the beam stays on
// The laser cruiser's beam now runs from its centre to the END OF THE MAP (see laser_length in gunfire.odin).
LASER_COOLDOWN_TICKS     :: 60    // pause after the beam switches off
LASER_TRIGGER_RANGE      :: MAP_DIAGONAL // fires at any target on the map (it still has to face it and be on-screen)
LASER_WIDTH              :: 7.0
LASER_DAMAGE             :: 1
LASER_HIT_INTERVAL_TICKS :: 5     // the beam hurts every 5 ticks (3 hits per shot)

// --- Enhancements ---
MAX_ENHANCEMENTS              :: 3
ENHANCEMENT_DROP_CHANCE       :: 0.0067 // any killed enemy
BOSS_DOUBLE_ENHANCEMENT_CHANCE :: 0.10  // a boss always drops one; 10% for a second
ENH_PICKUP_LIFETIME           :: 20.0
ENH_PICKUP_RADIUS             :: 13.0
MAX_HEALTH_BONUS_PER_COPY     :: 0.10 // "Max health" enhancement: +10% of the base max health per copy

// --- "Minion" enhancement: an allied laser drone that follows its summoner ---
MAX_PLAYER_MINIONS        :: PLAYER_COUNT * MAX_ENHANCEMENTS // one per Minion enhancement copy
MINION_RADIUS             :: 14.0
MINION_HEALTH_SHARE       :: 0.5    // minion max health = this share of the summoner's max health
MINION_FOLLOW_DIST        :: 58.0   // orbit distance around the summoner
MINION_MAX_SPEED          :: 420.0
MINION_LEASH              :: 320.0  // farther than this from the summoner (screen wrap...) = teleport next to it
MINION_TURN_RATE          :: 8.0    // rad/s, same as the laser cruisers
MINION_AIM_TOLERANCE      :: 0.25   // radians: must face the target to fire
MINION_LASER_COOLDOWN_TICKS :: 75   // a bit slower than the cruiser's 60
MINION_LASER_DAMAGE       :: 1

// --- Pickups ---
COIN_RADIUS      :: 9.0
COIN_LIFETIME    :: 10.0
COIN_SCORE       :: 10
COIN_DROP_CHANCE :: 0.25
ALLY_RADIUS      :: 14.0
ALLY_HP          :: 3
ALLY_LIFETIME    :: 15.0
HEAL_AMOUNT      :: 10

// --- Asteroids (drifting rocks; they do not chase) ---
ASTEROID_RADIUS_MIN       :: 9.0
ASTEROID_RADIUS_MAX       :: 24.0
ASTEROID_SPEED_MIN        :: 60.0
ASTEROID_SPEED_MAX        :: 150.0
ASTEROID_POINTS           :: 4
ASTEROID_RATE_IDLE        :: 0.15  // per second while no asteroid belt is on the map
ASTEROID_RATE_BELT        :: 2.2   // per second while a belt is on the map (high!)
ASTEROID_SAFE_DIST        :: 140.0 // belt asteroids never appear this close to a living player

// --- Space backdrop (backdrop.odin): planets, suns, pulsars that drift across the map ---
MAX_BODIES            :: 3
BODY_DRIFT_MIN        :: 5.0    // px/s
BODY_DRIFT_MAX        :: 12.0
BODY_BELT_CHANCE      :: 0.45   // planets / suns / ringless gas giants; pulsars use a lower chance
