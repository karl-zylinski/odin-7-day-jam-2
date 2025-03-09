package game

Color :: [4]u8

color_normalize :: proc(c: Color) -> [4]f32 {
	return {
		f32(c.r)/255.0,
		f32(c.g)/255.0,
		f32(c.b)/255.0,
		f32(c.a)/255.0,
	}
}
