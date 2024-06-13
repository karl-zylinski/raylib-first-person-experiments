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

	atlas: rl.Texture2D,
	plane_mesh: rl.Mesh,
	plane: rl.Model,

	shadow_map: rl.RenderTexture2D,

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
	/*fmt.println("albedo", i32(rg.ShaderLocationIndex.MAP_ALBEDO))
	fmt.println("diffuse", i32(rg.ShaderLocationIndex.MAP_))
	fmt.println("metalness", i32(rg.ShaderLocationIndex.MAP_METALNESS))*/

	//light_pos = {200*f32(math.cos(rl.GetTime())), 200, -200*f32(math.sin(rl.GetTime()))}

	set_light(0, true, light_pos, { 1,1,1,1 }, true)
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
		m := rl.MatrixToFloatV(auto_cast linalg.matrix4_translate(g_mem.player_pos))
	 	rg.MultMatrixf(&m[0])
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
	//rl.DrawModelEx(g_mem.teapot, {0, -4.5, -14}, {0, 1, 0}, 90, {0.3, 0.3, 0.3}, rl.WHITE)

	{
		box_transforms := make([dynamic]rl.Matrix, context.temp_allocator)
		npc_rects := make([dynamic]Rect, context.temp_allocator)

		for b in g_mem.boxes {
			m: rl.Matrix = auto_cast (linalg.matrix4_translate(b.pos) * linalg.matrix4_scale(b.size))
			append(&box_transforms, m)
			append(&npc_rects, Rect {})
		}

		mat := shadowcaster ? g_mem.shadowcasting_mat_instanced : g_mem.default_mat_instanced

		draw_mesh_instanced(g_mem.box.meshes[0], mat, box_transforms[:], npc_rects[:])
		//rl.DrawMeshInstanced(g_mem.box.meshes[0], mat, raw_data(box_transforms), i32(len(box_transforms)))
	}

	rl.DrawSphere({0, 1, 0}, 0.1, rl.GREEN)

/*	draw_billboard :: proc(pos: Vec3, texture: rl.Texture2D,  shadowcaster: bool) {
		cam := game_camera()

		xz_cam_position := Vec3 {cam.position.x, 0, cam.position.z}
		
		cam_dir := linalg.normalize0(Vec3{pos.x, 0, pos.z} - xz_cam_position)
		forward := Vec3{0, 0, -1}
		yr := math.acos(linalg.dot(cam_dir, forward)) * math.sign(linalg.dot(cam_dir, Vec3{-1, 0, 0}))

		squirrel_transf := linalg.matrix4_translate(pos) * linalg.matrix4_rotate(yr, Vec3{0, 1, 0}) * linalg.matrix4_rotate(math.TAU/4, Vec3{1, 0, 0}) * linalg.matrix4_scale(Vec3{1, 0.01, 1})
		g_mem.squirrel_mat.maps[0].texture = texture
		g_mem.shadowcaster_mat_squirrel.maps[0].texture = texture
		rl.DrawMesh(g_mem.plane_mesh, shadowcaster ? g_mem.shadowcaster_mat_squirrel : g_mem.squirrel_mat, auto_cast squirrel_transf)
	}*/

	rg.DisableBackfaceCulling()
	{
		npc_transforms := make([dynamic]rl.Matrix, context.temp_allocator)
		npc_rects := make([dynamic]Rect, context.temp_allocator)

		get_npc_transform :: proc(pos: Vec3) -> rl.Matrix {
			cam := game_camera()

			xz_cam_position := Vec3 {cam.position.x, 0, cam.position.z}
			
			cam_dir := linalg.normalize0(Vec3{pos.x, 0, pos.z} - xz_cam_position)
			forward := Vec3{0, 0, -1}
			yr := math.acos(linalg.dot(cam_dir, forward)) * math.sign(linalg.dot(cam_dir, Vec3{-1, 0, 0}))

			return auto_cast(linalg.matrix4_translate(pos) * linalg.matrix4_rotate(yr, Vec3{0, 1, 0}) * linalg.matrix4_rotate(math.TAU/4, Vec3{1, 0, 0}) * linalg.matrix4_scale(Vec3{1, 0.01, 1}))
		}

		append(&npc_transforms, get_npc_transform({0, 0.43, -5}))
		append(&npc_rects, atlas_textures[.Squirrel].rect)
		append(&npc_transforms, get_npc_transform({2, 0.5, -5}))
		append(&npc_rects, atlas_textures[.Cat].rect)

		mat := shadowcaster ? g_mem.shadowcasting_mat_instanced : g_mem.default_mat_instanced

		draw_mesh_instanced(g_mem.plane_mesh, mat, npc_transforms[:], npc_rects[:])
	}
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


	//set_light(1, true, {0, 1, f32(math.cos(rl.GetTime()))*10 }, { 1,1,1, 1 }, false)

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

SHADER_LOCATION_UVS :: len(rg.ShaderLocationIndex)

// Draw multiple mesh instances with material and different transforms
draw_mesh_instanced :: proc(mesh: rl.Mesh, material: rl.Material, transforms: []rl.Matrix, uv_rects: []Rect) {
    // Bind shader program
    rg.EnableShader(material.shader.id)

    // Send required data to shader (matrices, values)
    //-----------------------------------------------------
    // Upload to shader material.colDiffuse
    if material.shader.locs[rg.ShaderLocationIndex.COLOR_DIFFUSE] != -1 {
        values := [4]f32 {
            f32(material.maps[rl.MaterialMapIndex.ALBEDO].color.r)/255,
            f32(material.maps[rl.MaterialMapIndex.ALBEDO].color.g)/255,
            f32(material.maps[rl.MaterialMapIndex.ALBEDO].color.b)/255,
            f32(material.maps[rl.MaterialMapIndex.ALBEDO].color.a)/255,
        }

        rg.SetUniform(material.shader.locs[rg.ShaderLocationIndex.COLOR_DIFFUSE], raw_data(&values), i32(rg.ShaderUniformDataType.VEC4), 1)
    }

    // Upload to shader material.colSpecular (if location available)
    if material.shader.locs[rg.ShaderLocationIndex.COLOR_SPECULAR] != -1 {
        values := [4]f32 {
            f32(material.maps[rl.ShaderLocationIndex.COLOR_SPECULAR].color.r)/255,
            f32(material.maps[rl.ShaderLocationIndex.COLOR_SPECULAR].color.g)/255,
            f32(material.maps[rl.ShaderLocationIndex.COLOR_SPECULAR].color.b)/255,
            f32(material.maps[rl.ShaderLocationIndex.COLOR_SPECULAR].color.a)/255,
        }

        rg.SetUniform(material.shader.locs[rg.ShaderLocationIndex.COLOR_SPECULAR], raw_data(&values), i32(rl.ShaderUniformDataType.VEC4), 1)
    }

    // Get a copy of current matrices to work with,
    // just in case stereo render is required, and we need to modify them
    // NOTE: At this point the modelview matrix just contains the view matrix (camera)
    // That's because BeginMode3D() sets it and there is no model-drawing function
    // that modifies it, all use rlPushMatrix() and rlPopMatrix()
    matView := rg.GetMatrixModelview()
    matModelView := rl.Matrix(1)
    matProjection := rg.GetMatrixProjection()

    // Upload view and projection matrices (if locations available)
    if (material.shader.locs[rg.ShaderLocationIndex.MATRIX_VIEW] != -1) {
    	rg.SetUniformMatrix(material.shader.locs[rg.ShaderLocationIndex.MATRIX_VIEW], matView)
    }

    if (material.shader.locs[rg.ShaderLocationIndex.MATRIX_PROJECTION] != -1) {
    	rg.SetUniformMatrix(material.shader.locs[rg.ShaderLocationIndex.MATRIX_PROJECTION], matProjection)
    }

    assert(len(transforms) == len(uv_rects))
    // Create instances buffer
    instanceTransforms := make([][16]f32, len(transforms), context.temp_allocator)
    instanceUVRemaps := make([][4]f32, len(uv_rects), context.temp_allocator)

    // Fill buffer with instances transformations as float16 arrays
    for t, i in transforms {
    	instanceTransforms[i] = rl.MatrixToFloatV(t)
    }

    for r, i in uv_rects {
    	if r == {} {
    		instanceUVRemaps[i] = {-1, -1, -1, -1}
    		continue
    	}

    	v := [4]f32 {
    		r.x/f32(g_mem.atlas.width),
    		(r.x + r.width)/f32(g_mem.atlas.width),
    		r.y/f32(g_mem.atlas.height),
    		(r.y + r.height)/f32(g_mem.atlas.height),
    	}

    	instanceUVRemaps[i] = v
    }


    // Enable mesh VAO to attach new buffer
    rg.EnableVertexArray(mesh.vaoId)

    // This could alternatively use a static VBO and either glMapBuffer() or glBufferSubData().
    // It isn't clear which would be reliably faster in all cases and on all platforms,
    // anecdotally glMapBuffer() seems very slow (syncs) while glBufferSubData() seems
    // no faster, since we're transferring all the transform matrices anyway
    instancesVboId := rg.LoadVertexBuffer(raw_data(instanceTransforms), i32(len(transforms)*size_of([16]f32)), false)

    // Instances transformation matrices are send to shader attribute location: SHADER_LOC_MATRIX_MODEL
    for ii in 0..<4 {
    	i := u32(ii)
        rg.EnableVertexAttribute(u32(material.shader.locs[rg.ShaderLocationIndex.MATRIX_MODEL]) + i)
        rg.SetVertexAttribute(u32(material.shader.locs[rg.ShaderLocationIndex.MATRIX_MODEL]) + i, 4, rg.FLOAT, false, size_of(rl.Matrix), transmute(rawptr)(uintptr(i*size_of([4]f32))))
        rg.SetVertexAttributeDivisor(u32(material.shader.locs[rg.ShaderLocationIndex.MATRIX_MODEL]) + i, 1)
    }
    //rg.DisableVertexBuffer()

   	uvRemapsVboId := rg.LoadVertexBuffer(raw_data(instanceUVRemaps), i32(len(uv_rects)*size_of([4]f32)), false)
    rg.EnableVertexAttribute(u32(material.shader.locs[SHADER_LOCATION_UVS]))
    rg.SetVertexAttribute(u32(material.shader.locs[SHADER_LOCATION_UVS]), 4, rg.FLOAT, false, size_of([4]f32), nil)
    rg.SetVertexAttributeDivisor(u32(material.shader.locs[SHADER_LOCATION_UVS]), 1)

    rg.DisableVertexBuffer()
    rg.DisableVertexArray()

    // Accumulate internal matrix transform (push/pop) and view matrix
    // NOTE: In this case, model instance transformation must be computed in the shader
    matModelView = matView * rg.GetMatrixTransform()//rl.MatrixMultiply(rg.GetMatrixTransform(), matView)

    // Upload model normal matrix (if locations available)
    if (material.shader.locs[rg.ShaderLocationIndex.MATRIX_NORMAL] != -1) {
    	rg.SetUniformMatrix(material.shader.locs[rg.ShaderLocationIndex.MATRIX_NORMAL], rl.MatrixTranspose(rl.MatrixInvert(rg.GetMatrixTransform())))
    }

    //-----------------------------------------------------

    // Bind active texture maps (if available)
    
    // copied from rconfig.h
    MAX_MATERIAL_MAPS :: 12

    for ii in 0..<MAX_MATERIAL_MAPS {
    	i := i32(ii)
    	mi := rl.MaterialMapIndex(i)
        if (material.maps[i].texture.id > 0) {
            // Select current shader texture slot
            rg.ActiveTextureSlot(i)

            // Enable texture for active slot
            if mi == rl.MaterialMapIndex.IRRADIANCE || mi == rl.MaterialMapIndex.PREFILTER || mi == rl.MaterialMapIndex.CUBEMAP {
            	rg.EnableTextureCubemap(material.maps[i].texture.id)
            } else {
            	rg.EnableTexture(material.maps[i].texture.id)
            }

            rg.SetUniform(material.shader.locs[i32(rg.ShaderLocationIndex.MAP_ALBEDO) + i], &i, i32(rg.ShaderUniformDataType.INT), 1)
        }
    }

    rg.EnableVertexArray(mesh.vaoId)

    /*// Try binding vertex array objects (VAO)
    // or use VBOs if not possible
    if (!rg.EnableVertexArray(mesh.vaoId))
    {
        // Bind mesh VBO data: vertex position (shader-location = 0)
        rg.EnableVertexBuffer(mesh.vboId[0])
        rg.SetVertexAttribute(u32(material.shader.locs[rg.ShaderLocationIndex.VERTEX_POSITION]), 3, rg.FLOAT, false, 0, nil)
        rg.EnableVertexAttribute(u32(material.shader.locs[rg.ShaderLocationIndex.VERTEX_POSITION]))

        // Bind mesh VBO data: vertex texcoords (shader-location = 1)
        rg.EnableVertexBuffer(mesh.vboId[1])
        rg.SetVertexAttribute(u32(material.shader.locs[rg.ShaderLocationIndex.VERTEX_TEXCOORD01]), 2, rg.FLOAT, false, 0, nil)
        rg.EnableVertexAttribute(u32(material.shader.locs[rg.ShaderLocationIndex.VERTEX_TEXCOORD01]))

        if (material.shader.locs[rg.ShaderLocationIndex.VERTEX_NORMAL] != -1)
        {
            // Bind mesh VBO data: vertex normals (shader-location = 2)
            rg.EnableVertexBuffer(mesh.vboId[2])
            rg.SetVertexAttribute(material.shader.locs[rg.ShaderLocationIndex.VERTEX_NORMAL], 3, RL_FLOAT, 0, 0, 0)
            rg.EnableVertexAttribute(material.shader.locs[rg.ShaderLocationIndex.VERTEX_NORMAL])
        }

        // Bind mesh VBO data: vertex colors (shader-location = 3, if available)
        if (material.shader.locs[SHADER_LOC_VERTEX_COLOR] != -1)
        {
            if (mesh.vboId[3] != 0)
            {
                rg.EnableVertexBuffer(mesh.vboId[3])
                rg.SetVertexAttribute(material.shader.locs[SHADER_LOC_VERTEX_COLOR], 4, RL_UNSIGNED_BYTE, 1, 0, 0)
                rg.EnableVertexAttribute(material.shader.locs[SHADER_LOC_VERTEX_COLOR])
            }
            else
            {
                // Set default value for unused attribute
                // NOTE: Required when using default shader and no VAO support
                value := [4]f32 { 1, 1, 1, 1 }
                rg.SetVertexAttributeDefault(material.shader.locs[SHADER_LOC_VERTEX_COLOR], value, SHADER_ATTRIB_VEC4, 4)
                rg.DisableVertexAttribute(material.shader.locs[SHADER_LOC_VERTEX_COLOR])
            }
        }

        // Bind mesh VBO data: vertex tangents (shader-location = 4, if available)
        if (material.shader.locs[SHADER_LOC_VERTEX_TANGENT] != -1)
        {
            rg.EnableVertexBuffer(mesh.vboId[4])
            rg.SetVertexAttribute(material.shader.locs[SHADER_LOC_VERTEX_TANGENT], 4, RL_FLOAT, 0, 0, 0)
            rg.EnableVertexAttribute(material.shader.locs[SHADER_LOC_VERTEX_TANGENT])
        }

        // Bind mesh VBO data: vertex texcoords2 (shader-location = 5, if available)
        if (material.shader.locs[SHADER_LOC_VERTEX_TEXCOORD02] != -1)
        {
            rg.EnableVertexBuffer(mesh.vboId[5])
            rg.SetVertexAttribute(material.shader.locs[SHADER_LOC_VERTEX_TEXCOORD02], 2, RL_FLOAT, 0, 0, 0)
            rg.EnableVertexAttribute(material.shader.locs[SHADER_LOC_VERTEX_TEXCOORD02])
        }

        if (mesh.indices != NULL) {
        	rg.EnableVertexBufferElement(mesh.vboId[6])
        }
    }

    // WARNING: Disable vertex attribute color input if mesh can not provide that data (despite location being enabled in shader)
    if mesh.vboId[3] == 0 {
    	rg.DisableVertexAttribute(u32(material.shader.locs[rg.ShaderLocationIndex.VERTEX_COLOR]))
    }*/

    {
        // Calculate model-view-projection matrix (MVP)
        matModelViewProjection := matProjection * matModelView// rl.MatrixMultiply(matModelView, matProjection)

        // Send combined model-view-projection matrix to shader
        rg.SetUniformMatrix(material.shader.locs[rl.ShaderLocationIndex.MATRIX_MVP], matModelViewProjection)

        // Draw mesh instanced
        if (mesh.indices != nil) {
        	rg.DrawVertexArrayElementsInstanced(0, mesh.triangleCount*3, nil, i32(len(transforms)))
        } else {
        	rg.DrawVertexArrayInstanced(0, mesh.vertexCount, i32(len(transforms)))
        }
    }

    // Unbind all bound texture maps
    for ii in 0..<MAX_MATERIAL_MAPS {
    	i := i32(ii)
    	mi := rl.MaterialMapIndex(i)
        if (material.maps[i].texture.id > 0)
        {
            // Select current shader texture slot
            rg.ActiveTextureSlot(i)

            // Disable texture for active slot
            if ((mi == rl.MaterialMapIndex.IRRADIANCE) || (mi == rl.MaterialMapIndex.PREFILTER) || (mi == rl.MaterialMapIndex.CUBEMAP)) {
            	rg.DisableTextureCubemap()
            } else {
            	rg.DisableTexture()
            }
        }
    }

    // Disable all possible vertex array objects (or VBOs)
   	rg.DisableVertexArray()
   	rg.DisableVertexBuffer()
   	rg.DisableVertexBufferElement()

    // Disable shader program
   	rg.DisableShader()

    // Remove instance transforms buffer
    rg.UnloadVertexBuffer(instancesVboId)
    rg.UnloadVertexBuffer(uvRemapsVboId)
    
}


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
		atlas = rl.LoadTexture("atlas.png"),
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

	set_shader_location(&g_mem.default_shader, rl.ShaderLocationIndex.MATRIX_VIEW, "matView")
	set_shader_location(&g_mem.default_shader, rl.ShaderLocationIndex.VECTOR_VIEW, "viewPos")
	set_shader_location(&g_mem.default_shader, i32(rl.ShaderLocationIndex.MAP_ALBEDO) + 10, "shadowMap")

	set_shader_location(&g_mem.default_shader_instanced, rl.ShaderLocationIndex.VECTOR_VIEW, "viewPos")
	set_shader_location(&g_mem.default_shader_instanced, rl.ShaderLocationIndex.MATRIX_VIEW, "matView")
	set_shader_attrib_location(&g_mem.default_shader_instanced, rg.ShaderLocationIndex.MATRIX_MODEL, "instanceTransform")
	set_shader_attrib_location(&g_mem.default_shader_instanced, SHADER_LOCATION_UVS, "instanceUVRemap")
	set_shader_location(&g_mem.default_shader_instanced, i32(rl.ShaderLocationIndex.MAP_ALBEDO) + 10, "shadowMap")

	set_shader_attrib_location(&g_mem.shadowcasting_shader_instanced, SHADER_LOCATION_UVS, "instanceUVRemap")
	set_shader_attrib_location(&g_mem.shadowcasting_shader_instanced, rg.ShaderLocationIndex.MATRIX_MODEL, "instanceTransform")

	g_mem.default_mat = rl.LoadMaterialDefault()
	g_mem.default_mat.shader = g_mem.default_shader
	g_mem.default_mat.maps[0].texture = g_mem.atlas
	g_mem.default_mat.maps[10].texture = g_mem.shadow_map.depth

	g_mem.default_mat_instanced = rl.LoadMaterialDefault()
	g_mem.default_mat_instanced.shader = g_mem.default_shader_instanced
	g_mem.default_mat_instanced.maps[0].texture = g_mem.atlas
	g_mem.default_mat_instanced.maps[10].texture = g_mem.shadow_map.depth

	g_mem.shadowcasting_mat = rl.LoadMaterialDefault()
	g_mem.shadowcasting_mat.shader = g_mem.shadowcasting_shader

	g_mem.shadowcasting_mat_instanced = rl.LoadMaterialDefault()
	g_mem.shadowcasting_mat_instanced.maps[0].texture = g_mem.atlas
	g_mem.shadowcasting_mat_instanced.shader = g_mem.shadowcasting_shader_instanced

	g_mem.plane = rl.LoadModelFromMesh(g_mem.plane_mesh)

	for midx in 0..<g_mem.plane.materialCount {
		g_mem.plane.materials[midx].shader = g_mem.default_shader
	}


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

	//set_light(1, true, {0, 1, 0}, { 1,1,1, 1 }, false)

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