package game

import "core:math/linalg"
import "core:math"

Mat4 :: matrix[4,4]f32
Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32

vec4_point :: proc(v: Vec3) -> Vec4 {
	return {v.x, v.y, v.z, 1}
}

create_model_matrix :: proc(model_pos: Vec3, rot: Vec3, scl: Vec3 = {1,1,1}) -> Mat4 {
	rotm := linalg.matrix4_from_euler_angles_xyz(rot.x * math.TAU, rot.y * math.TAU, rot.z * math.TAU)
	posm := linalg.matrix4_translate_f32(model_pos)
	sclm := linalg.matrix4_scale_f32(scl)
	return posm * rotm * sclm
}

create_view_matrix :: proc(pos: Vec3, yaw: f32, pitch: f32, roll: f32) -> Mat4 {
	rot := linalg.matrix4_from_yaw_pitch_roll_f32(yaw * math.TAU, pitch * math.TAU, 0)
	look := pos + linalg.mul(rot, Vec4{0, 0, 1, 1}).xyz
	roll_rot := linalg.matrix4_from_yaw_pitch_roll_f32(0, 0, roll * math.TAU)
	up := linalg.mul(rot, linalg.mul(roll_rot, Vec4{0, 1, 0, 1})).xyz
	return linalg.matrix4_look_at(pos, look, up)
}

create_projection_matrix :: proc(fovy: f32, render_width, render_height: f32) -> Mat4 {
	ar := abs(render_height) > 000.1 ? render_width / render_height : 1
	return linalg.matrix4_perspective(fovy, ar, 0.01, 1000.0)
}