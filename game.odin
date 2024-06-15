package game

import "core:math/linalg"
import "core:fmt"
import rl "vendor:raylib"
import rg "vendor:raylib/rlgl"
import "core:math"
import "core:os"
import "core:c"

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
	default_shader_instanced: Shader,
	shadowcasting_shader_instanced: Shader,
	skybox_shader: Shader,
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

	cat_pos: Vec3,
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

player_set_state :: proc(state: Player_State) {
	g_mem.player.state_start = g_mem.time
	g_mem.player.state = state
}

Frame_State :: struct {
	crosshair_color: rl.Color,
}

update :: proc() -> Frame_State {
	cat_diff := Vec3{g_mem.player.pos.x, 0.5, g_mem.player.pos.z} - g_mem.cat_pos

	if linalg.length(cat_diff) > 2 {
		dir := linalg.normalize0(cat_diff)

		g_mem.cat_pos += dir * dt * 2
	}

	fs := Frame_State {
		crosshair_color = rl.GRAY,
	}

	// Rotate light
	// light_pos = {20*f32(math.cos(rl.GetTime())), 20, -20*f32(math.sin(rl.GetTime()))}

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
				player_set_state(Player_State_Climb_Down {
					start = p.pos,
					end = p.pos - {0, 4, 0},
				})
			}

		case Player_State_Climb_Down:
			t := f32(remap(g_mem.time, p.state_start, p.state_start + 3, 0, 1))
			p.pos = math.lerp(s.start, s.end, t)

			if t >= 1 {
				player_set_state(Player_State_Climb_End {
					start_yaw = p.yaw,
				})
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

	p.pos.z += p.vel.z * dt

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

	screen_mid := Vec2{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}*0.5
	cam := game_camera()
	mouse_ray := rl.GetMouseRay(screen_mid, cam)

	for c in g_mem.climb_points {
		if coll := rl.GetRayCollisionSphere(mouse_ray, c.pos, 0.1); coll.hit && coll.distance < 1.5 {
			fs.crosshair_color = rl.GREEN

			if rl.IsKeyPressed(.E) && union_type(g_mem.player.state) == Player_State_Default {
				player_set_state(Player_State_Climb_Start {
					point = c,
					start = g_mem.player.pos,
					start_pitch = g_mem.player.pitch,
					start_yaw = g_mem.player.yaw,
				})
				break
			}
		}
	}

	return fs
}

begin_shader_mode :: proc(s: ^Shader) {
	rg.SetShader(s.id, raw_data(s.rl_locs[:]))

	mat_view := rg.GetMatrixModelview()
	mat_projection := rg.GetMatrixProjection()

	mat_view_projection := mat_projection * mat_view * rg.GetMatrixTransform()

	if loc := s.uniform_locations[.Transform_Model_View_Projection]; loc != UNIFORM_LOCATION_NONE {
		rg.SetUniformMatrix(loc, mat_view_projection)
	}
}

end_shader_mode :: proc() {
	rg.SetShader(rg.GetShaderIdDefault(), rg.GetShaderLocsDefault())
}

draw_skybox :: proc() {
	begin_shader_mode(&g_mem.skybox_shader)
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

	end_shader_mode()
}

draw_world :: proc(shader: Shader, shader_params: Shader_Parameters, disable_backface_culling: bool) {
	// boxes
	{
		box_transforms := make([dynamic]rl.Matrix, context.temp_allocator)
		atlas_rects := make([dynamic]Rect, context.temp_allocator)

		for b in g_mem.boxes {
			m: rl.Matrix = auto_cast (linalg.matrix4_translate(b.pos) * linalg.matrix4_scale(b.size))
			append(&box_transforms, m)
			append(&atlas_rects, Rect {})
		}

		draw_mesh_instanced(g_mem.box_mesh, shader, shader_params, box_transforms[:], atlas_rects[:])
	}

	if disable_backface_culling {
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
		append(&npc_transforms, get_npc_transform(g_mem.cat_pos))
		append(&npc_rects, atlas_textures[.Cat].rect)

		draw_mesh_instanced(g_mem.plane_mesh, shader, shader_params, npc_transforms[:], npc_rects[:])
	}

	if disable_backface_culling {
		rg.EnableBackfaceCulling()
	}
}

draw :: proc(fs: Frame_State) {
	shader_params := Shader_Parameters {
		albedo = rl.WHITE,
		atlas = g_mem.atlas,
		shadow_map = g_mem.shadow_map.depth,
		lights = {
			0 = {
				type = .Directional,
				direction = Vec3{0,0,0}-light_pos,
				color = rl.WHITE,
			},
		},
	}

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
	draw_world(g_mem.shadowcasting_shader_instanced, shader_params, true)
	rl.EndMode3D()
	rl.EndTextureMode()

	// Shadowmap done. Draw normally and use shadows!

	shader_params.transf_light_vp = light_proj * light_view

	rl.ClearBackground(rl.BLACK)

	cam := game_camera()

	shader_params.view_pos = cam.position
	rl.BeginMode3D(cam)
	draw_skybox()

	draw_world(g_mem.default_shader_instanced, shader_params, false)

	for c in g_mem.climb_points {
		rl.DrawSphere(c.pos, 0.1, rl.RED)
	}
		
	rl.EndMode3D()

	screen_mid := Vec2{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}*0.5
	rl.DrawCircleV(screen_mid, 5, fs.crosshair_color)

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

	frame_state := update()
	draw(frame_state)
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

vec4_from_color :: proc(c: Color) -> Vec4 {
	return {
		f32(c.r)/255,
		f32(c.g)/255,
		f32(c.b)/255,
		f32(c.a)/255,
	}
}

draw_mesh_instanced :: proc(mesh: rl.Mesh, shader: Shader, params: Shader_Parameters, transforms: []rl.Matrix, atlas_rects: []Rect) {
	assert(len(transforms) == len(atlas_rects))

	rg.EnableShader(shader.id)

	// Upload to shader material.colDiffuse
	if shader.uniform_locations[.Color_Diffuse] != UNIFORM_LOCATION_NONE {
		color := vec4_from_color(params.albedo)
		rg.SetUniform(shader.uniform_locations[.Color_Diffuse], raw_data(&color), i32(rg.ShaderUniformDataType.VEC4), 1)
	}

	for l, i in params.lights {
		type_loc, direction_loc, position_loc, color_loc: c.int

		switch i {
			case 0:
				type_loc = shader.uniform_locations[.Light_0_Type]
				direction_loc = shader.uniform_locations[.Light_0_Direction]
				position_loc = shader.uniform_locations[.Light_0_Position]
				color_loc = shader.uniform_locations[.Light_0_Color]

			case 1:
				type_loc = shader.uniform_locations[.Light_1_Type]
				direction_loc = shader.uniform_locations[.Light_1_Direction]
				position_loc = shader.uniform_locations[.Light_1_Position]
				color_loc = shader.uniform_locations[.Light_1_Color]

			case 2:
				type_loc = shader.uniform_locations[.Light_2_Type]
				direction_loc = shader.uniform_locations[.Light_2_Direction]
				position_loc = shader.uniform_locations[.Light_2_Position]
				color_loc = shader.uniform_locations[.Light_2_Color]

			case 3:
				type_loc = shader.uniform_locations[.Light_3_Type]
				direction_loc = shader.uniform_locations[.Light_3_Direction]
				position_loc = shader.uniform_locations[.Light_3_Position]
				color_loc = shader.uniform_locations[.Light_3_Color]
		}

		if type_loc == -1 || direction_loc == -1 || position_loc == -1 || color_loc == -1 {
			continue
		}

		type := i32(l.type)
		color := vec4_from_color(l.color)
		rg.SetUniform(type_loc, &type, i32(rg.ShaderUniformDataType.INT), 1)

		switch l.type {
			case .None:
			case .Directional:
				dir := l.direction
				rg.SetUniform(direction_loc, &dir, i32(rg.ShaderUniformDataType.VEC3), 1)
			case .Point:
				pos := l.position
				rg.SetUniform(position_loc, &pos, i32(rg.ShaderUniformDataType.VEC3), 1)
		}
		
		rg.SetUniform(color_loc, &color, i32(rg.ShaderUniformDataType.VEC4), 1)
	}

	// Populate uniform matrices
	mat_view := rg.GetMatrixModelview()
	mat_projection := rg.GetMatrixProjection()

	if loc := shader.uniform_locations[.Transform_View]; loc != UNIFORM_LOCATION_NONE {
		rg.SetUniformMatrix(loc, mat_view)
	}

	if loc := shader.uniform_locations[.Light_View_Projection]; loc != UNIFORM_LOCATION_NONE {
		rg.SetUniformMatrix(loc, params.transf_light_vp)
	}

	if loc := shader.uniform_locations[.Position_Camera]; loc != UNIFORM_LOCATION_NONE {
		pos := params.view_pos
		rg.SetUniform(loc, &pos, i32(rg.ShaderUniformDataType.VEC3), 1)
	}

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
		loc := u32(Shader_Attribute_Location.Instance_Transform_0) + u32(i)
		rg.EnableVertexAttribute(loc)
		offset := transmute(rawptr)(uintptr(i*size_of([4]f32)))
		rg.SetVertexAttribute(loc, 4, rg.FLOAT, false, size_of(rl.Matrix), offset)
		rg.SetVertexAttributeDivisor(loc, 1)
	}
	
	rg.DisableVertexBuffer()

	uv_remaps_vbo_id := rg.LoadVertexBuffer(raw_data(instance_uv_remaps), i32(len(atlas_rects)*size_of([4]f32)), false)
	uv_remap_loc := u32(Shader_Attribute_Location.Instance_UV_Remap)
	rg.EnableVertexAttribute(uv_remap_loc)
	rg.SetVertexAttribute(uv_remap_loc, 4, rg.FLOAT, false, size_of([4]f32), nil)
	rg.SetVertexAttributeDivisor(uv_remap_loc, 1)

	rg.DisableVertexBuffer()
	rg.DisableVertexArray()

	// Upload model normal matrix (if locations available)
	if loc := shader.uniform_locations[.Transform_Normal]; loc != UNIFORM_LOCATION_NONE {
		rg.SetUniformMatrix(loc, rl.MatrixTranspose(rl.MatrixInvert(rg.GetMatrixTransform())))
	}

	set_texture :: proc(shader: Shader, name: Texture_Name, tex: rl.Texture) {
		if tex.id == 0 {
			return
		}

		loc := shader.texture_locations[name]

		if loc == UNIFORM_LOCATION_NONE {
			return
		}

		i := c.int(name)
		rg.ActiveTextureSlot(i)
		rg.EnableTexture(tex.id)
		rg.SetUniform(loc, &i, i32(rg.ShaderUniformDataType.INT), 1)
	}

	set_texture(shader, .Atlas, params.atlas)
	set_texture(shader, .Shadow_Map, params.shadow_map)

	rg.EnableVertexArray(mesh.vaoId)

	mat_view_projection := mat_projection * mat_view * rg.GetMatrixTransform()

	if loc := shader.uniform_locations[.Transform_Model_View_Projection]; loc != UNIFORM_LOCATION_NONE {
		rg.SetUniformMatrix(loc, mat_view_projection)
	}

	// Draw mesh instanced
	if mesh.indices != nil {
		rg.DrawVertexArrayElementsInstanced(0, mesh.triangleCount*3, nil, i32(len(transforms)))
	} else {
		rg.DrawVertexArrayInstanced(0, mesh.vertexCount, i32(len(transforms)))
	}

	for ii in 0..<len(Texture_Name) {
		i := i32(ii)
		rg.ActiveTextureSlot(i)
		rg.DisableTexture()
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

Shader_Attribute_Location :: enum {
	Position,
	Texcoord,
	Normal,
	Color,
	Tangent,
	Texcoord2,
	Instance_Transform_0,
	Instance_Transform_1,
	Instance_Transform_2,
	Instance_Transform_3,
	Instance_UV_Remap,
}

Uniform_Name :: enum {
	Transform_Model,
	Transform_Model_View_Projection,
	Transform_View_Projection,
	Transform_View,
	Transform_Normal,
	Light_0_Type,
	Light_0_Direction,
	Light_0_Position,
	Light_0_Color,
	Light_1_Type,
	Light_1_Direction,
	Light_1_Position,
	Light_1_Color,
	Light_2_Type,
	Light_2_Direction,
	Light_2_Position,
	Light_2_Color,
	Light_3_Type,
	Light_3_Direction,
	Light_3_Position,
	Light_3_Color,
	Color_Diffuse,
	Position_Camera,
	Light_View_Projection,
}

Texture_Name :: enum {
	Atlas,
	Shadow_Map,
}

Shader :: struct {
	id: c.uint,
	uniform_locations: [Uniform_Name]c.int,
	texture_locations: [Texture_Name]c.int,
	rl_locs: [32]c.int,
}

Light_Type :: enum {
	None,
	Directional,
	Point,
}

Shader_Light :: struct {
	type: Light_Type,
	direction: Vec3,
	position: Vec3,
	color: rl.Color,
}

Shader_Parameters :: struct {
	albedo: rl.Color,
	atlas: rl.Texture,
	shadow_map: rl.Texture,
	view_pos: Vec3,
	transf_light_vp: rl.Matrix,
	lights: [4]Shader_Light,
}

UNIFORM_LOCATION_NONE :: -1

load_shader :: proc(vs_name: string, fs_name: string) -> Shader {
	vs_shader: c.uint

	if vs, ok := os.read_entire_file(vs_name, context.temp_allocator); ok {
		vs_shader = rg.CompileShader(temp_cstring(string(vs)), rg.VERTEX_SHADER)
	}

	fs_shader: c.uint
	if fs, ok := os.read_entire_file(fs_name, context.temp_allocator); ok {
		fs_shader = rg.CompileShader(temp_cstring(string(fs)), rg.FRAGMENT_SHADER)
	}

	s: Shader
	s.id = rg.LoadShaderProgram(vs_shader, fs_shader)
	s.uniform_locations = {
		.Transform_Model_View_Projection = rg.GetLocationUniform(s.id, "transf_mvp"),
		.Transform_Model = rg.GetLocationUniform(s.id, "transf_model"),
		.Transform_View_Projection = rg.GetLocationUniform(s.id, "transf_vp"),
		.Transform_View = rg.GetLocationUniform(s.id, "transf_view"),
		.Transform_Normal = rg.GetLocationUniform(s.id, "transf_normal"),
		.Color_Diffuse = rg.GetLocationUniform(s.id, "color_diffuse"),
		.Position_Camera = rg.GetLocationUniform(s.id, "position_camera"),
		.Light_View_Projection = rg.GetLocationUniform(s.id, "transf_light_vp"),
		.Light_0_Type = rg.GetLocationUniform(s.id, "lights[0].type"),
		.Light_0_Direction = rg.GetLocationUniform(s.id, "lights[0].direction"),
		.Light_0_Position = rg.GetLocationUniform(s.id, "lights[0].position"),
		.Light_0_Color = rg.GetLocationUniform(s.id, "lights[0].color"),
		.Light_1_Type = rg.GetLocationUniform(s.id, "lights[1].type"),
		.Light_1_Direction = rg.GetLocationUniform(s.id, "lights[1].direction"),
		.Light_1_Position = rg.GetLocationUniform(s.id, "lights[1].position"),
		.Light_1_Color = rg.GetLocationUniform(s.id, "lights[1].color"),
		.Light_2_Type = rg.GetLocationUniform(s.id, "lights[2].type"),
		.Light_2_Direction = rg.GetLocationUniform(s.id, "lights[2].direction"),
		.Light_2_Position = rg.GetLocationUniform(s.id, "lights[2].position"),
		.Light_2_Color = rg.GetLocationUniform(s.id, "lights[2].color"),
		.Light_3_Type = rg.GetLocationUniform(s.id, "lights[3].type"),
		.Light_3_Direction = rg.GetLocationUniform(s.id, "lights[3].direction"),
		.Light_3_Position = rg.GetLocationUniform(s.id, "lights[3].position"),
		.Light_3_Color = rg.GetLocationUniform(s.id, "lights[3].color"),
	}

	s.texture_locations = {
		.Atlas = rg.GetLocationUniform(s.id, "tex_atlas"),
		.Shadow_Map = rg.GetLocationUniform(s.id, "tex_shadow_map"),
	}

	rl_locs := [rg.ShaderLocationIndex]c.int {
		.VERTEX_POSITION = 0,
		.VERTEX_TEXCOORD01 = 1,
		.VERTEX_TEXCOORD02 = 6,
		.VERTEX_NORMAL = 2,
		.VERTEX_TANGENT = 5,
		.VERTEX_COLOR = 3,
		.MATRIX_MVP = s.uniform_locations[.Transform_Model_View_Projection],
		.MATRIX_VIEW = s.uniform_locations[.Transform_View],
		.MATRIX_PROJECTION = -1,
		.MATRIX_MODEL = s.uniform_locations[.Transform_Model],
		.MATRIX_NORMAL = s.uniform_locations[.Transform_Normal],
		.VECTOR_VIEW = s.uniform_locations[.Position_Camera],
		.COLOR_DIFFUSE = s.uniform_locations[.Color_Diffuse],
		.COLOR_SPECULAR = -1,
		.COLOR_AMBIENT = -1,
		.MAP_ALBEDO = s.texture_locations[.Atlas],
		.MAP_METALNESS = -1,
		.MAP_NORMAL = -1,
		.MAP_ROUGHNESS = -1,
		.MAP_OCCLUSION = -1,
		.MAP_EMISSION = -1,
		.MAP_HEIGHT = -1,
		.MAP_CUBEMAP = -1,
		.MAP_IRRADIANCE = -1,
		.MAP_PREFILTER = -1,
		.MAP_BRDF = -1,
	}

	for l, i in rl_locs {
		s.rl_locs[i] = l
	}

	return s
}

@(export)
game_init :: proc() {
	g_mem = new(Game_Memory)

	g_mem^ = Game_Memory {
		player = {
			pos = {2, 2, -3},
		},
		shadowcasting_shader_instanced = load_shader("shadowcaster_instanced.vs", "shadowcaster.fs"),
		default_shader_instanced = load_shader("default_lighting_instanced.vs", "default_lighting.fs"),
		skybox_shader = load_shader("skybox.vs", "skybox.fs"),
		atlas = rl.LoadTexture("atlas.png"),
		plane_mesh = rl.GenMeshPlane(1, 1, 2, 2),
		box_mesh = rl.GenMeshCube(1, 1, 1),
		shadow_map = create_shadowmap_rt(4096, 4096),
	}

	g_mem.cat_pos = {g_mem.player.pos.x, 0.5, g_mem.player.pos.z - 2}

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
		size = {0.5, 10, 0.5},
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