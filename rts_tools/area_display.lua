-- RTS tools mod for minetest
-- Copyright (c) 2015 est31 <MTest31@outlook.com>
-- License: LGPL v2.1+

local rtsp = ...


-- Initial version of the entity and node definitions for the display
-- copied from TenPlus1's WTFPL licensed "Protector" mod

minetest.register_entity("rts_tools:area_display", {
	physical = false,
	collisionbox = {0, 0, 0, 0, 0, 0},
	visual = "wielditem",
	visual_size = {x = 1.0 / 1.5, y = 1.0 / 1.5}, -- wielditem seems to be scaled to 1.5 times original node size
	textures = {"rts_tools:area_display_helper_node_??"}, -- to be replaced later with actual node name
	on_step = function(self, dtime)
		self.timer = (self.timer or 0) + dtime
		if self.timer > 10 then
			self.object:remove()
		end
	end,
})

rtsp.registered_area_displays = {}

-- Registers (or retrieves) an area display with the given radius
function rtstools.register_area_display(radius)
	assert(type(radius) == "number")

	if rtsp.registered_area_displays[radius] then
		return rtsp.registered_area_displays[radius]
	end

	local r = radius -- shorter name :)

	-- Helper node for the area display
	-- it provides the texture for the area display entity
	minetest.register_node(":rts_tools:area_display_helper_node_" .. radius, {
		tiles = {"protector_display.png"},
		use_texture_alpha = true,
		walkable = false,
		drawtype = "nodebox",
		node_box = {
			type = "fixed",
			fixed = {
				-- sides
				{-(r + .55), -(r + .55), -(r + .55), -(r + .45),  (r + .55),  (r + .55)},
				{-(r + .55), -(r + .55),  (r + .45),  (r + .55),  (r + .55),  (r + .55)},
				{ (r + .45), -(r + .55), -(r + .55),  (r + .55),  (r + .55),  (r + .55)},
				{-(r + .55), -(r + .55), -(r + .55),  (r + .55),  (r + .55), -(r + .45)},
				-- top
				{-(r + .55),  (r + .45), -(r + .55),  (r + .55),  (r + .55),  (r + .55)},
				-- bottom
				{-(r + .55), -(r + .55), -(r + .55),  (r + .55), -(r + .45),  (r + .55)},
				-- middle (surrounding the management node)
				{-.55, -.55, -.55, .55, .55, .55},
			},
		},
		selection_box = {
			type = "regular",
		},
		paramtype = "light",
		groups = {dig_immediate = 3, not_in_creative_inventory = 1},
		drop = "",
	})

	local ret = {
		spawn = function(pos)
			minetest.registered_entities["rts_tools:area_display"].textures =
				{"rts_tools:area_display_helper_node_" .. radius}
			local entity = minetest.add_entity(pos, "rts_tools:area_display")
			assert(entity) -- ensure we could spawn the entity
			return entity
		end,
	}
	rtsp.registered_area_displays[radius] = ret
	return ret
end
