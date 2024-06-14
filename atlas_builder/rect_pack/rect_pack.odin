package rect_pack

// Copyright (c) 2017 Sean Barrett, 2024 Justin Hurstwright
// Permission is hereby granted, free of charge, to any person obtaining a copy of
// this software and associated documentation files (the "Software"), to deal in
// the Software without restriction, including without limitation the rights to
// use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is furnished to do
// so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.


import "core:sort"

PackContext :: struct {
	width:       i32,
	height:      i32,
	alignment:   i32,
	has_init:    bool,
	num_nodes:   i32,
	heuristic:   PackHeuristic,
	active_head: ^Node,
	free_head:   ^Node,
	extra:       [2]Node,
}

MAXVAL :: 0x7fffffff

Node :: struct {
	x, y: Coord,
	next: ^Node,
}
Rect :: struct {
	id:         i32,
	w, h:       Coord,
	x, y:       Coord,
	was_packed: i32,
}

Coord :: i32

PackHeuristic :: enum i32 {
	Skyline_default = 0,
	Skyline_BL_SortHeight = 0,
	Skyline_BF_SortHeight,
}

// Assign packed locations to rectangles. The rectangles are of type
// 'stbrp_rect' defined below, stored in the array 'rects', and there
// are 'num_rects' many of them.
//
// Rectangles which are successfully packed have the 'was_packed' flag
// set to a non-zero value and 'x' and 'y' store the minimum location
// on each axis (i.e. bottom-left in cartesian coordinates, top-left
// if you imagine y increasing downwards). Rectangles which do not fit
// have the 'was_packed' flag set to 0.
//
// You should not try to access the 'rects' array from another thread
// while this function is running, as the function temporarily reorders
// the array while it executes.
//
// To pack into another rectangle, you need to call stbrp_init_target
// again. To continue packing into the same rectangle, you can call
// this function again. Calling this multiple times with multiple rect
// arrays will probably produce worse packing results than calling it
// a single time with the full rectangle array, but the option is
// available.
//
// The function returns 1 if all of the rectangles were successfully
// packed and 0 otherwise.
// TODO: return boolean
pack_rects :: proc(ctx: ^PackContext, rects: []Rect) -> i32 {
	i: i32
	all_rects_packed: i32 = 1

	for i = 0; i < i32(len(rects)); i += 1 {
		rects[i].was_packed = i
	}

	sort.quick_sort_proc(rects[:], rect_height_compare)

	for i = 0; i < i32(len(rects)); i += 1 {
		if rects[i].w == 0 || rects[i].h == 0 {
			rects[i].x = 0
			rects[i].y = 0
		} else {
			result := skyline_pack_rectangle(ctx, rects[i].w, rects[i].h)
			if result.prev_link != nil {
				rects[i].x = cast(Coord)result.x
				rects[i].y = cast(Coord)result.y
			} else {
				rects[i].x = MAXVAL
				rects[i].y = MAXVAL
			}
		}

	}

	sort.quick_sort_proc(rects[:], rect_original_order)

	for i = 0; i < i32(len(rects)); i += 1 {
		rects[i].was_packed = i32(!(rects[i].x == MAXVAL && rects[i].y == MAXVAL))

		if rects[i].was_packed == 0 {
			all_rects_packed = 0
		}
	}

	return all_rects_packed
}

FoundResult :: struct {
	x, y:      i32,
	prev_link: ^^Node,
}

// Initialize a rectangle packer to:
//    pack a rectangle that is 'width' by 'height' in dimensions
//    using temporary storage provided by the array 'nodes', which is 'num_nodes' long
//
// You must call this function every time you start packing into a new target.
//
// There is no "shutdown" function. The 'nodes' memory must stay valid for
// the following stbrp_pack_rects() call (or calls), but can be freed after
// the call (or calls) finish.
//
// Note: to guarantee best results, either:
//       1. make sure 'num_nodes' >= 'width'
//   or  2. call stbrp_allow_out_of_mem() defined below with 'allow_out_of_mem = 1'
//
// If you don't do either of the above things, widths will be quantized to multiples
// of small integers to guarantee the algorithm doesn't run out of temporary storage.
//
// If you do #2, then the non-quantized algorithm will be used, but the algorithm
// may run out of temporary storage and be unable to pack some rectangles.
init_target :: proc(ctx: ^PackContext, width, height: i32, nodes: []Node) {
	i: int

	for i = 0; i < len(nodes) - 1; i += 1 {
		nodes[i].next = &nodes[i + 1]
	}
	nodes[i].next = nil
	ctx.has_init = true
	ctx.heuristic = .Skyline_default
	ctx.free_head = &nodes[0]
	ctx.active_head = &ctx.extra[0]
	ctx.num_nodes = cast(i32)len(nodes)
	ctx.width = width
	ctx.height = height
	setup_allow_out_of_mem(ctx, false)

	ctx.extra[0].x = 0
	ctx.extra[0].y = 0
	ctx.extra[0].next = &ctx.extra[1]
	ctx.extra[1].x = width
	ctx.extra[1].y = 1 << 30
	ctx.extra[1].next = nil
}

// Optionally call this function after init but before doing any packing to
// change the handling of the out-of-temp-memory scenario, described above.
// If you call init again, this will be reset to the default (false).
setup_allow_out_of_mem :: proc(ctx: ^PackContext, allow_oom: bool) {
	if allow_oom {
		ctx.alignment = 1
	} else {
		ctx.alignment = (ctx.width + ctx.num_nodes - 1) / ctx.num_nodes
	}
}

// Optionally select which packing heuristic the library should use. Different
// heuristics will produce better/worse results for different data sets.
// If you call init again, this will be reset to the default.
setup_heuristic :: proc(ctx: ^PackContext, heuristic: PackHeuristic) {
	ctx.heuristic = heuristic
}

@(private = "file")
skyline_pack_rectangle :: proc(ctx: ^PackContext, width, height: i32) -> (res: FoundResult) {
	res = skyline_find_best_pos(ctx, width, height)
	node: ^Node
	cur: ^Node
	//    1. it failed
	if (res.prev_link == nil) {
		res.prev_link = nil
		return
	}
	//    2. the best node doesn't fit (we don't always check this)
	if (res.y + height > ctx.height) {
		res.prev_link = nil
		return
	}
	//    3. we're out of memory
	if (ctx.free_head == nil) {
		res.prev_link = nil
		return
	}

	// Point the code for at free head
	node = ctx.free_head
	node.x = Coord(res.x)
	node.y = Coord(res.y + height)

	ctx.free_head = node.next


	cur = res.prev_link^
	if cur.x < res.x {
		next := cur.next
		cur.next = node
		cur = next
	} else {
		res.prev_link^ = node
	}

	for cur.next != nil && cur.next.x <= res.x + width {
		next := cur.next
		cur.next = ctx.free_head
		ctx.free_head = cur
		cur = next
	}
	node.next = cur
	if cur.x < res.x + width {
		cur.x = Coord(res.x + width)
	}

	return
}

@(private = "file")
skyline_find_best_pos :: proc(ctx: ^PackContext, in_width, height: i32) -> (res: FoundResult) {
	best_waste: i32 = 1 << 30
	best_x: i32 = best_waste
	best_y: i32 = best_waste

	prev: ^^Node
	best: ^^Node

	node: ^Node
	tail: ^Node

	width := in_width + ctx.alignment - 1
	width -= width % ctx.alignment

	// TODO: Return Error
	if width > ctx.width || height > ctx.height {
		return
	}

	node = ctx.active_head
	prev = &ctx.active_head

	for node.x + width <= ctx.width {
		waste: i32
		y := skyline_find_min_y(ctx, node, node.x, width, &waste)
		if ctx.heuristic == .Skyline_BL_SortHeight {
			if y < best_y {
				best_y = y
				best = prev
			}
		} else {
			if y + height <= ctx.height {
				if (y < best_y || (y == best_y && waste < best_waste)) {
					best_y = y
					best_waste = waste
					best = prev
				}
			}
		}
		prev = &node.next
		node = node.next
	}
	best_x = best == nil ? 0 : (best^).x

	if ctx.heuristic == .Skyline_BF_SortHeight {
		tail = ctx.active_head
		node = ctx.active_head
		prev = &ctx.active_head

		for tail.x < width {
			tail = tail.next
		}
		for tail != nil {
			xpos: i32 = tail.x - width
			y: i32
			waste: i32

			for node.next.x <= xpos {
				y := skyline_find_min_y(ctx, node, xpos, width, &waste)
				if y + height <= ctx.height {
					if y <= best_y {
						if y < best_y ||
						   waste < best_waste ||
						   (waste == best_waste && xpos < best_x) {
							best_x = xpos
							assert(y <= best_y)
							best_y = y
							best_waste = waste
							best = prev
						}
					}
				}
			}


			tail = tail.next
		}
	}


	res.prev_link = best
	res.x = best_x
	res.y = best_y
	return
}

// TODO:: Return the waste instead
@(private = "file")
skyline_find_min_y :: proc(ctx: ^PackContext, first: ^Node, x0, width: i32, pwaste: ^i32) -> i32 {
	node: ^Node = first
	x1: i32 = x0 + width
	min_y: i32
	visited_width: i32
	waste_area: i32

	assert(first.x <= x0)
	assert(node.next.x > x0)

	for node.x < x1 {
		if node.y > min_y {
			// raise min_y higher.
			// we've accounted for all waste up to min_y,
			// but we'll now add more waste for everything we've visted
			waste_area += visited_width * (node.y - min_y)
			min_y = node.y

			if node.x < x0 {
				visited_width += node.next.x - x0
			} else {
				visited_width += node.next.x - node.x
			}
		} else {
			under_width := node.next.x - node.x
			if under_width + visited_width > width {
				under_width = width - visited_width
			}
			waste_area += under_width * (min_y - node.y)
			visited_width += under_width
		}
		node = node.next
	}

	pwaste^ = waste_area


	return min_y
}

@(private = "file")
rect_height_compare :: proc(a, b: Rect) -> int {
	if a.h > b.h {
		return -1
	}
	if a.h < b.h {
		return 1
	}
	if a.w > b.w {
		return -1
	}
	if a.w < b.w {
		return 1
	}
	return 0
}

@(private = "file")
rect_original_order :: proc(a, b: Rect) -> int {
	if (a.was_packed < b.was_packed) {
		return -1
	}
	if (a.was_packed > b.was_packed) {
		return 1
	}
	return 0
}
