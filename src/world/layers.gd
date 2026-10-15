class_name Layers
extends RefCounted
## Physics layer bits. WORLD = ground, town, player. BUILT = player-built pieces. ZOMBIE = zombie bodies.
## BAG = dropped death bags (nothing collides with them; only the interact ray looks for them).
## TRAP = spike strips (same: walk over them, only rays see them).

const WORLD := 1
const BUILT := 2
const ZOMBIE := 4
const BAG := 8
const TRAP := 16  # spike strips: walk-over, only rays (aiming, building) see them
const CEILING := 32  # V24: house and factory ceilings: only the walker bumps its head on them (navmesh and rays ignore them)
const HITBOX := 64  # V33: zombies' bone hit zones (Area3D): only gun and melee rays look for them
