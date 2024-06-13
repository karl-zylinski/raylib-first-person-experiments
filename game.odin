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

Player :: struct {
	pos: Vec3,
	vel: Vec3,
	state: Player_State,
	state_start: f64,

	yaw: f32,
	pitch: f32,
}

Game_Memory :: struct {
	player: Player,
	time: f64,
	default_shader: rl.Shader,
	default_shader_instanced: rl.Shader,
	shadowcasting_shader: rl.Shader,
	shadowcasting_shader_instanced: rl.Shader,
	skybox_shader: rl.Shader,
	boxes: [dynamic]Box,
	mouse_captured: bool,
	climb_points: [dynamic]Climb_Point,

	atlas: rl.Texture2D,
	plane_mesh: rl.Mesh,
	box_mesh: rl.Mesh,

	shadow_map: rl.RenderTexture2D,

	default_mat: rl.Material,
	default_mat_instanced: rl.Material,
	shadowcasting_mat: rl.Material,
	shadowcasting_mat_instanced: rl.Material,

	debug_draw: bool,
}

g_mem: ^Game_Memory

PLAYER_SIZE :: Vec3 { 0.3, 1, 0.3 }

player_bounding_box :: proc() -> rl.BoundingBox {
	return {
		min = g_mem.player.pos - PLAYER_SIZE*0.5,
		max = g_mem.player.pos + PLAYER_SIZE*0.5,
	}
}

player_eye_pos :: proc() -> Vec3 {
	return g_mem.player.pos + {0, PLAYER_SIZE.y/4, 0}
}

dt: f32

update :: proc() {
	// Rotate light
	// light_pos = {20*f32(math.cos(rl.GetTime())), 20, -20*f32(math.sin(rl.GetTime()))}
	set_light(0, true, light_pos, { 1, 1, 1, 1 }, true)
	dt = min(rl.GetFrameTime(), 0.033)
	g_mem.time += f64(dt)

	p := &g_mem.player
	switch &s in p.state {
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

				p.yaw -= rl.GetMouseDelta().x * dt * 0.2
				p.pitch -= rl.GetMouseDelta().y * dt * 0.2
				p.pitch = clamp(p.pitch, -0.24, 0.24)
				r := linalg.matrix4_rotate(p.yaw * math.TAU, Vec3{0, 1, 0})
				p.vel.xz = linalg.mul(r, vec4_point(movement)).xz * 3
			}

		case Player_State_Climb_Start:
			end_yaw := math.asin(s.point.wanted_facing.y)/math.TAU + 0.5
			t := f32(remap(g_mem.time, p.state_start, p.state_start + 1, 0, 1))
			p.yaw = math.lerp(s.start_yaw, end_yaw, t)
			p.pitch = math.lerp(s.start_pitch, 0, t)

			end_pos := s.start - s.point.wanted_facing

			p.pos = math.lerp(s.start, end_pos, t)

			if t >= 1 {
				p.state = Player_State_Climb_Down {
					start = p.pos,
					end = p.pos - {0, 4, 0},
				}
				p.state_start = g_mem.time
			}

		case Player_State_Climb_Down:
			t := f32(remap(g_mem.time, p.state_start, p.state_start + 3, 0, 1))
			p.pos = math.lerp(s.start, s.end, t)

			if t >= 1 {
				p.state = Player_State_Climb_End {
					start_yaw = p.yaw,
				}
				p.state_start = g_mem.time
			}

		case Player_State_Climb_End:
			t := f32(remap(g_mem.time, p.state_start, p.state_start + 1, 0, 1))
			p.yaw = math.lerp(s.start_yaw, s.start_yaw + 0.5, t)

			if t >= 1 {
				p.state = Player_State_Default {}
			}
	}
	
	p.vel.y -= dt * 9.82
	p.pos.y += p.vel.y * dt
	grounded := false

	for b in g_mem.boxes {
		bb := rl.BoundingBox {
			min = b.pos - b.size * 0.5,
			max = b.pos + b.size * 0.5,
		}

		if obb, coll := bounding_box_overlap(player_bounding_box(), bb); coll {
			sign: f32 = p.pos.y + PLAYER_SIZE.y/2 < (b.pos.y + b.size.y / 2) ? -1 : 1
			p.pos.y += (obb.max.y - obb.min.y) * sign
			p.vel.y = 0
			grounded = true
		}
	}

	p.pos.x += p.vel.x * dt

	for b in g_mem.boxes {
		bb := rl.BoundingBox {
			min = b.pos - b.size * 0.5,
			max = b.pos + b.size * 0.5,
		}

		if obb, coll := bounding_box_overlap(player_bounding_box(), bb); coll {
			sign: f32 = p.pos.x + PLAYER_SIZE.x/2 < (b.pos.x + b.size.x / 2) ? -1 : 1
			p.pos.x += (obb.max.x - obb.min.x) * sign
			p.vel.x = 0
		}
	}

	p.pos.z += p.vel.z * rl.GetFrameTime()

	for b in g_mem.boxes {
		bb := rl.BoundingBox {
			min = b.pos - b.size * 0.5,
			max = b.pos + b.size * 0.5,
		}

		if obb, coll := bounding_box_overlap(player_bounding_box(), bb); coll {
			sign: f32 = p.pos.z + PLAYER_SIZE.z/2 < (b.pos.z + b.size.z / 2) ? -1 : 1
			p.pos.z += (obb.max.z - obb.min.z) * sign
			p.vel.z = 0
		}
	}

	if grounded {
		if rl.IsKeyPressed(.SPACE) {
			p.vel.y = 5
		}
	}
}

draw_skybox :: proc() {
	rl.BeginShaderMode(g_mem.skybox_shader)
	s :: 1000
	c := rl.RED

	rg.PushMatrix()
	m := rl.MatrixToFloatV(auto_cast linalg.matrix4_translate(g_mem.player.pos))
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
	// boxes
	{
		box_transforms := make([dynamic]rl.Matrix, context.temp_allocator)
		atlas_rects := make([dynamic]Rect, context.temp_allocator)

		for b in g_mem.boxes {
			m: rl.Matrix = auto_cast (linalg.matrix4_translate(b.pos) * linalg.matrix4_scale(b.size))
			append(&box_transforms, m)
			append(&atlas_rects, Rect {})
		}

		mat := shadowcaster ? g_mem.shadowcasting_mat_instanced : g_mem.default_mat_instanced
		draw_mesh_instanced(g_mem.box_mesh, mat, box_transforms[:], atlas_rects[:])
	}

	rl.DrawSphere({0, 1, 0}, 0.1, rl.GREEN)

	if shadowcaster {
		rg.DisableBackfaceCulling()
	}

	// "npcs"
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

	if shadowcaster {
		rg.EnableBackfaceCulling()
	}
}

draw :: proc() {
	rl.BeginDrawing()

	// Draw into shadowmap

	rl.BeginTextureMode(g_mem.shadow_map)
	rl.ClearBackground(rl.WHITE)

	light_cam := rl.Camera3D {
		position = light_pos + g_mem.player.pos,
		target = g_mem.player.pos,
		up = {0, 1, 0},
		fovy = 20,
		projection = .ORTHOGRAPHIC,
	}

	rl.BeginMode3D(light_cam)
	light_view := rg.GetMatrixModelview()
	light_proj := rg.GetMatrixProjection()
	draw_world(true)
	rl.EndMode3D()
	rl.EndTextureMode()

	// Shadowmap done. Draw normally and use shadows!

	light_vp_loc := rl.GetShaderLocation(g_mem.default_shader, "lightVP")
	light_view_proj := light_proj * light_view

	rl.SetShaderValueMatrix(g_mem.default_shader, light_vp_loc, light_view_proj)
	rl.SetShaderValueMatrix(g_mem.default_shader_instanced, light_vp_loc, light_view_proj)

	rl.ClearBackground(rl.BLACK)

	cam := game_camera()
	rl.BeginMode3D(cam)
	draw_skybox()

	rl.SetShaderValue(g_mem.default_shader, rl.ShaderLocationIndex(g_mem.default_shader.locs[rl.ShaderLocationIndex.VECTOR_VIEW]), raw_data(&g_mem.player.pos), .VEC3)
	rl.SetShaderValue(g_mem.default_shader_instanced, rl.ShaderLocationIndex(g_mem.default_shader_instanced.locs[rl.ShaderLocationIndex.VECTOR_VIEW]), raw_data(&g_mem.player.pos), .VEC3)

	draw_world(false)

	screen_mid := Vec2{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}*0.5
	r := rl.GetMouseRay(screen_mid, cam)

	crosshair_color := rl.GRAY
	for c in g_mem.climb_points {
		rl.DrawSphere(c.pos, 0.1, rl.RED)

		if coll := rl.GetRayCollisionSphere(r, c.pos, 0.1); coll.hit && coll.distance < 1.5 {
			crosshair_color = rl.GREEN

			if rl.IsKeyPressed(.E) && union_type(g_mem.player.state) == Player_State_Default {
				g_mem.player.state = Player_State_Climb_Start {
					point = c,
					start = g_mem.player.pos,
					start_pitch = g_mem.player.pitch,
					start_yaw = g_mem.player.yaw,
				}
				g_mem.player.state_start = g_mem.time
				break
			}
		}
	}
		
	rl.EndMode3D()

	rl.DrawCircleV(screen_mid, 5, crosshair_color)

	if g_mem.debug_draw {
		rl.DrawTextureEx(g_mem.shadow_map.depth, {}, 0, 0.1, rl.WHITE)
	}

	rl.EndDrawing()
}

@(export)
game_update :: proc() -> bool {
	if rl.IsKeyPressed(.F3) {
		g_mem.debug_draw = !g_mem.debug_draw
	}

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
	camera_rot_x := linalg.matrix4_rotate(g_mem.player.pitch * math.TAU, Vec3{1, 0, 0})
	camera_rot_y := linalg.matrix4_rotate(g_mem.player.yaw * math.TAU, Vec3{0, 1, 0})
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

	if (b1.max.x > b2.min.x) && (b1.min.x < b2.max.x) {
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

draw_mesh_instanced :: proc(mesh: rl.Mesh, material: rl.Material, transforms: []rl.Matrix, atlas_rects: []Rect) {
	rg.EnableShader(material.shader.id)

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

	// Populate uniform matrices
	mat_view := rg.GetMatrixModelview()
	mat_projection := rg.GetMatrixProjection()

	if material.shader.locs[rg.ShaderLocationIndex.MATRIX_VIEW] != -1 {
		rg.SetUniformMatrix(material.shader.locs[rg.ShaderLocationIndex.MATRIX_VIEW], mat_view)
	}

	if material.shader.locs[rg.ShaderLocationIndex.MATRIX_PROJECTION] != -1 {
		rg.SetUniformMatrix(material.shader.locs[rg.ShaderLocationIndex.MATRIX_PROJECTION], mat_projection)
	}

	assert(len(transforms) == len(atlas_rects))

	// Create instance buffers
	instance_transforms := make([][16]f32, len(transforms), context.temp_allocator)
	instance_uv_remaps := make([][4]f32, len(atlas_rects), context.temp_allocator)

	for t, i in transforms {
		instance_transforms[i] = rl.MatrixToFloatV(t)
	}

	for r, i in atlas_rects {
		if r == {} {
			instance_uv_remaps[i] = {-1, -1, -1, -1}
			continue
		}

		v := [4]f32 {
			r.x/f32(g_mem.atlas.width),
			(r.x + r.width)/f32(g_mem.atlas.width),
			r.y/f32(g_mem.atlas.height),
			(r.y + r.height)/f32(g_mem.atlas.height),
		}

		instance_uv_remaps[i] = v
	}

	// Enable mesh VAO to attach new buffer
	rg.EnableVertexArray(mesh.vaoId)

	transforms_vbo_id := rg.LoadVertexBuffer(raw_data(instance_transforms), i32(len(transforms)*size_of([16]f32)), false)

	// Instances transformation matrices are send to shader attribute location: SHADER_LOC_MATRIX_MODEL
	for i in 0..<4 {
		rg.EnableVertexAttribute(u32(material.shader.locs[rg.ShaderLocationIndex.MATRIX_MODEL]) + u32(i))
		offset := transmute(rawptr)(uintptr(i*size_of([4]f32)))
		rg.SetVertexAttribute(u32(material.shader.locs[rg.ShaderLocationIndex.MATRIX_MODEL]) + u32(i), 4, rg.FLOAT, false, size_of(rl.Matrix), offset)
		rg.SetVertexAttributeDivisor(u32(material.shader.locs[rg.ShaderLocationIndex.MATRIX_MODEL]) + u32(i), 1)
	}
	
	rg.DisableVertexBuffer()

	uv_remaps_vbo_id := rg.LoadVertexBuffer(raw_data(instance_uv_remaps), i32(len(atlas_rects)*size_of([4]f32)), false)
	rg.EnableVertexAttribute(u32(material.shader.locs[SHADER_LOCATION_UVS]))
	rg.SetVertexAttribute(u32(material.shader.locs[SHADER_LOCATION_UVS]), 4, rg.FLOAT, false, size_of([4]f32), nil)
	rg.SetVertexAttributeDivisor(u32(material.shader.locs[SHADER_LOCATION_UVS]), 1)

	rg.DisableVertexBuffer()
	rg.DisableVertexArray()

	// Upload model normal matrix (if locations available)
	if material.shader.locs[rg.ShaderLocationIndex.MATRIX_NORMAL] != -1 {
		rg.SetUniformMatrix(material.shader.locs[rg.ShaderLocationIndex.MATRIX_NORMAL], rl.MatrixTranspose(rl.MatrixInvert(rg.GetMatrixTransform())))
	}

	// Bind active texture maps (if available)

	// copied from rconfig.h
	MAX_MATERIAL_MAPS :: 12

	for ii in 0..<MAX_MATERIAL_MAPS {
		i := i32(ii)

		if material.maps[i].texture.id > 0 {
			// Select current shader texture slot
			rg.ActiveTextureSlot(i)

			// Enable texture for active slot
			mi := rl.MaterialMapIndex(i)
			if mi == rl.MaterialMapIndex.IRRADIANCE || mi == rl.MaterialMapIndex.PREFILTER || mi == rl.MaterialMapIndex.CUBEMAP {
				rg.EnableTextureCubemap(material.maps[i].texture.id)
			} else {
				rg.EnableTexture(material.maps[i].texture.id)
			}

			rg.SetUniform(material.shader.locs[i32(rg.ShaderLocationIndex.MAP_ALBEDO) + i], &i, i32(rg.ShaderUniformDataType.INT), 1)
		}
	}

	rg.EnableVertexArray(mesh.vaoId)

	mat_view_projection := mat_projection * mat_view * rg.GetMatrixTransform()
	rg.SetUniformMatrix(material.shader.locs[rl.ShaderLocationIndex.MATRIX_MVP], mat_view_projection)

	// Draw mesh instanced
	if mesh.indices != nil {
		rg.DrawVertexArrayElementsInstanced(0, mesh.triangleCount*3, nil, i32(len(transforms)))
	} else {
		rg.DrawVertexArrayInstanced(0, mesh.vertexCount, i32(len(transforms)))
	}

	// Unbind all bound texture maps
	for ii in 0..<MAX_MATERIAL_MAPS {
		i := i32(ii)
		if material.maps[i].texture.id > 0 {
			// Select current shader texture slot
			rg.ActiveTextureSlot(i)

			// Disable texture for active slot
			mi := rl.MaterialMapIndex(i)
			if mi == rl.MaterialMapIndex.IRRADIANCE || mi == rl.MaterialMapIndex.PREFILTER || mi == rl.MaterialMapIndex.CUBEMAP {
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
	rg.UnloadVertexBuffer(transforms_vbo_id)
	rg.UnloadVertexBuffer(uv_remaps_vbo_id)
}

@(export)
game_init :: proc() {
	g_mem = new(Game_Memory)

	g_mem^ = Game_Memory {
		player = {
			pos = {2, 2, -3},
		},
		default_shader = rl.LoadShader("default_lighting.vs", "default_lighting.fs"),
		default_shader_instanced = rl.LoadShader("default_lighting_instanced.vs", "default_lighting.fs"),
		shadowcasting_shader = rl.LoadShader("shadowcaster.vs", "shadowcaster.fs"),
		shadowcasting_shader_instanced = rl.LoadShader("shadowcaster_instanced.vs", "shadowcaster.fs"),
		skybox_shader = rl.LoadShader("skybox.vs", "skybox.fs"),
		atlas = rl.LoadTexture("atlas.png"),
		plane_mesh = rl.GenMeshPlane(1, 1, 2, 2),
		box_mesh = rl.GenMeshCube(1, 1, 1),
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

	ambient := Vec4{ 0.2, 0.2, 0.3, 1.0}

	rl.SetShaderValue(g_mem.default_shader, rl.GetShaderLocation(g_mem.default_shader, "ambient"), raw_data(&ambient), .VEC4)
	rl.SetShaderValue(g_mem.default_shader_instanced, rl.GetShaderLocation(g_mem.default_shader_instanced, "ambient"), raw_data(&ambient), .VEC4)

	append(&g_mem.climb_points, Climb_Point {
		pos = {0,  0.2, -10},
		wanted_facing = {0, 0, 1},
	})

	append(&g_mem.boxes, Box{
		pos = {0, -5, 0},
		size = {5, 10, 20},
	})

	append(&g_mem.boxes, Box{
		pos = {0, 4, 0},
		size = {6, 1, 20},
	})

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

	if target.id > 0 {
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