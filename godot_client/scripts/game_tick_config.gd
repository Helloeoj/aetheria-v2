class_name GameTickConfig
extends RefCounted

## The shared world tick advances at this cadence. Monsters attack every three
## ticks; player attacks use weapon intervals; movement and projectiles use frame delta.
const TICK_DURATION_SECONDS := 0.6
const TICKS_PER_SECOND := 1.0 / TICK_DURATION_SECONDS
const MONSTER_ATTACK_INTERVAL_TICKS := 3
const MONSTER_CHASE_LEASH_TILES := 20.0
