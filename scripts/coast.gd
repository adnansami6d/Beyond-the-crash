extends Node3D
# Coast of the map: sea on all four sides (outside the map), sand beach inside the map.
# v_022: you can walk into the sea. The sea floor slopes down gently (SEA_DEPTH metres deep after SEA_RUN metres from the shore);
# there an invisible wall stops you - you can always walk back. The tall edge walls (nothing leaves, not even the helicopter) stand there too.
# made by fx_map.gd -> build(half)   (Beyond the Crash: floors on layer 2, walls on layer 1)

const Util = preload("res://scripts/util.gd")
const SEA_RUN := 100.0     # v_022: metres of walkable sea floor from the shore (the map edge)
const SEA_DEPTH := 3.0     # v_022: depth at the end of it (head under water only far out)
const SLOPE := SEA_DEPTH / SEA_RUN
const BEACH := 18.0   # sand strip width inside the map


func build(half: float) -> void:
	var run := SEA_RUN
	var ang := atan(SLOPE)
	var sand := Util.mat(Color(0.84, 0.76, 0.52), 1.0)
	var water := Util.mat(Color(0.1, 0.42, 0.66), 0.12, 0.2)
	var long := half * 2.0 + run * 2.0 + 20.0

	# sand beaches inside the map (west, east, south)
	Util.part(self, Vector3(BEACH, 0.04, half * 2.0), Vector3(-half + BEACH / 2.0, 0.02, 0), sand)
	Util.part(self, Vector3(BEACH, 0.04, half * 2.0), Vector3(half - BEACH / 2.0, 0.02, 0), sand)
	Util.part(self, Vector3(half * 2.0 - BEACH * 2.0, 0.04, BEACH), Vector3(0, 0.02, half - BEACH / 2.0), sand)

	# sea: three big water plates outside the map
	Util.part(self, Vector3(500, 0.1, 1400), Vector3(-half - 250, -0.05, 0), water)
	Util.part(self, Vector3(500, 0.1, 1400), Vector3(half + 250, -0.05, 0), water)
	Util.part(self, Vector3(half * 2.0, 0.1, 500), Vector3(0, -0.05, half + 250), water)

	# sloping sea floor (collision only) + stop walls. side = outward direction
	for side in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(run / cos(ang) if side.x != 0.0 else long, 1.0, long if side.x != 0.0 else run / cos(ang))
		cs.shape = sh
		var mid := run / 2.0
		var nrm := Vector3(side.x * sin(ang), cos(ang), side.y * sin(ang))
		var top := Vector3(side.x * (half + mid), -SEA_DEPTH / 2.0, side.y * (half + mid))
		cs.position = top - nrm * 0.5
		if side.x != 0.0:
			cs.rotation = Vector3(0, 0, -ang * side.x)
		else:
			cs.rotation = Vector3(ang * side.y, 0, 0)
		body.add_child(cs)
		body.collision_layer = 2   # Beyond the Crash: the sea floor is ground (layer 2, like the voxel ground), the stop wall below is layer 1
		body.collision_mask = 0
		body.add_to_group("voxel_ground")
		var wall_body := StaticBody3D.new()
		var wall := CollisionShape3D.new()
		var ws := BoxShape3D.new()
		ws.size = Vector3(1.0 if side.x != 0.0 else long, 12.0, long if side.x != 0.0 else 1.0)
		wall.shape = ws
		wall.position = Vector3(side.x * (half + run + 0.5), 2.0, side.y * (half + run + 0.5))
		wall_body.add_child(wall)
		add_child(wall_body)
		add_child(body)

	# north: sand + sea instead of the old hill
	Util.part(self, Vector3(half * 2.0 - BEACH * 2.0, 0.04, BEACH), Vector3(0, 0.02, -half + BEACH / 2.0), sand)
	Util.part(self, Vector3(half * 2.0, 0.1, 500), Vector3(0, -0.05, -half - 250), water)

	# invisible walls round the walkable sea (SEA_RUN m outside the map edge), from below the floor up to 200 m (nothing can leave, not even the helicopter)
	var wall_h := 210.0
	var edge := half + run - 0.5
	var body := StaticBody3D.new()
	body.name = "EdgeWalls"
	for side in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		if side.x != 0.0:
			sh.size = Vector3(2.0, wall_h, (half + run) * 2.0 + 4.0)
		else:
			sh.size = Vector3((half + run) * 2.0 + 4.0, wall_h, 2.0)
		cs.shape = sh
		cs.position = Vector3(side.x * (edge + 1.0), wall_h / 2.0 - 10.0, side.y * (edge + 1.0))
		body.add_child(cs)
	add_child(body)
