package game

import rl "vendor:raylib"
import "core:math/linalg"
import "core:fmt"
import rg "vendor:raylib/rlgl"

_ :: fmt

Gizmo_State :: enum {
	None,
	Dragging,
}

Editor_State :: struct {
	camera_pos: Vec3,
	camera_yaw: f32,
	camera_pitch: f32,

	selected_object: int,
	gizmo_state: Gizmo_State,
	gizmo_start_pos: Vec2,
	gizmo_object_start_pos: Vec3,
}

@(private="file")
es: ^Editor_State

editor_set_state :: proc(s: ^Editor_State) {
	es = s
}

editor_update_free_camera :: proc() {
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

	es.camera_yaw -= rl.GetMouseDelta().x * dt * 0.2
	es.camera_pitch -= rl.GetMouseDelta().y * dt * 0.2
	es.camera_pitch = clamp(es.camera_pitch, -0.24, 0.24)
	r := camera_rot_matrix(es.camera_pitch, es.camera_yaw)
	es.camera_pos += (linalg.mul(r, vec4_point(movement)) * 3).xyz * dt
}

editor_update_default :: proc() {
	cam := editor_camera()
	r := rl.GetMouseRay(rl.GetMousePosition(), cam)

	{
		b := &g_mem.boxes[es.selected_object]
		p := b.pos

		switch es.gizmo_state {
		case .None:
			if rl.IsMouseButtonPressed(.LEFT) {
				if coll := rl.GetRayCollisionSphere(r, p, 0.1); coll.hit {
					es.gizmo_state = .Dragging
					es.gizmo_start_pos = rl.GetMousePosition()
					es.gizmo_object_start_pos = p
				}
			}

		case .Dragging:
			diff := es.gizmo_start_pos - rl.GetMousePosition()
			b.pos.x = es.gizmo_object_start_pos.x - diff.x
			if rl.IsMouseButtonReleased(.LEFT) {
				es.gizmo_state = .None
			}
		}
	}

	if es.gizmo_state == .None && rl.IsMouseButtonPressed(.LEFT) {
		closest_idx := -1
		closest_idx_distance := max(f32)
		for b, i in g_mem.boxes {
			bb := rl.BoundingBox {
				min = b.pos - b.size * 0.5,
				max = b.pos + b.size * 0.5,
			}

			if coll := rl.GetRayCollisionBox(r, bb); coll.hit {
				if coll.distance < closest_idx_distance {
					closest_idx = i
					closest_idx_distance = coll.distance
				}
			}
		}

		if closest_idx != -1 {
			es.selected_object = closest_idx
		}
	}
}

editor_camera :: proc() -> rl.Camera3D {
	return {
		position = es.camera_pos,
		target = es.camera_pos + linalg.mul(camera_rot_matrix(es.camera_pitch, es.camera_yaw), Vec4{0, 0, -1, 1}).xyz,
		up = {0, 1, 0},
		fovy = 90,
		projection = .PERSPECTIVE,
	}
}

editor_update :: proc() {
	if rl.IsMouseButtonPressed(.RIGHT) {
		rl.DisableCursor()
	}

	if rl.IsMouseButtonReleased(.RIGHT) {
		rl.EnableCursor()
	}

	if rl.IsMouseButtonDown(.RIGHT) {
		editor_update_free_camera()
	} else {
		editor_update_default()
	}

	rl.BeginDrawing()
	cam := editor_camera()
	draw_world(cam)

	rl.BeginMode3D(cam)

	old_line_width := rg.GetLineWidth()
	rg.SetLineWidth(5)
	for b, i in g_mem.boxes {
		if es.selected_object == i {
			rl.DrawCubeWiresV(b.pos, b.size, rl.RED)
		}
	}
	rl.EndMode3D()

	rl.BeginMode3D(cam)
	rg.DisableDepthTest()
	{
		b := &g_mem.boxes[es.selected_object]
		p := b.pos

		rl.DrawSphere(p, 0.1, rl.RED)
	}

	rl.EndMode3D()
	rg.EnableDepthTest()
	rl.EndDrawing()
	rg.SetLineWidth(old_line_width)
}