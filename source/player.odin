package game

import la "core:math/linalg"
import "core:math"
import sapp "sokol/app"

Player :: struct {
	yaw: f32,
	pitch: f32,
	roll: f32,
	pos: Vec3,
	vel: Vec3,
	grounded_at: f64,
	jumping: bool,
	roll_easer: Easer(Strafe_State),
	fov_easer: Easer(Run_State),
	state: Player_State,
}

Player_State :: enum {
	Default,
	Wall_Running,
}

Strafe_State :: enum {
	None,
	Left,
	Right,
}

Run_State :: enum {
	Still,
	Running,
}

player_on_load :: proc(p: ^Player) {
	p.roll_easer = {
		targets = {
			.None = 0,
			.Left = -0.015,
			.Right = 0.015,
		},
		durations = {
			.None = 0.2,
			.Left = 0.2,
			.Right = 0.2,
		},
		ease = proc(t: f32) -> f32 {
			return 1 - (1 - t) * (1 - t)
		},
	}

	p.fov_easer = {
		targets = {
			.Still = 0,
			.Running = 7,
		},
		durations = {
			.Still = 3,
			.Running = 0.4,
		},
		ease = proc(t: f32) -> f32 {
			return 1 - (1 - t) * (1 - t) * (1 - t) * (1 - t)
		},
	}
}

player_update :: proc(p: ^Player) {
	p.vel += {0, -9.82, 0} * dt

	movement: Vec3
	
	if key_held[.Forward] {
		movement.z -= 1
	}
	
	if key_held[.Backward] {
		movement.z += 1
	}

	if key_held[.Left] {
		movement.x -= 1
	}

	if key_held[.Right] {
		movement.x += 1
	}

	if left_touching {
		THRESHOLD :: 50
		movement.x = math.remap(left_touch_offset.x, -THRESHOLD, THRESHOLD, -1, 1)
		movement.z = math.remap(left_touch_offset.y, -THRESHOLD, THRESHOLD, -1, 1)
	}

	run_state := movement.z < 0 ? Run_State.Running : Run_State.Still
	easer_set_state(&p.fov_easer, run_state)
	g.fov_offset = easer_update(&p.fov_easer, dt)

	if la.length(movement) > 1 {
		movement = la.normalize0(movement)	
	}

	rot := la.matrix4_from_yaw_pitch_roll_f32(p.yaw * math.TAU, 0, 0)
	p.vel.xz = la.mul(rot, vec4_point(movement*7)).xz
	
	if sapp.mouse_locked() && !g.debug_free_fly {
		p.yaw -= mouse_move.x * dt * 0.05
		p.pitch -= mouse_move.y * dt * 0.05
	} else if mouse_held[.Left] {
		sapp.lock_mouse(true)
	}

	if right_touching {
		p.yaw -= right_touch_diff.x * dt * 0.05
		p.pitch -= right_touch_diff.y * dt * 0.05
	}
	
	p.pitch = clamp(p.pitch, -0.2, 0.2)

	p.pos.y += p.vel.y * dt
	grounded := false

	for &o in &g.objects {
		bb, bb_ok := o.collider.?

		if !bb_ok {
			continue
		}

		if obb, coll := bounding_box_get_overlap(player_bounding_box(), bb); coll {
			sign: f32 = p.pos.y + PLAYER_SIZE.y/2 < (o.pos.y + o.scl.y / 2) ? -1 : 1
			p.pos.y += (obb.max.y - obb.min.y) * sign
			p.vel.y = 0
			grounded = true
		}
	}

	p.pos.x += p.vel.x * dt

	for &o in &g.objects {
		bb, bb_ok := o.collider.?

		if !bb_ok {
			continue
		}

		if obb, coll := bounding_box_get_overlap(player_bounding_box(), bb); coll {
			sign: f32 = p.pos.x + PLAYER_SIZE.x/2 < (o.pos.x + o.scl.x / 2) ? -1 : 1
			p.pos.x += (obb.max.x - obb.min.x) * sign
			p.vel.x = 0
		}
	}

	p.pos.z += p.vel.z * dt

	for &o in &g.objects {
		bb, bb_ok := o.collider.?

		if !bb_ok {
			continue
		}

		if obb, coll := bounding_box_get_overlap(player_bounding_box(), bb); coll {
			sign: f32 = p.pos.z + PLAYER_SIZE.z/2 < (o.pos.z + o.scl.z / 2) ? -1 : 1
			p.pos.z += (obb.max.z - obb.min.z) * sign
			p.vel.z = 0
		}
	}

	if grounded {
		p.jumping = false
		p.grounded_at = time
	}

	if time < key_pressed_time[.Jump] + 0.1 && !p.jumping && time < (p.grounded_at + 0.1) {
		p.jumping = true
		p.vel.y = 4
	}

	camera_rel_vel := la.mul(la.inverse(rot), vec4_from_vec3(p.vel))
	strafe_state := Strafe_State.None

	if camera_rel_vel.x > 0.5 {
		strafe_state = .Right
	}

	if camera_rel_vel.x < -0.5 {
		strafe_state = .Left
	}

	easer_set_state(&p.roll_easer, strafe_state)
	p.roll = -easer_update(&p.roll_easer, dt)
}

PLAYER_SIZE :: Vec3 { 0.6, 1.8, 0.6 }

player_bounding_box :: proc() -> Bounding_Box {
	return {
		min = g.player.pos - PLAYER_SIZE*0.5,
		max = g.player.pos + PLAYER_SIZE*0.5,
	}
}
