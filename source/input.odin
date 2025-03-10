package game

import sapp "sokol/app"

Key :: enum {
	None,
	Forward,
	Backward,
	Left,
	Right,
	Jump,
}

key_pressed: [Key]bool
key_held: [Key]bool
key_pressed_time: [Key]f64

key_mapping := #partial #sparse [sapp.Keycode]Key {
	.W = .Forward,
	.S = .Backward,
	.A = .Left,
	.D = .Right,
	.SPACE = .Jump,
}

Mouse_Button :: enum {
	Left,
	Right,
}

mouse_held: [Mouse_Button]bool
mouse_move: [2]f32

left_touch_origin: Vec2
right_touch_prev: Vec2
left_touching: bool
right_touching: bool

left_touch_offset: Vec2
right_touch_diff: Vec2

process_input :: proc(e: ^sapp.Event) {
	#partial switch e.type {
		case .MOUSE_MOVE: 
			mouse_move += {e.mouse_dx, e.mouse_dy}

		case .KEY_DOWN:
			if e.key_repeat == true {
				break
			}

			key := key_mapping[e.key_code]

			if key != .None {
				if !key_held[key] {
					key_pressed_time[key] = g.time
				}

				key_held[key] = true
				key_pressed[key] = true
			}
			
			if e.key_code == .F6 {
				force_reset = true
			}

			if e.key_code == .ESCAPE {
				sapp.lock_mouse(false)
			}

		case .KEY_UP:
			key := key_mapping[e.key_code]
			if key != .None {
				key_held[key] = false
			}

		case .MOUSE_DOWN:
			if e.mouse_button == .LEFT {
				mouse_held[.Left] = true
			}

			if e.mouse_button == .RIGHT {
				mouse_held[.Right] = true
			}


		case .MOUSE_UP:
			if e.mouse_button == .LEFT {
				mouse_held[.Left] = false
			}

			if e.mouse_button == .RIGHT {
				mouse_held[.Right] = false
			}

		case .TOUCHES_BEGAN:
			for tidx in 0..<e.num_touches {
				t := e.touches[tidx]
				pos := Vec2 {t.pos_x, t.pos_y}

				if pos.x < sapp.widthf()/2 {
					left_touch_origin = pos
					left_touching = true
				} else {
					right_touch_prev = pos
					right_touching = true
				}
			}

		case .TOUCHES_MOVED:
			for tidx in 0..<e.num_touches {
				t := e.touches[tidx]
				pos := Vec2 {t.pos_x, t.pos_y}

				if pos.x < sapp.widthf()/2 {
					diff := left_touch_origin - pos
					left_touch_offset = diff
				} else {
					diff := pos - right_touch_prev
					right_touch_prev = pos
					right_touch_diff = diff
				}
			}


		case .TOUCHES_ENDED:
			for tidx in 0..<e.num_touches {
				t := e.touches[tidx]
				pos := Vec2 {t.pos_x, t.pos_y}

				if pos.x < sapp.widthf()/2 {
					left_touching = false
				} else {
					right_touching = false
				}
			}
	}
}

input_init :: proc() {
	for &t in key_pressed_time {
		t = -1
	}
}

input_reset :: proc() {
	key_pressed = {}
}