package game

Mat4 :: matrix[4, 4]f32
Vec4 :: [4]f32
Vec3 :: [3]f32
Vec2i :: [2]int
Vec2 :: [2]f32

vec4_point :: proc(v: Vec3) -> Vec4 {
	return {
		v.x, v.y, v.z, 1,
	}
}

vec2_from_vec2i :: proc(p: Vec2i) -> Vec2 {
	return { f32(p.x), f32(p.y) }
}
