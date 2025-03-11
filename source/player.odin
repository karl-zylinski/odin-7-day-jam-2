package game

import la "core:math/linalg"
import "core:math"
import sapp "sokol/app"
import "core:fmt"

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
	state_time: f32,
}

Player_State :: union #no_nil {
	Player_State_Default,
	Player_State_Wall_Running,
}

Player_State_Default :: struct {

}

Player_State_Wall_Running :: struct {
	wall_side: Direction,
	need_look_dir: Direction,
}

Direction :: enum {
	North,
	East,
	South,
	West,
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

player_set_state :: proc(p: ^Player, s: Player_State) {
	p.state_time = 0
	p.state = s
}

player_update :: proc(p: ^Player) {
	p.vel += {0, -15, 0} * dt
	p.state_time += dt

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

	hit_sides: bit_set[Direction]

	for &o in &g.objects {
		bb, bb_ok := o.collider.?

		if !bb_ok {
			continue
		}

		if obb, coll := bounding_box_get_overlap(player_bounding_box(p^), bb); coll {
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

		sign := (p.pos.x + PLAYER_SIZE.x/2 < o.pos.x + o.scl.x / 2) ? -1 : 1
		pbb := player_bounding_box(p^)
		sbb := player_left_right_bounding_box(p^)

		if obb, coll := bounding_box_get_overlap(pbb, bb); coll {
			p.pos.x += (obb.max.x - obb.min.x) * f32(sign)
			p.vel.x = 0
		}

		if bounding_box_check_overlap(sbb, bb) {
			if sign == -1 {
				hit_sides += { .East }
			}

			if sign == 1 {
				hit_sides += { .West }
			}
		}
	}

	p.pos.z += p.vel.z * dt

	for &o in &g.objects {
		bb, bb_ok := o.collider.?

		if !bb_ok {
			continue
		}

		sign := (p.pos.z + PLAYER_SIZE.z/2 < o.pos.z + o.scl.z / 2) ? -1 : 1
		pbb := player_bounding_box(p^)
		sbb := player_front_back_bounding_box(p^)

		if obb, coll := bounding_box_get_overlap(pbb, bb); coll {
			p.pos.z += (obb.max.z - obb.min.z) * f32(sign)
			p.vel.z = 0
		}

		if bounding_box_check_overlap(sbb, bb) {
			if sign == 1 {
				hit_sides += { .North }
			}

			if sign == -1 {
				hit_sides += { .South }
			}
		}
	}

	if grounded {
		p.jumping = false
		p.grounded_at = time
	}

	look_dir := player_look_direction(p^)

	switch &s in p.state {
	case Player_State_Default:
		if time < key_pressed_time[.Jump] + 0.1 && !p.jumping && time < (p.grounded_at + 0.1) {
			WALL_RUN_MIN_SPEED :: 1

			if hit_sides != nil {
				if .West in hit_sides && movement.x < 0 && p.vel.z < -WALL_RUN_MIN_SPEED && look_dir == .North {
					player_set_state(p, Player_State_Wall_Running {
						wall_side = .West,
						need_look_dir = look_dir,
					})

					break
				}

				if .West in hit_sides && movement.x > 0 && p.vel.z > WALL_RUN_MIN_SPEED && look_dir == .South {
					player_set_state(p, Player_State_Wall_Running {
						wall_side = .West,
						need_look_dir = look_dir,
					})

					break
				}

				if .East in hit_sides && movement.x > 0 && p.vel.z < -WALL_RUN_MIN_SPEED && look_dir == .North {
					player_set_state(p, Player_State_Wall_Running {
						wall_side = .East,
						need_look_dir = look_dir,
					})

					break
				}

				if .East in hit_sides && movement.x < 0 && p.vel.z > WALL_RUN_MIN_SPEED && look_dir == .South {
					player_set_state(p, Player_State_Wall_Running {
						wall_side = .East,
						need_look_dir = look_dir,
					})

					break
				}

				if .North in hit_sides && movement.x > 0 && p.vel.x < -WALL_RUN_MIN_SPEED && look_dir == .West {
					player_set_state(p, Player_State_Wall_Running {
						wall_side = .North,
						need_look_dir = look_dir,
					})

					break
				}

				if .North in hit_sides && movement.x < 0 && p.vel.x > WALL_RUN_MIN_SPEED && look_dir == .East {
					player_set_state(p, Player_State_Wall_Running {
						wall_side = .North,
						need_look_dir = look_dir,
					})

					break
				}

				if .South in hit_sides && movement.x > 0 && p.vel.x > WALL_RUN_MIN_SPEED && look_dir == .East {
					player_set_state(p, Player_State_Wall_Running {
						wall_side = .South,
						need_look_dir = look_dir,
					})

					break
				}

				if .South in hit_sides && movement.x < 0 && p.vel.x < -WALL_RUN_MIN_SPEED && look_dir == .West {
					player_set_state(p, Player_State_Wall_Running {
						wall_side = .South,
						need_look_dir = look_dir,
					})

					break
				}
			}

			p.jumping = true
			p.vel.y = 4
		}


	case Player_State_Wall_Running:
		done := false
		if s.need_look_dir != look_dir {
			done = true
		} if s.wall_side not_in hit_sides {
			done = true
		} else if p.state_time > 0.7 {
			done = true
		} else {
			p.vel += {0, 15.1, 0} * dt
		}

		if done {
			player_set_state(p, Player_State_Default{})
		}
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

player_bounding_box :: proc(p: Player) -> Bounding_Box {
	return {
		min = p.pos - PLAYER_SIZE*0.5,
		max = p.pos + PLAYER_SIZE*0.5,
	}
}

PLAYER_FRONT_BACK_COLLIDER_SIZE :: Vec3 {PLAYER_SIZE.x * 0.7, PLAYER_SIZE.y * 0.7, PLAYER_SIZE.z * 1.5}
PLAYER_LEFT_RIGHT_COLLIDER_SIZE :: Vec3 {PLAYER_SIZE.x * 1.5, PLAYER_SIZE.y * 0.7, PLAYER_SIZE.z * 0.7}

player_front_back_bounding_box :: proc(p: Player) -> Bounding_Box {
	return {
		min = p.pos - PLAYER_FRONT_BACK_COLLIDER_SIZE*0.5,
		max = p.pos + PLAYER_FRONT_BACK_COLLIDER_SIZE*0.5,
	}
}

player_look_direction :: proc(p: Player) -> Direction {
	y := (p.yaw == 1 ? 1 : la.fract(p.yaw)) * 8.0

	if y >= 1 && y <= 3 {
		return .West
	}

	if y >= 3 && y <= 5 {
		return .South
	}

	if y >= 5 && y <= 7 {
		return .East
	}

	return .North
}

player_left_right_bounding_box :: proc(p: Player) -> Bounding_Box {
	return {
		min = p.pos - PLAYER_LEFT_RIGHT_COLLIDER_SIZE*0.5,
		max = p.pos + PLAYER_LEFT_RIGHT_COLLIDER_SIZE*0.5,
	}
}