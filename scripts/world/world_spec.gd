class_name WorldSpec
extends RefCounted
## The board's dimensions. One Godot unit is one metre.
##
## The board is 100 km square: 1000 x 1000 tiles of 100 m, each divided into 10 x 10 subtiles of
## 10 m, the cell building placement works on. Regions of 10 km are the coarsest tier, the only
## structure still legible when the whole board is in view. The board is centred on the origin
## at y = 0, so it spans -50 km to +50 km on x and z.

const BOARD_SIZE := 100000.0
const HALF_BOARD := BOARD_SIZE * 0.5
const REGION := 10000.0
const TILE := 100.0
const SUBTILE := 10.0
const TILES_PER_SIDE := 1000
const SUBTILES_PER_TILE := 10

## The wood frame around the board: its width on each side, how far its top stands above the
## board and how far its outer wall drops below it.
const FRAME_WIDTH := 2000.0
const FRAME_HEIGHT := 400.0
const FRAME_DEPTH := 600.0
