package game

import "core:math/linalg"
import "core:slice"
import "core:math"
import "core:fmt"
import "core:math/ease"
import sapp "sokol/app"
import sg "sokol/gfx"
import sglue "sokol/glue"
import slog "sokol/log"
import sshape "sokol/shape"

Game_Memory :: struct {
	pip: sg.Pipeline,
	bind: sg.Bindings,
	models: [dynamic]Model,
	objects: [dynamic]Object,
	player: Player,
	touch_prev: Vec2,
	touching: bool,
	fov_offset: f32,
	time: f64,
}

Player :: struct {
	yaw: f32,
	pitch: f32,
	roll: f32,
	pos: Vec3,
	vel: Vec3,
	jumping: bool,
	roll_easer: Easer(Strafe_State),
	fov_easer: Easer(Run_State),
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

g: ^Game_Memory

Object :: struct {
	model: int,
	pos: Vec3,
	rot: Vec3,
	scl: Vec3,
	color: Color,
	collider: Maybe(Bounding_Box),
}

@export
game_app_default_desc :: proc() -> sapp.Desc {
	return {
		width = 1920,
		height = 1080,
		sample_count = 4,
		window_title = "Odin + Sokol hot reload template",
		icon = { sokol_default = true },
		logger = { func = slog.func },
		html5_update_document_title = true,
		high_dpi = true,
	}
}

create_easers :: proc() {
	g.player.roll_easer = {
		end_values = {
			.None = 0,
			.Left = -0.015,
			.Right = 0.015,
		},
		duration = 0.3,
		ease = proc(t: f32) -> f32 {
			return 1 - (1 - t) * (1 - t)
		}
	}

	g.player.fov_easer = {
		end_values = {
			.Still = 0,
			.Running = 10,
		},
		duration = 0.4,
		ease = proc(t: f32) -> f32 {
			return 1 - (1 - t) * (1 - t) * (1 - t) * (1 - t)
		},
	}
}

@export
game_init :: proc() {
	g = new(Game_Memory)
	game_hot_reloaded(g)

	sg.setup({
		environment = sglue.environment(),
		logger = { func = slog.func },
	})

	box_sizes := sshape.box_sizes(1)
	box_vertices := make([]sshape.Vertex, box_sizes.vertices.num, context.temp_allocator)
	box_indices := make([]u16, box_sizes.indices.num, context.temp_allocator)

	box_buf := sshape.Buffer {
		vertices = { buffer = { ptr = raw_data(box_vertices), size = uint(slice.size(box_vertices)) } },
		indices  = { buffer = { ptr = raw_data(box_indices), size = uint(slice.size(box_indices)) } },
	}

	box_buf = sshape.build_box(box_buf, {
		width = 1,
		depth = 1,
		height = 1,
 		tiles = 1,
 		random_colors = true,
	})

	append(&g.models, Model {
		vbuf = sg.make_buffer(sshape.vertex_buffer_desc(box_buf)),
		ibuf = sg.make_buffer(sshape.index_buffer_desc(box_buf)),
	})

	add_box(pos = {0, -1, 0},  size = {10, 1, 10}, color = {255, 255, 255, 255})
	add_box(pos = {5, -1, 10}, size = {3, 1, 10}, color = {255, 255, 255, 255})
	add_box(pos = {-5, 0, 0},  size = {1, 10, 50}, color = {255, 255, 255, 255})
	add_box(pos = {5, 0, 0},   size = {1, 5, 5},   color = {255, 255, 0, 255})
	add_box(pos = {0, -1, 10}, size = {5, 1, 5},   color = {0, 255, 0, 255})
	add_box(pos = {0, 0, 15},  size = {5, 0.2, 5}, color = {0, 255, 255, 255})

	g.pip = sg.make_pipeline({
		shader = sg.make_shader(texcube_shader_desc(sg.query_backend())),
		layout = {
			attrs = {
				ATTR_texcube_pos      = sshape.position_vertex_attr_state(),
                ATTR_texcube_normal   = sshape.normal_vertex_attr_state(),
                ATTR_texcube_texcoord = sshape.texcoord_vertex_attr_state(),
                ATTR_texcube_color0   = sshape.color_vertex_attr_state(),
			},
		},
		index_type = .UINT16,
		cull_mode = .BACK,
		depth = {
			compare = .LESS_EQUAL,
			write_enabled = true,
		},
	})
}

add_box :: proc(pos: Vec3, size: Vec3, color: Color) {
	append(&g.objects, Object {
		model = 0,
		pos = pos,
		scl = size,
		color = color,
		collider = bounding_box_from_pos_size(pos, size),
	})
}

@export
game_frame :: proc() {
	dt := f32(sapp.frame_duration())
	g.time += sapp.frame_duration()

	p := &g.player
	p.vel += {0, -9.82, 0} * dt

	movement: Vec3
	
	if key_held[.Forward] {
		movement.z += 1
		easer_set_state(&p.fov_easer, Run_State.Running)
	} else {
		easer_set_state(&p.fov_easer, Run_State.Still)
	}

	g.fov_offset = easer_update(&p.fov_easer, dt)
	
	if key_held[.Backward] {
		movement.z -= 1
	}

	if key_held[.Left] {
		movement.x += 1
		easer_set_state(&p.roll_easer, Strafe_State.Left)
	}

	if key_held[.Right] {
		movement.x -= 1
		easer_set_state(&p.roll_easer, Strafe_State.Right)
	}

	if movement.x == 0 {
		easer_set_state(&p.roll_easer, Strafe_State.None)
	}

	p.roll = easer_update(&p.roll_easer, dt)

	rot := linalg.matrix4_from_yaw_pitch_roll_f32(p.yaw * math.TAU, p.pitch * math.TAU, 0)
	p.vel.xz = linalg.mul(rot, vec4_point(linalg.normalize0(movement)*dt*600)).xz
	
	if sapp.mouse_locked() || g.touching {
		p.yaw -= mouse_move.x * dt * 0.05
		p.pitch += mouse_move.y * dt * 0.05

		p.pitch = clamp(p.pitch, -0.1, 0.2)
	} else if mouse_held[.Left] {
		sapp.lock_mouse(true)
	}

	mouse_move = {}

	pass_action := sg.Pass_Action {
		colors = {
			0 = { load_action = .CLEAR, clear_value = { 0.41, 0.68, 0.83, 1 } },
		},
}

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

	if key_held[.Jump] && grounded {
		p.vel.y = 4
	}

	sg.begin_pass({ action = pass_action, swapchain = sglue.swapchain() })
	sg.apply_pipeline(g.pip)

	for &o in g.objects {
		m := &g.models[o.model]

		g.bind.vertex_buffers[0] = m.vbuf
		g.bind.index_buffer = m.ibuf
		sg.apply_bindings(g.bind)
		model_transf := create_model_matrix(o.pos, o.rot, o.scl)

		view_matrix := create_view_matrix(p.pos, p.yaw, p.pitch, p.roll)
		mvp := create_projection_matrix((60 + g.fov_offset)  * math.RAD_PER_DEG, sapp.widthf(), sapp.heightf()) * view_matrix * model_transf

		vs_params := Vs_Params {
			mvp = mvp,
			model = model_transf,
		}

		fs_params := Fs_Params {
			sun = {f32(math.cos(g.time)*2)*1, 3, f32(math.sin(g.time)*5)*2},
			model_color = color_normalize(o.color),
		}

		sg.apply_uniforms(UB_vs_params, { ptr = &vs_params, size = size_of(vs_params) })
		sg.apply_uniforms(UB_fs_params, { ptr = &fs_params, size = size_of(fs_params) })
		sg.draw(0, 36, 1)
	}

	sg.end_pass()
	sg.commit()

	free_all(context.temp_allocator)
}

PLAYER_SIZE :: Vec3 { 0.4, 1.8, 0.4 }

player_bounding_box :: proc() -> Bounding_Box {
	return {
		min = g.player.pos - PLAYER_SIZE*0.5,
		max = g.player.pos + PLAYER_SIZE*0.5,
	}
}

force_reset: bool

@export
game_event :: proc(e: ^sapp.Event) {
	process_input(e)
}

@export
game_cleanup :: proc() {
	sg.shutdown()

	delete(g.models)
	delete(g.objects)

	free(g)
}

@(export)
game_memory :: proc() -> rawptr {
	return g
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g = (^Game_Memory)(mem)

	create_easers()
}

@(export)
game_force_restart :: proc() -> bool {
	return force_reset
}
