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
import "core:math"

_ :: linalg
_ :: fmt

Box :: struct {
	size: Vec3,
	pos: Vec3,
}

GameMemory :: struct {	
	player_pos: Vec3,
	player_vel: Vec3,
	yaw: f32,
	pitch: f32,
	default_shader: rl.Shader,
	skybox_shader: rl.Shader,
	teapot: rl.Model,
	box: rl.Model,
	boxes: [dynamic]Box,
	mouse_captured: bool,
	player_grounded: bool,
}

g_mem: ^GameMemory

PLAYER_SIZE :: Vec3 { 0.3, 1, 0.3 }

player_bounding_box :: proc() -> rl.BoundingBox {
	return {
		min = g_mem.player_pos - PLAYER_SIZE*0.5,
		max = g_mem.player_pos + PLAYER_SIZE*0.5,
	}
}

update :: proc() {
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

		g_mem.yaw -= rl.GetMouseDelta().x * rl.GetFrameTime() * 0.2
		g_mem.pitch -= rl.GetMouseDelta().y * rl.GetFrameTime() * 0.2
		g_mem.pitch = clamp(g_mem.pitch, -0.24, 0.24)
		r := linalg.matrix4_rotate(g_mem.yaw * math.TAU, Vec3{0, 1, 0})
		g_mem.player_vel.xz = linalg.mul(r, vec4_point(movement)).xz * 3
	}
	
	g_mem.player_vel.y -= rl.GetFrameTime() * 9.82
	g_mem.player_pos.y += g_mem.player_vel.y * rl.GetFrameTime()
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

	g_mem.player_pos.x += g_mem.player_vel.x * rl.GetFrameTime()

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


draw_skybox :: proc()
{
	rl.BeginShaderMode(g_mem.skybox_shader)
    s :: 1000
    c := rl.RED

    rl.rlPushMatrix()
        rl.rlBegin(rl.RL_TRIANGLES)
            rl.rlColor4ub(c.r, c.g, c.b, c.a)

            // Front face
            rl.rlNormal3f(0, 0, -1)
            rl.rlVertex3f(+s/2, -s/2, +s/2)
            rl.rlVertex3f(-s/2, -s/2, +s/2)
            rl.rlVertex3f(-s/2, +s/2, +s/2)
            rl.rlVertex3f(-s/2, +s/2, +s/2)
            rl.rlVertex3f(+s/2, +s/2, +s/2)
            rl.rlVertex3f(+s/2, -s/2, +s/2)

            // Back
            rl.rlNormal3f(0, 0, 1)
            rl.rlVertex3f(-s/2, -s/2, -s/2)
            rl.rlVertex3f(+s/2, -s/2, -s/2)
            rl.rlVertex3f(-s/2, +s/2, -s/2)
            rl.rlVertex3f(+s/2, +s/2, -s/2)
            rl.rlVertex3f(-s/2, +s/2, -s/2)
            rl.rlVertex3f(+s/2, -s/2, -s/2)

            // Left
            rl.rlNormal3f(-1, 0, 0)
            rl.rlVertex3f(+s/2, -s/2, -s/2)
            rl.rlVertex3f(+s/2, -s/2, +s/2)
            rl.rlVertex3f(+s/2, +s/2, -s/2)
            rl.rlVertex3f(+s/2, +s/2, +s/2)
            rl.rlVertex3f(+s/2, +s/2, -s/2)
            rl.rlVertex3f(+s/2, -s/2, +s/2)

            // Right
            rl.rlNormal3f(1, 0, 0)
            rl.rlVertex3f(-s/2, -s/2, +s/2)
            rl.rlVertex3f(-s/2, -s/2, -s/2)
            rl.rlVertex3f(-s/2, +s/2, -s/2)
            rl.rlVertex3f(-s/2, +s/2, -s/2)
            rl.rlVertex3f(-s/2, +s/2, +s/2)
            rl.rlVertex3f(-s/2, -s/2, +s/2)

            // Bottom
            rl.rlNormal3f(0, 1, 0)
            rl.rlVertex3f(-s/2, -s/2, -s/2)
            rl.rlVertex3f(-s/2, -s/2, +s/2)
            rl.rlVertex3f(+s/2, -s/2, -s/2)
            rl.rlVertex3f(+s/2, -s/2, +s/2)
            rl.rlVertex3f(+s/2, -s/2, -s/2)
            rl.rlVertex3f(-s/2, -s/2, +s/2)

            // Top
            rl.rlNormal3f(0, -1, 0)
            rl.rlVertex3f(-s/2, +s/2, +s/2)
            rl.rlVertex3f(-s/2, +s/2, -s/2)
            rl.rlVertex3f(+s/2, +s/2, -s/2)
            rl.rlVertex3f(+s/2, +s/2, -s/2)
            rl.rlVertex3f(+s/2, +s/2, +s/2)
            rl.rlVertex3f(-s/2, +s/2, +s/2)
        rl.rlEnd()
    rl.rlPopMatrix()
    rl.EndShaderMode()
}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	rl.BeginMode3D(game_camera())
	draw_skybox()
	rl.BeginShaderMode(g_mem.default_shader)

	rl.SetShaderValue(g_mem.default_shader, rl.ShaderLocationIndex(g_mem.default_shader.locs[rl.ShaderLocationIndex.VECTOR_VIEW]), raw_data(&g_mem.player_pos), .VEC3)

	rl.DrawModel(g_mem.teapot, {0, 0, -5}, 0.3, rl.WHITE)

	for b in g_mem.boxes {
		rl.DrawModelEx(g_mem.box, b.pos, 0, 0, b.size, rl.WHITE)
		rl.DrawModelEx(g_mem.box, b.pos, 0, 0, b.size, rl.WHITE)
	}
	
	rl.EndShaderMode()

	rl.EndMode3D()

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
		position = g_mem.player_pos,
		target = g_mem.player_pos + linalg.mul(camera_rot_matrix(), Vec4{0, 0, -1, 1}).xyz,
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

@(export)
game_init :: proc() {
	g_mem = new(GameMemory)

	g_mem^ = GameMemory {
		player_pos = {2, 2, -3},
		yaw = 0.1,
		pitch = -0.1,
		default_shader = rl.LoadShader("default_lighting.vs", "default_lighting.fs"),
		skybox_shader = rl.LoadShader("skybox.vs", "skybox.fs"),
		teapot = rl.LoadModel("teapot.obj"),
		box = rl.LoadModel("box.obj"),
	}

	ambient := Vec4{ 0.2, 0.2, 0.3, 1.0}
	rl.SetShaderValue(g_mem.default_shader, rl.GetShaderLocation(g_mem.default_shader, "ambient"), raw_data(&ambient), .VEC4)

	for midx in 0..<g_mem.teapot.materialCount {
		g_mem.teapot.materials[midx].shader = g_mem.default_shader
	}

	for midx in 0..<g_mem.box.materialCount {
		g_mem.box.materials[midx].shader = g_mem.default_shader
	}
	
	g_mem.default_shader.locs[rl.ShaderLocationIndex.VECTOR_VIEW] = i32(rl.GetShaderLocation(g_mem.default_shader, "viewPos"))

	set_light(0, true, {20, 100, -100}, { 0.8, 0.5, 0.5, 1 }, true)

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
		size = {2, 1, 2},
	})

	append(&g_mem.boxes, Box{
		pos = {0, 0, -3},
		size = {3, 5, 1},
	})

	game_hot_reloaded(g_mem)
}

set_light :: proc(n: int, enabled: bool, pos: Vec3, color: Vec4, directional: bool) {
	enabled := int(enabled)
	type := directional ? 1 : 0
	pos := pos
	color := color
	rl.SetShaderValue(g_mem.default_shader, rl.GetShaderLocation(g_mem.default_shader, fmt.ctprintf("lights[%v].enabled", n)), &enabled, .INT)
	rl.SetShaderValue(g_mem.default_shader, rl.GetShaderLocation(g_mem.default_shader, fmt.ctprintf("lights[%v].type", n)), &type, .INT)
	rl.SetShaderValue(g_mem.default_shader, rl.GetShaderLocation(g_mem.default_shader, fmt.ctprintf("lights[%v].position", n)), raw_data(&pos), .VEC3)
	rl.SetShaderValue(g_mem.default_shader, rl.GetShaderLocation(g_mem.default_shader, fmt.ctprintf("lights[%v].color", n)), raw_data(&color), .VEC4)
}

@(export)
game_shutdown :: proc() { 
	rl.EnableCursor()
	delete(g_mem.boxes)
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
	return size_of(GameMemory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g_mem = (^GameMemory)(mem)
}

@(export)
game_force_reload :: proc() -> bool {
	return rl.IsKeyPressed(.F5)
}

@(export)
game_force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.F6)
}