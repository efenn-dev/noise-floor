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
