package game

import "core:math"
import la "core:math/linalg"

Debug_Camera :: struct {
	pos: Vec3,
	yaw, pitch: f32,
}

debug_camera_update :: proc(c: ^Debug_Camera) {
	c.yaw -= mouse_move.x * dt * 0.05
	c.pitch -= mouse_move.y * dt * 0.05
	rot := la.matrix4_from_yaw_pitch_roll_f32(c.yaw * math.TAU, c.pitch * math.TAU, 0)

	movement: Vec3
	
	if key_held[.Debug_Camera_Forward] {
		movement.z -= 1
	}
	
	if key_held[.Debug_Camera_Backward] {
		movement.z += 1
	}

	if key_held[.Debug_Camera_Left] {
		movement.x -= 1
	}

	if key_held[.Debug_Camera_Right] {
		movement.x += 1
	}

	speed := f32(key_held[.Sprint] ? 30 : 10)

	vel := la.mul(rot, vec4_point(la.normalize0(movement)*speed)).xyz
	c.pos += vel * dt
}