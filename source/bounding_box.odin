package game

Bounding_Box :: struct {
	min: Vec3,
	max: Vec3,
}

bounding_box_from_pos_size :: proc(pos: Vec3, size: Vec3) -> Bounding_Box {
	return {
		pos - size/2,
		pos + size/2,
	}
}

bounding_box_size :: proc(bb: Bounding_Box) -> Vec3 {
	return bb.max - bb.min
}

// Check collision between two boxes
// NOTE: Boxes are defined by two points minimum and maximum
bounding_box_get_overlap :: proc(b1: Bounding_Box, b2: Bounding_Box) -> (res: Bounding_Box, collision: bool) {
	if bounding_box_check_overlap(b1, b2) {
		res.min.x = max(b1.min.x, b2.min.x)
		res.max.x = min(b1.max.x, b2.max.x)
		res.min.y = max(b1.min.y, b2.min.y)
		res.max.y = min(b1.max.y, b2.max.y)
		res.min.z = max(b1.min.z, b2.min.z)
		res.max.z = min(b1.max.z, b2.max.z)
		collision = true
	}

	return
}

bounding_box_check_overlap :: proc(b1: Bounding_Box, b2: Bounding_Box) -> bool {
	collision := true

	if (b1.max.x > b2.min.x) && (b1.min.x < b2.max.x) {
		if (b1.max.y <= b2.min.y) || (b1.min.y >= b2.max.y) {
			collision = false
		}

		if (b1.max.z <= b2.min.z) || (b1.min.z >= b2.max.z) {
			collision = false
		}
	} else {
		collision = false
	}

	return collision
}
