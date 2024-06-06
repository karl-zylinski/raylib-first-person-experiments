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

GameMemory :: struct {	
	player_pos: Vec3,
	yaw: f32,
	pitch: f32,
	shader: rl.Shader,
	teapot: rl.Model,
	box: rl.Model,
	mouse_captured: bool,
}

g_mem: ^GameMemory

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
		r := camera_rot_matrix()
		g_mem.player_pos += linalg.mul(r, vec4_point(movement)).xyz * rl.GetFrameTime()
	}
}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)
	
	rl.BeginMode3D(game_camera())
	rl.BeginShaderMode(g_mem.shader)

    rl.SetShaderValue(g_mem.shader, rl.ShaderLocationIndex(g_mem.shader.locs[rl.ShaderLocationIndex.VECTOR_VIEW]), raw_data(&g_mem.player_pos), .VEC3)

	rl.DrawModel(g_mem.teapot, {0, 0, -5}, 0.3, rl.WHITE)
	rl.DrawModelEx(g_mem.box, {0, -1, 0}, 0, 0, {5, 1, 20}, rl.WHITE)
	rl.DrawModelEx(g_mem.box, {0, 4, 0}, 0, 0, {5, 1, 20}, rl.WHITE)

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
	rl.InitWindow(1280, 720, "Teapot Tycoon")
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
		fovy = 60,
		projection = .PERSPECTIVE,
	}
}

@(export)
game_init :: proc() {
	g_mem = new(GameMemory)

	g_mem^ = GameMemory {
		player_pos = {2, 2, -3},
		yaw = 0.1,
		pitch = -0.1,
		shader = rl.LoadShader("vertex_shader.vs", "fragment_shader.fs"),
		teapot = rl.LoadModel("teapot.obj"),
		box = rl.LoadModel("box.obj"),
	}


	ambient := Vec4{ 0.1, 0.1, 0.1, 1.0}
    rl.SetShaderValue(g_mem.shader, rl.GetShaderLocation(g_mem.shader, "ambient"), raw_data(&ambient), .VEC4)

	for midx in 0..<g_mem.teapot.materialCount {
		g_mem.teapot.materials[midx].shader = g_mem.shader
	}

	for midx in 0..<g_mem.box.materialCount {
		g_mem.box.materials[midx].shader = g_mem.shader
	}
	
	g_mem.shader.locs[rl.ShaderLocationIndex.VECTOR_VIEW] = i32(rl.GetShaderLocation(g_mem.shader, "viewPos"))

    set_light(0, true, {0, 2, 5}, { 0.8, 0.5, 0.5, 1 })

    set_light(1, true, {0, 2, -5}, { 0.4, 0.8, 0.5, 1 })
    set_light(3, true, {0, 2, -7}, { 0.4, 0.2, 0.9, 1 })

	game_hot_reloaded(g_mem)
}

set_light :: proc(n: int, enabled: bool, pos: Vec3, color: Vec4) {
	enabled := int(enabled)
	pos := pos
	color := color
	rl.SetShaderValue(g_mem.shader, rl.GetShaderLocation(g_mem.shader, fmt.ctprintf("lights[%v].enabled", n)), &enabled, .INT)
	rl.SetShaderValue(g_mem.shader, rl.GetShaderLocation(g_mem.shader, fmt.ctprintf("lights[%v].type", n)), &enabled, .INT)
	rl.SetShaderValue(g_mem.shader, rl.GetShaderLocation(g_mem.shader, fmt.ctprintf("lights[%v].position", n)), raw_data(&pos), .VEC3)
    rl.SetShaderValue(g_mem.shader, rl.GetShaderLocation(g_mem.shader, fmt.ctprintf("lights[%v].color", n)), raw_data(&color), .VEC4)
}

@(export)
game_shutdown :: proc() { 
	rl.EnableCursor()
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