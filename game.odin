// This file is compiled as part of the `odin.dll` file. It contains the
// procs that `game.exe` will call, such as:
//
// game_init: Sets up the game state
// game_update: Run once per frame
// game_shutdown: Shuts down game and frees memory
// game_memory: Run just before a hot reload, so game.exe has a pointer to the
//		game's memory.
// game_hot_reloaded: Run after a hot reload so that the `g_mem` global variable
//		can be set to whatever pointer it was in the old DLL.

package game

import "core:math/linalg"
import "core:fmt"
import rl "vendor:raylib"
import rg "vendor:raylib/rlgl"
import "core:math"

_ :: linalg
_ :: fmt

Box :: struct {
	size: Vec3,
	pos: Vec3,
}

Climb_Point :: struct {
	pos: Vec3,
	wanted_facing: Vec3,
}

Player_State_Default :: struct {}

Player_State_Climb_Start :: struct {
	point: Climb_Point,
	start: Vec3,
	start_pitch: f32,
	start_yaw: f32,
}

Player_State_Climb_Down :: struct {
	start: Vec3,
	end: Vec3,
}

Player_State_Climb_End :: struct {
	start_yaw: f32,
}

Player_State :: union #no_nil {
	Player_State_Default,
	Player_State_Climb_Start,
	Player_State_Climb_Down,
	Player_State_Climb_End,
}

Game_Memory :: struct {	
	player_pos: Vec3,
	player_vel: Vec3,
	player_state: Player_State,
	state_start: f64,
	time: f64,
	yaw: f32,
	pitch: f32,
	default_shader: rl.Shader,
	default_shader_instanced: rl.Shader,
	shadowcasting_shader: rl.Shader,
	shadowcasting_shader_instanced: rl.Shader,
	skybox_shader: rl.Shader,
	teapot: rl.Model,
	box: rl.Model,
	boxes: [dynamic]Box,
	mouse_captured: bool,
	player_grounded: bool,
	climb_points: [dynamic]Climb_Point,

	squirrel: rl.Texture2D,
	cat: rl.Texture2D,
	plane_mesh: rl.Mesh,
	plane: rl.Model,

	shadow_map: rl.RenderTexture2D,

	squirrel_mat: rl.Material,
	shadowcaster_mat_squirrel: rl.Material,

	default_mat: rl.Material,
	default_mat_instanced: rl.Material,
	shadowcasting_mat: rl.Material,
	shadowcasting_mat_instanced: rl.Material,

	cube: rl.Mesh,
}

g_mem: ^Game_Memory

PLAYER_SIZE :: Vec3 { 0.3, 1, 0.3 }

player_bounding_box :: proc() -> rl.BoundingBox {
	return {
		min = g_mem.player_pos - PLAYER_SIZE*0.5,
		max = g_mem.player_pos + PLAYER_SIZE*0.5,
	}
}

player_eye_pos :: proc() -> Vec3 {
	return g_mem.player_pos + {0, PLAYER_SIZE.y/4, 0}
}

dt: f32

update :: proc() {
	//light_pos = {200*f32(math.cos(rl.GetTime())), 200, -200*f32(math.sin(rl.GetTime()))}

	set_light(0, true, light_pos, { 1,1,1, 1 }, true)
	dt = min(rl.GetFrameTime(), 0.033)
	g_mem.time += f64(dt)

	switch &s in g_mem.player_state {
		case Player_State_Default:
			if rl.IsWindowFocused() {
				if rl.IsKeyPressed(.X) {
					if g_mem.mouse_captured {
						rl.EnableCursor()
						g_mem.mouse_captured = false
					} else {
						rl.DisableCursor()
						g_mem.mouse_captured = true
					}
				}

				movement: Vec3

				if rl.IsKeyDown(.W) {
					movement.z -= 1
				}

				if rl.IsKeyDown(.S) {
					movement.z += 1
				}

				if rl.IsKeyDown(.A) {
					movement.x -= 1
				}

				if rl.IsKeyDown(.D) {
					movement.x += 1
				}

				g_mem.yaw -= rl.GetMouseDelta().x * dt * 0.2
				g_mem.pitch -= rl.GetMouseDelta().y * dt * 0.2
				g_mem.pitch = clamp(g_mem.pitch, -0.24, 0.24)
				r := linalg.matrix4_rotate(g_mem.yaw * math.TAU, Vec3{0, 1, 0})
				g_mem.player_vel.xz = linalg.mul(r, vec4_point(movement)).xz * 3
			}

		case Player_State_Climb_Start:
			end_yaw := math.asin(s.point.wanted_facing.y)/math.TAU + 0.5
			t := f32(remap(g_mem.time, g_mem.state_start, g_mem.state_start + 1, 0, 1))
			g_mem.yaw = math.lerp(s.start_yaw, end_yaw, t)
			g_mem.pitch = math.lerp(s.start_pitch, 0, t)

			end_pos := s.start - s.point.wanted_facing

			g_mem.player_pos = math.lerp(s.start, end_pos, t)

			if t >= 1 {
				g_mem.player_state = Player_State_Climb_Down {
					start = g_mem.player_pos,
					end = g_mem.player_pos - {0, 4, 0},
				}
				g_mem.state_start = g_mem.time
			}

		case Player_State_Climb_Down:
			t := f32(remap(g_mem.time, g_mem.state_start, g_mem.state_start + 3, 0, 1))
			g_mem.player_pos = math.lerp(s.start, s.end, t)

			if t >= 1 {
				g_mem.player_state = Player_State_Climb_End {
					start_yaw = g_mem.yaw,
				}
				g_mem.state_start = g_mem.time
			}

		case Player_State_Climb_End:
			t := f32(remap(g_mem.time, g_mem.state_start, g_mem.state_start + 1, 0, 1))
			g_mem.yaw = math.lerp(s.start_yaw, s.start_yaw + 0.5, t)

			if t >= 1 {
				g_mem.player_state = Player_State_Default {}
			}
	}
	
	g_mem.player_vel.y -= dt * 9.82
	g_mem.player_pos.y += g_mem.player_vel.y * dt
	grounded := false

	for b in g_mem.boxes {
		bb := rl.BoundingBox {
			min = b.pos - b.size * 0.5,
			max = b.pos + b.size * 0.5,
		}

		if obb, coll := bounding_box_overlap(player_bounding_box(), bb); coll {
			sign: f32 = g_mem.player_pos.y + PLAYER_SIZE.y/2 < (b.pos.y + b.size.y / 2) ? -1 : 1
			g_mem.player_pos.y += (obb.max.y - obb.min.y) * sign
			g_mem.player_vel.y = 0
			grounded = true
		}
	}

	g_mem.player_pos.x += g_mem.player_vel.x * dt

	for b in g_mem.boxes {
		bb := rl.BoundingBox {
			min = b.pos - b.size * 0.5,
			max = b.pos + b.size * 0.5,
		}

		if obb, coll := bounding_box_overlap(player_bounding_box(), bb); coll {
			sign: f32 = g_mem.player_pos.x + PLAYER_SIZE.x/2 < (b.pos.x + b.size.x / 2) ? -1 : 1
			g_mem.player_pos.x += (obb.max.x - obb.min.x) * sign
			g_mem.player_vel.x = 0
		}
	}

	g_mem.player_pos.z += g_mem.player_vel.z * rl.GetFrameTime()

	for b in g_mem.boxes {
		bb := rl.BoundingBox {
			min = b.pos - b.size * 0.5,
			max = b.pos + b.size * 0.5,
		}

		if obb, coll := bounding_box_overlap(player_bounding_box(), bb); coll {
			sign: f32 = g_mem.player_pos.z + PLAYER_SIZE.z/2 < (b.pos.z + b.size.z / 2) ? -1 : 1
			g_mem.player_pos.z += (obb.max.z - obb.min.z) * sign
			g_mem.player_vel.z = 0
		}
	}

	if grounded {
		if rl.IsKeyPressed(.SPACE) {
			g_mem.player_vel.y = 5
		}
	}
}

draw_skybox :: proc() {
	rl.BeginShaderMode(g_mem.skybox_shader)
	s :: 1000
	c := rl.RED

	rg.PushMatrix()
		rg.Begin(rg.TRIANGLES)
			rg.Color4ub(c.r, c.g, c.b, c.a)

			// Front face
			rg.Normal3f(0, 0, -1)
			rg.Vertex3f(+s/2, -s/2, +s/2)
			rg.Vertex3f(-s/2, -s/2, +s/2)
			rg.Vertex3f(-s/2, +s/2, +s/2)
			rg.Vertex3f(-s/2, +s/2, +s/2)
			rg.Vertex3f(+s/2, +s/2, +s/2)
			rg.Vertex3f(+s/2, -s/2, +s/2)

			// Back
			rg.Normal3f(0, 0, 1)
			rg.Vertex3f(-s/2, -s/2, -s/2)
			rg.Vertex3f(+s/2, -s/2, -s/2)
			rg.Vertex3f(-s/2, +s/2, -s/2)
			rg.Vertex3f(+s/2, +s/2, -s/2)
			rg.Vertex3f(-s/2, +s/2, -s/2)
			rg.Vertex3f(+s/2, -s/2, -s/2)

			// Left
			rg.Normal3f(-1, 0, 0)
			rg.Vertex3f(+s/2, -s/2, -s/2)
			rg.Vertex3f(+s/2, -s/2, +s/2)
			rg.Vertex3f(+s/2, +s/2, -s/2)
			rg.Vertex3f(+s/2, +s/2, +s/2)
			rg.Vertex3f(+s/2, +s/2, -s/2)
			rg.Vertex3f(+s/2, -s/2, +s/2)

			// Right
			rg.Normal3f(1, 0, 0)
			rg.Vertex3f(-s/2, -s/2, +s/2)
			rg.Vertex3f(-s/2, -s/2, -s/2)
			rg.Vertex3f(-s/2, +s/2, -s/2)
			rg.Vertex3f(-s/2, +s/2, -s/2)
			rg.Vertex3f(-s/2, +s/2, +s/2)
			rg.Vertex3f(-s/2, -s/2, +s/2)

			// Bottom
			rg.Normal3f(0, 1, 0)
			rg.Vertex3f(-s/2, -s/2, -s/2)
			rg.Vertex3f(-s/2, -s/2, +s/2)
			rg.Vertex3f(+s/2, -s/2, -s/2)
			rg.Vertex3f(+s/2, -s/2, +s/2)
			rg.Vertex3f(+s/2, -s/2, -s/2)
			rg.Vertex3f(-s/2, -s/2, +s/2)

			// Top
			rg.Normal3f(0, -1, 0)
			rg.Vertex3f(-s/2, +s/2, +s/2)
			rg.Vertex3f(-s/2, +s/2, -s/2)
			rg.Vertex3f(+s/2, +s/2, -s/2)
			rg.Vertex3f(+s/2, +s/2, -s/2)
			rg.Vertex3f(+s/2, +s/2, +s/2)
			rg.Vertex3f(-s/2, +s/2, +s/2)
		rg.End()
	rg.PopMatrix()
	rl.EndShaderMode()
}

draw_world :: proc(shadowcaster: bool) {
	rl.DrawModelEx(g_mem.teapot, {0, -4.5, -14}, {0, 1, 0}, 90, {0.3, 0.3, 0.3}, rl.WHITE)

	{
		box_transforms := make([dynamic]rl.Matrix, context.temp_allocator)

		for b in g_mem.boxes {
			m: rl.Matrix = auto_cast (linalg.matrix4_translate(b.pos) * linalg.matrix4_scale(b.size))
			append(&box_transforms, m)
		}

		mat := shadowcaster ? g_mem.shadowcasting_mat_instanced : g_mem.default_mat_instanced

		rl.DrawMeshInstanced(g_mem.box.meshes[0], mat, raw_data(box_transforms), i32(len(box_transforms)))
	}

	draw_billboard :: proc(pos: Vec3, texture: rl.Texture2D,  shadowcaster: bool) {
		cam := game_camera()

		xz_cam_position := Vec3 {cam.position.x, 0, cam.position.z}
		
		cam_dir := linalg.normalize0(Vec3{pos.x, 0, pos.z} - xz_cam_position)
		forward := Vec3{0, 0, -1}
		yr := math.acos(linalg.dot(cam_dir, forward)) * math.sign(linalg.dot(cam_dir, Vec3{-1, 0, 0}))

		squirrel_transf := linalg.matrix4_translate(pos) * linalg.matrix4_rotate(yr, Vec3{0, 1, 0}) * linalg.matrix4_rotate(math.TAU/4, Vec3{1, 0, 0}) * linalg.matrix4_scale(Vec3{1, 0.01, 1})
		g_mem.squirrel_mat.maps[0].texture = texture
		g_mem.shadowcaster_mat_squirrel.maps[0].texture = texture
		rl.DrawMesh(g_mem.plane_mesh, shadowcaster ? g_mem.shadowcaster_mat_squirrel : g_mem.squirrel_mat, auto_cast squirrel_transf)
	}

	rg.DisableBackfaceCulling()
	draw_billboard({0, 0.43, -5}, g_mem.squirrel, shadowcaster)
	draw_billboard({2, 0.5, -5}, g_mem.cat, shadowcaster)
	rg.EnableBackfaceCulling()
}

draw :: proc() {
	rl.BeginDrawing()

	rl.BeginTextureMode(g_mem.shadow_map)
	rl.ClearBackground(rl.WHITE)

	lightCam := rl.Camera3D {
		position = light_pos + g_mem.player_pos,
		target = g_mem.player_pos,
		up = {0, 1, 0},
		fovy = 20,
		projection = .ORTHOGRAPHIC,
	}

	rl.BeginMode3D(lightCam)
	lightView := rg.GetMatrixModelview()
	lightProj := rg.GetMatrixProjection()
	draw_world(true)
	rl.EndMode3D()
	rl.EndTextureMode()

	lightVPLoc := rl.GetShaderLocation(g_mem.default_shader, "lightVP")
	lightViewProj := lightProj * lightView


	rl.SetShaderValueMatrix(g_mem.default_shader, lightVPLoc, lightViewProj)
	rl.SetShaderValueMatrix(g_mem.default_shader_instanced, lightVPLoc, lightViewProj)

	rl.ClearBackground(rl.BLACK)

	/*shadowMapLoc := rl.GetShaderLocation(g_mem.default_shader, "shadowMap")

	//rg.EnableTexture(g_mem.shadow_map.depth.id)

	slot := 1 // Can be anything 0 to 15, but 0 will probably be taken up
	rg.ActiveTextureSlot(1)
	rg.EnableTexture(g_mem.shadow_map.depth.id)
	rg.SetUniform(i32(shadowMapLoc), &slot, i32(rl.ShaderUniformDataType.INT), 1)*/

	/*shadowMapLoc := rl.GetShaderLocation(g_mem.default_shader, "shadowMap")
	rl.SetShaderValueTexture(g_mem.default_shader, shadowMapLoc, g_mem.shadow_map.depth)*/

//	rl.SetShaderValue(g_mem.default_shader, GetShaderLocation(g_mem.default_shader, "shadowMapResolution"), &shadowMapResolution, SHADER_UNIFORM_INT);

	cam := game_camera()
	rl.BeginMode3D(cam)
	//rl.BeginShaderMode(g_mem.default_shader)
	draw_skybox()

	rl.SetShaderValue(g_mem.default_shader, rl.ShaderLocationIndex(g_mem.default_shader.locs[rl.ShaderLocationIndex.VECTOR_VIEW]), raw_data(&g_mem.player_pos), .VEC3)

	draw_world(false)

	screen_mid := Vec2{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}*0.5
	r := rl.GetMouseRay(screen_mid, cam)

	crosshair_color := rl.GRAY
	for c in g_mem.climb_points {
		rl.DrawSphere(c.pos, 0.1, rl.RED)

		if coll := rl.GetRayCollisionSphere(r, c.pos, 0.1); coll.hit && coll.distance < 1.5 {
			crosshair_color = rl.GREEN

			if rl.IsKeyPressed(.E) && union_type(g_mem.player_state) == Player_State_Default {
				g_mem.player_state = Player_State_Climb_Start {
					point = c,
					start = g_mem.player_pos,
					start_pitch = g_mem.pitch,
					start_yaw = g_mem.yaw,
				}
				g_mem.state_start = g_mem.time
				break
			}
		}
	}

	//rl.DrawModelEx(g_mem.plane, {0, 0.5, -5}, {1, 0, 0}, 90, {1,1,1}, rl.WHITE)
	//rl.DrawBillboard(cam, g_mem.squirrel, {0, 0.5, -5}, 1, rl.WHITE)
		
	//rl.EndShaderMode()
	rl.EndMode3D()

	rl.DrawCircleV(screen_mid, 5, crosshair_color)

	//rl.DrawTextureEx(g_mem.shadow_map.depth, {}, 0, 0.2, rl.WHITE)

	rl.EndDrawing()
}

@(export)
game_update :: proc() -> bool {
	update()
	draw()
	return !rl.WindowShouldClose()
}

@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(1920, 1080, "Teapot Tycoon")
	rl.SetWindowPosition(200, 200)
	rl.SetTargetFPS(500)
}

camera_rot_matrix :: proc() -> Mat4 {
	camera_rot_x := linalg.matrix4_rotate(g_mem.pitch * math.TAU, Vec3{1, 0, 0})
	camera_rot_y := linalg.matrix4_rotate(g_mem.yaw * math.TAU, Vec3{0, 1, 0})
	return linalg.mul(camera_rot_y, camera_rot_x)
}

game_camera :: proc() -> rl.Camera {
	return {
		position = player_eye_pos(),
		target = player_eye_pos() + linalg.mul(camera_rot_matrix(), Vec4{0, 0, -1, 1}).xyz,
		up = {0, 1, 0},
		fovy = 90,
		projection = .PERSPECTIVE,
	}
}

check_collision_boxes :: proc(b1: rl.BoundingBox, b2: rl.BoundingBox) -> bool {
	collision := true

	if ((b1.max.x > b2.min.x) && (b1.min.x < b2.max.x))
	{
		if (b1.max.y <= b2.min.y) || (b1.min.y >= b2.max.y) {
			collision = false
		}

		if (b1.max.z <= b2.min.z) || (b1.min.z >= b2.max.z) {
			collision = false
		}
	} else {
		collision = false
	}

	return collision
}

// Check collision between two boxes
// NOTE: Boxes are defined by two points minimum and maximum
bounding_box_overlap :: proc(b1: rl.BoundingBox, b2: rl.BoundingBox) -> (res: rl.BoundingBox, collision: bool) {
	if check_collision_boxes(b1, b2) {
		res.min.x = max(b1.min.x, b2.min.x)
		res.max.x = min(b1.max.x, b2.max.x)
		res.min.y = max(b1.min.y, b2.min.y)
		res.max.y = min(b1.max.y, b2.max.y)
		res.min.z = max(b1.min.z, b2.min.z)
		res.max.z = min(b1.max.z, b2.max.z)
		collision = true
	}

	return
}

light_pos := Vec3{20, 20, -20}

@(export)
game_init :: proc() {
	g_mem = new(Game_Memory)

	g_mem^ = Game_Memory {
		player_pos = {2, 2, -3},
		default_shader = rl.LoadShader("default_lighting.vs", "default_lighting.fs"),
		default_shader_instanced = rl.LoadShader("default_lighting_instanced.vs", "default_lighting.fs"),
		shadowcasting_shader = rl.LoadShader("shadowcaster.vs", "shadowcaster.fs"),
		shadowcasting_shader_instanced = rl.LoadShader("shadowcaster_instanced.vs", "shadowcaster.fs"),
		skybox_shader = rl.LoadShader("skybox.vs", "skybox.fs"),
		teapot = rl.LoadModel("teapot.obj"),
		box = rl.LoadModel("box.obj"),
		squirrel = rl.LoadTexture("squirrel.png"),
		cat = rl.LoadTexture("cat.png"),
		plane_mesh = rl.GenMeshPlane(1, 1, 2, 2),
    	cube = rl.GenMeshCube(1, 1, 1),
    	shadow_map = create_shadowmap_rt(4096, 4096),
	}

	set_shader_location :: proc(s: ^rl.Shader, #any_int index: i32, name: cstring) {
		s.locs[index] = rl.GetShaderLocation(s^, name)
	}

	set_shader_attrib_location :: proc(s: ^rl.Shader, #any_int index: i32, name: cstring) {
		s.locs[index] = rl.GetShaderLocationAttrib(s^, name)
	}

	set_shader_location(&g_mem.default_shader, rl.ShaderLocationIndex.VECTOR_VIEW, "viewPos")
	set_shader_location(&g_mem.default_shader, rl.ShaderLocationIndex.MATRIX_MVP, "mvp")
	set_shader_location(&g_mem.default_shader, i32(rl.ShaderLocationIndex.MAP_ALBEDO) + 10, "shadowMap")

	set_shader_location(&g_mem.default_shader_instanced, rl.ShaderLocationIndex.VECTOR_VIEW, "viewPos")
	set_shader_location(&g_mem.default_shader_instanced, rl.ShaderLocationIndex.MATRIX_MVP, "mvp")
	set_shader_attrib_location(&g_mem.default_shader_instanced, rl.ShaderLocationIndex.MATRIX_MODEL, "instanceTransform")
	set_shader_location(&g_mem.default_shader_instanced, i32(rl.ShaderLocationIndex.MAP_ALBEDO) + 10, "shadowMap")

	set_shader_location(&g_mem.shadowcasting_shader, rl.ShaderLocationIndex.MATRIX_MVP, "mvp")

	set_shader_location(&g_mem.shadowcasting_shader_instanced, rl.ShaderLocationIndex.MATRIX_MVP, "mvp")
	set_shader_attrib_location(&g_mem.shadowcasting_shader_instanced, rl.ShaderLocationIndex.MATRIX_MODEL, "instanceTransform")

	g_mem.default_mat = rl.LoadMaterialDefault()
	g_mem.default_mat.shader = g_mem.default_shader
	g_mem.default_mat.maps[10].texture = g_mem.shadow_map.depth

	g_mem.default_mat_instanced = rl.LoadMaterialDefault()
	g_mem.default_mat_instanced.shader = g_mem.default_shader_instanced
	g_mem.default_mat_instanced.maps[10].texture = g_mem.shadow_map.depth

	g_mem.shadowcasting_mat = rl.LoadMaterialDefault()
	g_mem.shadowcasting_mat.shader = g_mem.shadowcasting_shader

	g_mem.shadowcasting_mat_instanced = rl.LoadMaterialDefault()
	g_mem.shadowcasting_mat_instanced.shader = g_mem.shadowcasting_shader_instanced

	g_mem.shadowcaster_mat_squirrel = rl.LoadMaterialDefault()
	g_mem.shadowcaster_mat_squirrel.shader = g_mem.default_shader
	g_mem.shadowcaster_mat_squirrel.maps[0].texture = g_mem.squirrel

	g_mem.squirrel_mat = rl.LoadMaterialDefault()
	g_mem.squirrel_mat.shader = g_mem.default_shader

	g_mem.plane = rl.LoadModelFromMesh(g_mem.plane_mesh)

	for midx in 0..<g_mem.plane.materialCount {
		g_mem.plane.materials[midx].shader = g_mem.default_shader
	}

	g_mem.squirrel_mat.maps[0].texture = g_mem.squirrel
	g_mem.squirrel_mat.maps[10].texture = g_mem.shadow_map.depth

	ambient := Vec4{ 0.2, 0.2, 0.3, 1.0}
	rl.SetShaderValue(g_mem.default_shader, rl.GetShaderLocation(g_mem.default_shader, "ambient"), raw_data(&ambient), .VEC4)

	rl.SetShaderValue(g_mem.default_shader_instanced, rl.GetShaderLocation(g_mem.default_shader_instanced, "ambient"), raw_data(&ambient), .VEC4)

	for midx in 0..<g_mem.teapot.materialCount {
		g_mem.teapot.materials[midx].shader = g_mem.default_shader
	}

	for midx in 0..<g_mem.box.materialCount {
		g_mem.box.materials[midx].shader = g_mem.default_shader
		g_mem.box.materials[midx].maps[10].texture = g_mem.shadow_map.depth
    	g_mem.box.materials[midx].maps[rl.MaterialMapIndex.ALBEDO].color = rl.RED
	}

	//set_light(1, true, {0, 3, -3}, { 1,1,1, 1 }, false)

	append(&g_mem.climb_points, Climb_Point {
		pos = {0,  0.2, -10},
		wanted_facing = {0, 0, 1},
	})

	append(&g_mem.boxes, Box{
		pos = {0, -5, 0},
		size = {5, 10, 20},
	})

	/*append(&g_mem.boxes, Box{
		pos = {0, 4, 0},
		size = {5, 1, 20},
	})*/

	append(&g_mem.boxes, Box{
		pos = {0, -5, -11},
		size = {2, 1, 10},
	})

	append(&g_mem.boxes, Box{
		pos = {0, 0, -3},
		size = {0.5, 5, 0.5},
	})

	game_hot_reloaded(g_mem)
}


create_shadowmap_rt :: proc(widthi, heighti: int) -> rl.RenderTexture2D {
	width := i32(widthi)
	height := i32(heighti)
	target: rl.RenderTexture2D

	target.id = rg.LoadFramebuffer(width, height) // Load an empty framebuffer
	target.texture.width = width
	target.texture.height = height

	if (target.id > 0)
	{
		rg.EnableFramebuffer(target.id)

		// Create depth texture
		// We don't need a color texture for the shadowmap
		target.depth.id = rg.LoadTextureDepth(width, height, false)
		target.depth.width = width
		target.depth.height = height
		target.depth.format = rl.PixelFormat(19)       //DEPTH_COMPONENT_24BIT?
		target.depth.mipmaps = 1

		// Attach depth texture to FBO
		rg.FramebufferAttach(target.id, target.depth.id, i32(rg.FramebufferAttachType.DEPTH), i32(rg.FramebufferAttachTextureType.TEXTURE2D), 0)

		// Check if fbo is complete with attachments (valid)
		if rg.FramebufferComplete(target.id) {
			fmt.printfln("FBO: [ID %v] Framebuffer object created successfully", target.id)
		}

		rg.DisableFramebuffer()
	} else {
		fmt.println("FBO: Framebuffer object can not be created")
	}

	return target
}

set_light :: proc(n: int, enabled: bool, pos: Vec3, color: Vec4, directional: bool) {
	enabled := int(enabled)
	type := directional ? 0 : 1
	pos := pos
	color := color
	rl.SetShaderValue(g_mem.default_shader, rl.GetShaderLocation(g_mem.default_shader, fmt.ctprintf("lights[%v].enabled", n)), &enabled, .INT)
	rl.SetShaderValue(g_mem.default_shader, rl.GetShaderLocation(g_mem.default_shader, fmt.ctprintf("lights[%v].type", n)), &type, .INT)
	rl.SetShaderValue(g_mem.default_shader, rl.GetShaderLocation(g_mem.default_shader, fmt.ctprintf("lights[%v].position", n)), raw_data(&pos), .VEC3)
	rl.SetShaderValue(g_mem.default_shader, rl.GetShaderLocation(g_mem.default_shader, fmt.ctprintf("lights[%v].color", n)), raw_data(&color), .VEC4)

	rl.SetShaderValue(g_mem.default_shader_instanced, rl.GetShaderLocation(g_mem.default_shader_instanced, fmt.ctprintf("lights[%v].enabled", n)), &enabled, .INT)
	rl.SetShaderValue(g_mem.default_shader_instanced, rl.GetShaderLocation(g_mem.default_shader_instanced, fmt.ctprintf("lights[%v].type", n)), &type, .INT)
	rl.SetShaderValue(g_mem.default_shader_instanced, rl.GetShaderLocation(g_mem.default_shader_instanced, fmt.ctprintf("lights[%v].position", n)), raw_data(&pos), .VEC3)
	rl.SetShaderValue(g_mem.default_shader_instanced, rl.GetShaderLocation(g_mem.default_shader_instanced, fmt.ctprintf("lights[%v].color", n)), raw_data(&color), .VEC4)
}

@(export)
game_shutdown :: proc() { 
	rl.EnableCursor()
	delete(g_mem.boxes)
	delete(g_mem.climb_points)
	free(g_mem)
}

@(export)
game_shutdown_window :: proc() {
	rl.CloseWindow()
}

@(export)
game_memory :: proc() -> rawptr {
	return g_mem
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g_mem = (^Game_Memory)(mem)
}

@(export)
game_force_reload :: proc() -> bool {
	return rl.IsKeyPressed(.F5)
}

@(export)
game_force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.F6)
}