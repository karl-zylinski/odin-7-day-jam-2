package game

import "core:math"

Easer :: struct($State_Type: typeid) {
	targets: [State_Type]f32,
	durations: [State_Type]f32,
	start: f32,
	cur: f32,
	timer: f32,
	state: State_Type,
	ease: proc(f32) -> f32,
}

easer_set_state :: proc(e: ^Easer($State_Type), s: State_Type) {
	if e.state == s {
		return
	}

	e.state = s
	e.timer = 0
	e.start = e.cur
}

easer_update :: proc(e: ^Easer($State_Type), dt: f32) -> f32{
	e.timer += dt
	target := e.targets[e.state]
	duration := e.durations[e.state]
	t := clamp(e.timer/duration, 0, 1)

	if e.ease != nil {
		t = e.ease(t)
	}

	e.cur = math.lerp(e.start, target, t)
	return e.cur
}

// easings

smoothstop2 :: proc(t: f32) -> f32 {
	return 1 - (1 - t) * (1 - t)
}