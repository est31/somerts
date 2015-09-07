-- RTS tools mod for minetest
-- Copyright (c) 2015 est31 <MTest31@outlook.com>
-- License: LGPL v2.1+

local rtsp = ...


-- Initial version of the entity and node definitions for the display
-- copied from TenPlus1's WTFPL licensed "Protector" mod

minetest.register_entity("rts_tools:area_display", {
	display_data = {
		lifetime = 10,
	},

	physical = false,
	collisionbox = {0, 0, 0, 0, 0, 0},
	visual = "wielditem",
	visual_size = {x = 1.0 / 1.5, y = 1.0 / 1.5}, -- wielditem seems to be scaled to 1.5 times original node size
	textures = {"rts_tools:area_display_helper_node_??"}, -- to be replaced later with actual node name

	on_activate = function(self, staticdata)
		if staticdata ~= "" then
			self.display_data = minetest.deserialize(staticdata)
			self:update_radius()
		end
	end,

	set_display_data = function(self, display_data)
		self.display_data = display_data
		self:update_radius()
	end,

	update_radius = function(self)
		self.object:set_properties({
			textures = { "rts_tools:area_display_helper_node_"
				.. self.display_data.boxdef_idf }
		})
	end,

	on_step = function(self, dtime)
		local display_data = self.display_data
		if display_data.lifetime then
			display_data.lifetime = display_data.lifetime - dtime
			if display_data.lifetime < 0 then
				self.object:remove()
			end
		end
	end,

	get_staticdata = function(self)
		return minetest.serialize(self.display_data)
	end,
})

rtsp.registered_area_displays = {}

local function boxdef_to_identifier(boxdef)
	if type(boxdef) == "number" then
		return tostring(boxdef)
	else
		local a = math.abs
		return a(boxdef.min.x) .. "_" .. a(boxdef.min.y) .. "_" .. a(boxdef.min.z) .. "_"
			.. a(boxdef.max.x) .. "_" .. a(boxdef.max.y) .. "_" .. a(boxdef.max.z)
	end
end

local function assert_valid_boxdef(boxdef)
	if type(boxdef) == "number" then
		return
	elseif type(boxdef) == "table" then
		assert(boxdef.min.x <= 0)
		assert(boxdef.min.y <= 0)
		assert(boxdef.min.z <= 0)
		assert(boxdef.max.x >= 0)
		assert(boxdef.max.y >= 0)
		assert(boxdef.max.z >= 0)
		return
	end
	assert(false)
end

-- Registers (or retrieves) an area display with the given radius
function rtstools.register_area_display(boxdef)
	assert_valid_boxdef(boxdef)

	local idf = boxdef_to_identifier(boxdef)

	if rtsp.registered_area_displays[idf] then
		return rtsp.registered_area_displays[idf]
	end

	local minp, maxp
	if type(boxdef) == "table" then
		minp = boxdef.min
		maxp = boxdef.max
	else
		local r = boxdef -- shorter name :)
		minp = {x = -r, y = -r, z = -r}
		maxp = {x = r, y = r, z = r}
	end


	-- Helper node for the area display
	-- it provides the texture for the area display entity
	minetest.register_node(":rts_tools:area_display_helper_node_" .. idf, {
		tiles = {"protector_display.png"},
		use_texture_alpha = true,
		walkable = false,
		drawtype = "nodebox",
		node_box = {
			type = "fixed",
			fixed = {
				-- sides
				{(minp.x + .55), (minp.y + .55), (minp.z + .55), (minp.z + .45), (maxp.y + .55), (maxp.z + .55)},
				{(minp.x + .55), (minp.y + .55), (maxp.z + .45), (maxp.z + .55), (maxp.y + .55), (maxp.z + .55)},
				{(maxp.x + .45), (minp.y + .55), (minp.z + .55), (maxp.z + .55), (maxp.y + .55), (maxp.z + .55)},
				{(minp.x + .55), (minp.y + .55), (minp.z + .55), (maxp.z + .55), (maxp.y + .55), (minp.z + .45)},
				-- top
				{(minp.x + .55), (maxp.y + .45), (minp.z + .55), (maxp.x + .55), (maxp.y + .55), (maxp.z + .55)},
				-- bottom
				{(minp.x + .55), (minp.y + .55), (minp.z + .55), (maxp.x + .55), (minp.y + .45), (maxp.z + .55)},
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
		spawn = function(pos, lifetime)
			local entity = minetest.add_entity(pos, "rts_tools:area_display")
			assert(entity) -- ensure we could spawn the entity
			entity:get_luaentity():set_display_data({ lifetime = lifetime, boxdef_idf = idf })
			return entity
		end,
	}
	rtsp.registered_area_displays[idf] = ret
	return ret
end
