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
import la "core:math/linalg"

_ :: fmt

Game_Memory :: struct {
	objects: [dynamic]Object,
	player: Player,
	fov_offset: f32,
	start: tme.Time,
	debug_free_fly: bool,
	debug_camera: Debug_Camera,
	default_drawer: Default_Drawer,
	shadowcaster: Shadowcaster_Drawer,
	quad_drawer: Quad_Drawer,
	sun_position: Vec3,
}

Default_Drawer :: struct {
	pip: sg.Pipeline,
	bind: sg.Bindings,
}

Quad_Drawer :: struct {
	pip: sg.Pipeline,
	bind: sg.Bindings,
}

Shadowcaster_Drawer :: struct {
	image: sg.Image,
	depth: sg.Image,
	attachments: sg.Attachments,
	pass_action: sg.Pass_Action,
	pip: sg.Pipeline,
	bind: sg.Bindings,
}

g: ^Game_Memory

Object :: struct {
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


	add_box(pos = {0, -1, 0},  size = {10, 1, 10}, color = {255, 255, 255, 255})
	add_box(pos = {11, -1, -10}, size = {8, 1, 10},  color = {255, 255, 255, 255})
	add_box(pos = {-5, 0, 0},  size = {1, 10, 50}, color = {255, 255, 255, 255})
	add_box(pos = {0, 0, 0},   size = {1, 5, 5},   color = {255, 200, 255, 255})
	add_box(pos = {-2, -1, -10}, size = {6, 1, 7},   color = {0, 255, 0, 255})
	add_box(pos = {-3, 0, -22},  size = {5, 0.2, 5}, color = {0, 255, 255, 255})

	add_box(pos = {4.5, 2, -12}, size = {10, 5, 1},  color = {255, 255, 255, 255})

	add_box(pos = {0, 0, 50}, size = {50, 1, 80},  color = {255, 230, 230, 255})

	add_box(pos = {0, 0, 50}, size = {1, 10, 1},  color = {255, 0, 230, 255})


	g.shadowcaster.image = sg.make_image({
		render_target = true,
		width = 4096,
		height = 4096,
		pixel_format = .RGBA8,
		sample_count = 1,
	})

	g.shadowcaster.depth = sg.make_image({
		render_target = true,
		width = 4096,
		height = 4096,
		pixel_format = .DEPTH,
		sample_count = 1,
	})

	g.shadowcaster.attachments = sg.make_attachments({
		colors = {
			0 = { image = g.shadowcaster.image },
		},
		depth_stencil = { image = g.shadowcaster.depth },
	})

	g.shadowcaster.pass_action = {
		colors = {
			0 = { load_action = .CLEAR, clear_value = { 1, 1, 1, 1 } },
		},
	}

	g.default_drawer.bind.vertex_buffers[0] = sg.make_buffer(sshape.vertex_buffer_desc(box_buf))
	g.default_drawer.bind.index_buffer = sg.make_buffer(sshape.index_buffer_desc(box_buf))
	g.default_drawer.bind.samplers[SMP_smp_shadow_map] = sg.make_sampler({
		wrap_u = .CLAMP_TO_BORDER,
		wrap_v = .CLAMP_TO_BORDER,
		border_color = .OPAQUE_WHITE,
	})
	g.default_drawer.bind.images[IMG_tex_shadow_map] = g.shadowcaster.image
	g.shadowcaster.bind.vertex_buffers = g.default_drawer.bind.vertex_buffers
	g.shadowcaster.bind.index_buffer = g.default_drawer.bind.index_buffer

	quad_vertices := [?]f32 {
		-1,   1,   0,     0, 0,
		-0.5, 1,   0,     1, 0,
		-0.5, 0.5, 0,     1, 1,
		-1,   0.5, 0,     0, 1,
	}

	quad_indices := [?]u16 {
		0, 1, 2,
		0, 2, 3,
	}
	
	g.quad_drawer = {
		bind = {
			vertex_buffers = {
				0 = sg.make_buffer({
					data = { ptr = &quad_vertices, size = size_of(quad_vertices) },
				}),
			},
			index_buffer = sg.make_buffer({
				type = .INDEXBUFFER,
				data = { ptr = &quad_indices, size = size_of(quad_indices) },
			}),
			samplers = {
				SMP_smp = sg.make_sampler({}),
			},
			images = {
				IMG_tex = g.shadowcaster.image,
			},
		},
	}

	game_hot_reloaded(g)
	input_init()
}

refresh_pipelines :: proc() {
	sg.destroy_pipeline(g.default_drawer.pip)

	g.default_drawer.pip = sg.make_pipeline({
		shader = sg.make_shader(default_lighting_shader_desc(sg.query_backend())),
		layout = {
			attrs = {
				ATTR_default_lighting_pos      = sshape.position_vertex_attr_state(),
				ATTR_default_lighting_normal   = sshape.normal_vertex_attr_state(),
				ATTR_default_lighting_texcoord = sshape.texcoord_vertex_attr_state(),
				ATTR_default_lighting_color0   = sshape.color_vertex_attr_state(),
			},
		},
		index_type = .UINT16,
		cull_mode = .BACK,
		depth = {
			compare = .LESS_EQUAL,
			write_enabled = true,
		},
	})


	sg.destroy_pipeline(g.shadowcaster.pip)

	g.shadowcaster.pip = sg.make_pipeline({
		shader = sg.make_shader(shadowcaster_shader_desc(sg.query_backend())),
		layout = {
			attrs = {
				ATTR_shadowcaster_pos      = sshape.position_vertex_attr_state(),
				ATTR_shadowcaster_normal   = sshape.normal_vertex_attr_state(),
				ATTR_shadowcaster_texcoord = sshape.texcoord_vertex_attr_state(),
				ATTR_shadowcaster_color0   = sshape.color_vertex_attr_state(),
			},
		},
		index_type = .UINT16,
		cull_mode = .BACK,
		sample_count = 1,
		depth = {
			pixel_format = .DEPTH,
			compare = .LESS_EQUAL,
			write_enabled = true,
		},
		colors = {
			0 = { pixel_format = .RGBA8 },
		},
	})

	sg.destroy_pipeline(g.quad_drawer.pip)

	g.quad_drawer.pip = sg.make_pipeline({
		shader = sg.make_shader(quad_textured_shader_desc(sg.query_backend())),
		index_type = .UINT16,
		layout = {
			attrs = {
				ATTR_quad_textured_position = { format = .FLOAT3 },
				ATTR_quad_textured_texcoord0 = { format = .FLOAT2 },
			},
		},
	})
}

add_box :: proc(pos: Vec3, size: Vec3, color: Color) {
	append(&g.objects, Object {
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

	SUN_SPEED :: 0
	g.sun_position = {100, 120, 75}

	if key_pressed[.Debug_Camera] {
		g.debug_free_fly = !g.debug_free_fly
	}

	if g.debug_free_fly {
		debug_camera_update(&g.debug_camera)
	}

	p := &g.player
	player_update(p)

	sg.begin_pass({ action = g.shadowcaster.pass_action, attachments = g.shadowcaster.attachments })
	sg.apply_pipeline(g.shadowcaster.pip)
	sun_view := sun_shadowcaster_view_matrix()
	sun_proj := sun_shadowcaster_proj_matrix()
	draw_world_shadowcaster(sun_view, sun_proj)
	sg.end_pass()

	sun_vp := sun_proj * sun_view

	pass_action := sg.Pass_Action {
		colors = {
			0 = { load_action = .CLEAR, clear_value = { 0.7, 0.69, 0.9, 1 } },
		},
	}

	sg.begin_pass({ action = pass_action, swapchain = sglue.swapchain() })
	sg.apply_pipeline(g.default_drawer.pip)

	view_matrix := create_view_matrix(p.pos + p.eyes_offset, p.yaw, p.pitch, p.roll)
	proj_matrix := create_projection_matrix((70 + g.fov_offset) * math.RAD_PER_DEG, sapp.widthf(), sapp.heightf())

	if g.debug_free_fly {
		c := &g.debug_camera
		view_matrix = create_view_matrix(c.pos, c.yaw, c.pitch, 0)
		proj_matrix = create_projection_matrix(70 * math.RAD_PER_DEG, sapp.widthf(), sapp.heightf())
	}

	//draw_world(sun_view, sun_proj, sun_vp)
	draw_world(view_matrix, proj_matrix, sun_vp)

	debug_draw :: proc(proj_matrix, view_matrix: Mat4, pos: Vec3, size: Vec3, color: Color) {
		model_transf := create_model_matrix(pos, {}, size)

		mvp := proj_matrix * view_matrix * model_transf

		vs_params := Vs_Params {
			mvp = mvp,
			model = model_transf,
		}

		fs_params := Fs_Params {
			sun_position = g.sun_position,
			model_color = color_normalize(color),
		}

		sg.apply_uniforms(UB_vs_params, { ptr = &vs_params, size = size_of(vs_params) })
		sg.apply_uniforms(UB_fs_params, { ptr = &fs_params, size = size_of(fs_params) })
		sg.draw(0, 36, 1)
	}

	if g.debug_free_fly {
		sg.apply_bindings(g.default_drawer.bind)
		debug_draw(proj_matrix, view_matrix, p.pos, PLAYER_SIZE, {255, 0, 0, 255})
		debug_draw(proj_matrix, view_matrix, p.pos, PLAYER_FRONT_BACK_COLLIDER_SIZE, {0, 255, 0, 255})
		debug_draw(proj_matrix, view_matrix, p.pos, PLAYER_LEFT_RIGHT_COLLIDER_SIZE, {0, 0, 255, 255})
	}

	if g.debug_free_fly {
	sg.apply_pipeline(g.quad_drawer.pip)
		sg.apply_bindings(g.quad_drawer.bind)
		sg.draw(0, 6, 1)
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

sun_shadowcaster_view_matrix :: proc() -> Mat4 {
	return la.matrix4_look_at(g.sun_position, g.player.pos, Vec3{0, 1, 0})
}

sun_shadowcaster_proj_matrix :: proc() -> Mat4 {
	return la.matrix4_infinite_perspective(f32(20)*math.RAD_PER_DEG, 1, 10)
}

draw_world :: proc(view_matrix, proj_matrix, shadowcaster_vp: Mat4) {
	g.default_drawer.bind.images[IMG_tex_shadow_map] = g.shadowcaster.image

	for &o in g.objects {
		sg.apply_bindings(g.default_drawer.bind)
		model_transf := create_model_matrix(o.pos, o.rot, o.scl)

		mvp := proj_matrix * view_matrix * model_transf

		vs_params := Vs_Params {
			mvp = mvp,
			model = model_transf,
		}

		fs_params := Fs_Params {
			sun_position = g.sun_position,
			model_color = color_normalize(o.color),
			shadowcaster_vp = shadowcaster_vp,
			camera_pos = g.player.pos,
		}

		sg.apply_uniforms(UB_vs_params, { ptr = &vs_params, size = size_of(vs_params) })
		sg.apply_uniforms(UB_fs_params, { ptr = &fs_params, size = size_of(fs_params) })
		sg.draw(0, 36, 1)
	}
}


draw_world_shadowcaster :: proc(view_matrix, proj_matrix: Mat4) {
	for &o in g.objects {
		sg.apply_bindings(g.shadowcaster.bind)
		model_transf := create_model_matrix(o.pos, o.rot, o.scl)

		mvp := proj_matrix  * view_matrix * model_transf

		vs_params := Shadowcaster_Vs_Params {
			mvp = mvp,
		}

		sg.apply_uniforms(UB_shadowcaster_vs_params, { ptr = &vs_params, size = size_of(vs_params) })
		sg.draw(0, 36, 1)
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
	refresh_pipelines()
	player_on_load(&g.player)
}

@(export)
game_force_restart :: proc() -> bool {
	return force_reset
}
