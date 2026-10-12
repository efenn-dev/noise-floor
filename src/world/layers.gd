class_name Layers
extends RefCounted
## Physics layer bits. WORLD = ground, town, player. BUILT = player-built pieces. ZOMBIE = zombie bodies.
## BAG = dropped death bags (nothing collides with them; only the interact ray looks for them).

const WORLD := 1
const BUILT := 2
const ZOMBIE := 4
const BAG := 8
