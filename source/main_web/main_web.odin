/*
Web build entry point. This code is executed by the javascript in
build/web/index.html (created from source/web/index_template.html).
*/

package main_web

import "core:log"
import "base:runtime"

import game ".."
import sapp "../sokol/app"

main :: proc() {
	// The WASM allocator doesn't work properly in combination with emscripten.
	// This sets up an allocator that uses emscripten's malloc.
	context.allocator = emscripten_allocator()

	// Make temp allocator use new `context.allocator` by re-initing it.
	runtime.init_global_temporary_allocator(1*runtime.Megabyte)

	context.logger = log.create_console_logger(lowest = .Info, opt = {.Level, .Short_File_Path, .Line, .Procedure})
	custom_context = context

	app_desc := game.game_app_default_desc()
	app_desc.init_cb = init
	app_desc.frame_cb = frame
	app_desc.cleanup_cb = cleanup
	app_desc.event_cb = event

	// On web this will not block. Any line after this one will run immediately!
	// Do any on-shutdown stuff in the `cleanup` proc.
	sapp.run(app_desc)
}

custom_context: runtime.Context

init :: proc "c" () {
	context = custom_context
	game.game_init()
}

frame :: proc "c" () {
	context = custom_context
	game.game_frame()
}

event :: proc "c" (e: ^sapp.Event) {
	context = custom_context
	game.game_event(e)
}

// Most web programs will never "quit". The tab will just close. But if you make
// a web program that runs `sapp.quit()`, then this will run.
cleanup :: proc "c" () {
	context = custom_context
	game.game_cleanup()
	log.destroy_console_logger(context.logger)

	// This runs any procedure tagged with `@fini`.
	runtime._cleanup_runtime()
}
