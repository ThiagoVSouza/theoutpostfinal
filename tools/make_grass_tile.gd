extends SceneTree
## Makes the grassland tile, assets/textures/grass_meadow.png, from Astra's highland-meadow diorama.
##
##   godot --headless --path . --script tools/make_grass_tile.gd -- "<path to highland-meadow.glb>"
##
## The diorama's ground is one 4096 x 4096 colour image mapped once over its 240 m x 220 m terrain,
## mottled olive with the footpath painted into it. Its normal map is flat, so only the colour is
## taken. This reads that image straight out of the GLB, cuts a square from a part the path does
## not cross, and makes it repeat without a seam.
##
## The seam is removed by cross-fading the cut with a copy of itself shifted by half: near the edges
## the shifted copy is used, which wraps continuously because its edges came from the middle of the
## cut, and in the middle the original is used, which hides the shifted copy's own seam there. On a
## mottled texture with no straight features the cross-fade does not show.
##
## The cut is 1536 texels square, so it keeps the diorama's own resolution: 240 m / 4096 = 5.86 cm a
## texel across and 220 m / 4096 = 5.37 cm down, which makes one repeat 90.0 m x 82.5 m. The shader's
## grass_tile_size has to match. Prints the tile's mean colour, which the shader's grass_mean holds.

const OUTPUT := "res://assets/textures/grass_meadow.png"
## The square taken from the 4096 image: clear of the footpath, which runs from about (720, 1720) to
## (3400, 2960), and clear of the image's border.
const CUT := Rect2i(1024, 64, 1536, 1536)
## How far in from each edge the cross-fade reaches, as a fraction of the tile.
const BLEND := 0.25

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Pass the path to highland-meadow.glb after --")
		quit(1)
		return
	var source := _ground_image(args[0])
	if source == null:
		quit(1)
		return
	var cut := source.get_region(CUT)
	var tile := _seamless(cut)
	var error := tile.save_png(ProjectSettings.globalize_path(OUTPUT))
	if error != OK:
		push_error("Could not write %s: %s" % [OUTPUT, error_string(error)])
		quit(1)
		return
	var mean := _mean(tile)
	print("Saved %s (%d x %d)." % [OUTPUT, tile.get_width(), tile.get_height()])
	print("MEAN_SRGB %.4f %.4f %.4f" % [mean.r, mean.g, mean.b])
	print("Run `godot --headless --path . --editor --import` before the game loads it.")
	quit()

## The first image in the GLB, which is the diorama ground's colour. Read from the binary chunk
## directly: importing the whole 250 MB scene to reach one texture would build every mesh in it.
func _ground_image(path: String) -> Image:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open %s" % path)
		return null
	if file.get_32() != 0x46546C67:
		push_error("%s is not a GLB" % path)
		return null
	file.get_32()
	file.get_32()
	var json_length := file.get_32()
	file.get_32()
	var gltf: Variant = JSON.parse_string(file.get_buffer(json_length).get_string_from_utf8())
	file.get_32()
	file.get_32()
	var binary_start := file.get_position()
	var view: Dictionary = gltf.bufferViews[int(gltf.images[0].bufferView)]
	file.seek(binary_start + int(view.get("byteOffset", 0)))
	var bytes := file.get_buffer(int(view.byteLength))
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		push_error("The GLB's first image is not a readable PNG")
		return null
	image.convert(Image.FORMAT_RGB8)
	return image

func _seamless(cut: Image) -> Image:
	var size := cut.get_width()
	var half := size / 2
	var reach := float(size) * BLEND
	var tile := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var shifted := cut.get_pixel((x + half) % size, (y + half) % size)
			var original := cut.get_pixel(x, y)
			var edge := minf(minf(x, size - 1 - x), minf(y, size - 1 - y))
			var t := clampf(edge / reach, 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			tile.set_pixel(x, y, shifted.lerp(original, t))
	return tile

## Mean colour in linear light, returned as sRGB, which is what a far-off view of it averages to.
func _mean(image: Image) -> Color:
	var total := Color(0, 0, 0)
	var count := 0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			var c := image.get_pixel(x, y).srgb_to_linear()
			total.r += c.r
			total.g += c.g
			total.b += c.b
			count += 1
	return Color(total.r / count, total.g / count, total.b / count).linear_to_srgb()
