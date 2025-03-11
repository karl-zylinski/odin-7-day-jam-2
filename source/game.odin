package game

import "core:slice"
import "core:math"
import "core:fmt"
import sapp "sokol/app"
import sg "sokol/gfx"
import sglue "sokol/glue"
import slog "sokol/log"
import sshape "sokol/shape"
import tme "core:time"

_ :: fmt

Game_Memory :: struct {
	pip: sg.Pipeline,
	bind: sg.Bindings,
	models: [dynamic]Model,
	objects: [dynamic]Object,
	player: Player,
	fov_offset: f32,
	start: tme.Time,
	debug_free_fly: bool,
	debug_camera: Debug_Camera,
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

@export
game_init :: proc() {
	g = new(Game_Memory)
	g.player.pos = { -3, 0, 3 }

	g.start = tme.now()

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
	add_box(pos = {11, -1, -10}, size = {8, 1, 10},  color = {255, 255, 255, 255})
	add_box(pos = {-5, 0, 0},  size = {1, 10, 50}, color = {255, 255, 255, 255})
	add_box(pos = {5, 0, 0},   size = {1, 5, 5},   color = {255, 200, 255, 255})
	add_box(pos = {-2, -1, -10}, size = {6, 1, 7},   color = {0, 255, 0, 255})
	add_box(pos = {-3, 0, -22},  size = {5, 0.2, 5}, color = {0, 255, 255, 255})

	add_box(pos = {4.5, 2, -12}, size = {10, 5, 1},  color = {255, 255, 255, 255})

	add_box(pos = {0, 0, 50}, size = {50, 1, 80},  color = {255, 230, 230, 255})

	game_hot_reloaded(g)
	input_init()
}

create_pipeline :: proc() {
	sg.destroy_pipeline(g.pip)

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

dt: f32
time: f64

@export
game_frame :: proc() {
	dt = f32(sapp.frame_duration())
	time = tme.duration_seconds(tme.since(g.start))

	if key_pressed[.Debug_Camera] {
		g.debug_free_fly = !g.debug_free_fly
	}

	if g.debug_free_fly {
		debug_camera_update(&g.debug_camera)
	}

	p := &g.player
	player_update(p)

	pass_action := sg.Pass_Action {
		colors = {
			0 = { load_action = .CLEAR, clear_value = { 0.41, 0.68, 0.83, 1 } },
		},
	}

	sg.begin_pass({ action = pass_action, swapchain = sglue.swapchain() })
	sg.apply_pipeline(g.pip)

	view_matrix := create_view_matrix(p.pos + p.eyes_offset, p.yaw, p.pitch, p.roll)
	proj_matrix := create_projection_matrix((70 + g.fov_offset) * math.RAD_PER_DEG, sapp.widthf(), sapp.heightf())

	if g.debug_free_fly {
		c := &g.debug_camera
		view_matrix = create_view_matrix(c.pos, c.yaw, c.pitch, 0)
		proj_matrix = create_projection_matrix(70 * math.RAD_PER_DEG, sapp.widthf(), sapp.heightf())
	}

	for &o in g.objects {
		m := &g.models[o.model]

		g.bind.vertex_buffers[0] = m.vbuf
		g.bind.index_buffer = m.ibuf
		sg.apply_bindings(g.bind)
		model_transf := create_model_matrix(o.pos, o.rot, o.scl)

		mvp := proj_matrix  * view_matrix * model_transf

		vs_params := Vs_Params {
			mvp = mvp,
			model = model_transf,
		}

		fs_params := Fs_Params {
			sun_position = {100, 120, 90},
			model_color = color_normalize(o.color),
		}

		sg.apply_uniforms(UB_vs_params, { ptr = &vs_params, size = size_of(vs_params) })
		sg.apply_uniforms(UB_fs_params, { ptr = &fs_params, size = size_of(fs_params) })
		sg.draw(0, 36, 1)
	}

	debug_draw :: proc(proj_matrix, view_matrix: Mat4, pos: Vec3, size: Vec3, color: Color) {
		model_transf := create_model_matrix(pos, {}, size)

		mvp := proj_matrix * view_matrix * model_transf

		vs_params := Vs_Params {
			mvp = mvp,
			model = model_transf,
		}

		fs_params := Fs_Params {
			sun_position = {100, 120, 0},
			model_color = color_normalize(color),
		}

		sg.apply_uniforms(UB_vs_params, { ptr = &vs_params, size = size_of(vs_params) })
		sg.apply_uniforms(UB_fs_params, { ptr = &fs_params, size = size_of(fs_params) })
		sg.draw(0, 36, 1)
	}

	if g.debug_free_fly {
		g.bind.vertex_buffers[0] = g.models[0].vbuf
		g.bind.index_buffer = g.models[0].ibuf
		sg.apply_bindings(g.bind)
		debug_draw(proj_matrix, view_matrix, p.pos, PLAYER_SIZE, {255, 0, 0, 255})
		debug_draw(proj_matrix, view_matrix, p.pos, PLAYER_FRONT_BACK_COLLIDER_SIZE, {0, 255, 0, 255})
		debug_draw(proj_matrix, view_matrix, p.pos, PLAYER_LEFT_RIGHT_COLLIDER_SIZE, {0, 0, 255, 255})
	}

	sg.end_pass()
	sg.commit()

	free_all(context.temp_allocator)

	input_reset()

	if p.pos.y < -20 {
		game_cleanup()
		game_init()
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
	create_pipeline()
	player_on_load(&g.player)
}

@(export)
game_force_restart :: proc() -> bool {
	return force_reset
}
