-- RTS tools mod for minetest
-- Copyright (c) 2015 est31 <MTest31@outlook.com>
-- License: LGPL v2.1+

local rtsp = ...

--------------------------------------------------------------
-- Local helper functions
--------------------------------------------------------------

local function get_edges_around_pos(pos, radius)
	return {
		x = pos.x - radius,
		y = pos.y - radius,
		z = pos.z - radius,
	}, {
		x = pos.x + radius,
		y = pos.y + radius,
		z = pos.z + radius,
	}
end

--------------------------------------------------------------
-- Building state helpers
--------------------------------------------------------------

rtstools.building_state = {
	BUILDING = 1,
	BUILT = 2,
}
rtstools.building_state_names = {
	"building",
	"built",
}

local function building_built()

end

--------------------------------------------------------------
-- Loaded buildings management
--------------------------------------------------------------

local astore = AreaStore()
local loaded_buildings = {}

local loaded_buildings_path = minetest.get_worldpath() .. "/rts_buildings.dat"

local function load_buildings_from_file()
	local f = io.open(loaded_buildings_path, "r")
	if f then
		local b = f:read("*all")
		loaded_buildings = {}
		for bid, building in pairs(minetest.deserialize(b)) do
			local def = rtsp.buildings[building.bld]
			local minp, maxp = get_edges_around_pos(building.pos, def.radius)
			local id = astore:insert_area(minp, maxp, '')
			assert(id)
			loaded_buildings[id] = {
				pos = building.pos,
				crit_states = {},
				state = building.state,
				bld = def,
			}
		end
		f:close()
	end
end


local function save_buildings_to_file()
	local f = io.open(loaded_buildings_path, "w")
	if f then
		local saved_b = {}
		for id, building in pairs(loaded_buildings) do
			saved_b[id] = {
				bld = building.bld.t_name,
				pos = building.pos,
				state = building.state,
			}
		end
		f:write(minetest.serialize(saved_b))
		f:close()
	end
end

minetest.after(.1, load_buildings_from_file)

minetest.register_on_shutdown(save_buildings_to_file)
-- TODO save them in regular intervals too, to not have problems when mt crashes

-- returns nil if there is no building
function rtstools.can_place_building_at_pos(pos, radius)
	local minp, maxp = get_edges_around_pos(pos, radius)
	for id, area in pairs(astore:get_areas_in_area(minp, maxp, true, false, false)) do
		return false
	end
	return true
end

function rtstools.get_buildings_overlapping_area(pos, radius)
	local minp, maxp = get_edges_around_pos(pos, radius)
	local ret = {}
	for id in pairs(astore:get_areas_in_area(minp, maxp, true, false, false)) do
		ret[id] = loaded_buildings[id]
	end
	return ret
end

-- returns nil if there is no building
function rtstools.get_building_at_pos(pos)
	for id, area in pairs(astore:get_areas_for_pos(pos)) do
		return loaded_buildings[id], id
	end
	return nil
end

--------------------------------------------------------------
-- Criteria helpers and management
--------------------------------------------------------------

-- a list of criteria types, every criterion type gets called differently
rtstools.crit_type = {
	nodes = 1, -- gets updated if nodes of the building change
}

rtstools.crit_helper = {}

function rtstools.crit_helper.make_node_number(nodename, count)
	return {
		type = rtstools.crit_type.nodes,
		is_fulfilled = function(mgmt_pos, bld)
			local minp, maxp = get_edges_around_pos(mgmt_pos, bld.radius)
			local vmanip = minetest.get_voxel_manip(minp, maxp)
			local cur_cnt = 0
			for x = minp.x, maxp.x do
			for y = minp.y, maxp.y do
			for z = minp.z, maxp.z do
				local n = vmanip:get_node_at({x = x, y = y, z = z})
				if n.name == nodename then
					cur_cnt = cur_cnt + 1
				end
			end
			end
			end
			return (cur_cnt >= count), --(cur_cnt >= count)
				-- and count .. "/" .. count or
				cur_cnt .. "/" .. count
		end,
		description = "Place " .. count .. " of " .. nodename,
	}
end

-- does a graph search
-- traverse_func(pos, val, table_for_new_elements) returning new done nodes and new todo nodes
local function do_graph_search(initial_table, traverse_func)
	local todo_table = {}
	local done_table = {}
	for idx, val in pairs(initial_table) do
		todo_table[idx] = val
	end
	while true do
		local pos
		for idx, val in pairs(todo_table) do
			pos = val
			break
		end
		if pos == nil then -- if the table was empty, the search has ended
			return
		end
		local new_done, new_todo = traverse_func(pos, todo_table[pos])
		for idx, val in pairs(new_todo) do
			if done_table[idx] == nil then
				todo_table[idx] = val
			end
		end
		todo_table[pos] = nil
		done_table[pos] = true
		for idx, val in pairs(new_done) do
			todo_table[idx] = nil
			done_table[idx] = true
		end
	end
end

local function add_to_postable(tbl, pos)
	tbl[minetest.hash_node_position(pos)] = pos
end

local function new_postbl_with_pos(pos)
	local res = {}
	add_to_postable(res, pos)
	return res
end

-- door_num: the number of at least two high openings filled
-- room_node_names: { air = {}, door = {}, wall = {}, roof = {}, floor = {} }
-- TODO: doors and walls recognition (esp. doors are hard problem :p)
function rtstools.crit_helper.make_room_basic(room_node_names, door_min, door_max, air_num)
	return {
		type = rtstools.crit_type.nodes,
		is_fulfilled = function(mgmt_pos, bld)
			local minp, maxp = get_edges_around_pos(mgmt_pos, bld.radius)
			local vmanip = minetest.get_voxel_manip(minp, maxp)
			local air_cnt = 0
			local door_cnt = 0

			-- starts the room's graph search with the pos above the management node
			local init_tbl = new_postbl_with_pos({x = mgmt_pos.x, y = mgmt_pos.y + 1, z = mgmt_pos.z})
			do_graph_search(init_tbl, function(pos, val)
				local new_done = new_postbl_with_pos(pos)
				local new_todo = {}

				-- 1. check current column
				local column_height = 0
				local valid_floor = false
				local valid_roof = false
				local is_air = true
				local curpos = {x = pos.x, y = pos.y, z = pos.z}
				-- first go down by at maximum 2 to find the floor node
				-- (simulating a walking player)
				while is_air do
					if curpos.y < minp.y or curpos.y < pos.y - 2 then
						-- abort if curpos is outside of boundaries
						return new_postbl_with_pos(pos), {}
					end
					local nd = vmanip:get_node_at(curpos)
					-- print("v " .. nd.name)
					is_air = false
					if room_node_names.air[nd.name] then
						curpos.y = curpos.y - 1
						is_air = true
					elseif room_node_names.floor[nd.name] then
						valid_floor = true
					elseif nd.name == bld.mgmt_name then
						-- the management node is a valid floor node as well
						valid_floor = true
					end
				end
				-- now go up, and count how many air nodes we find
				is_air = true
				add_to_postable(new_done, curpos)
				local column_floor_y = curpos.y
				curpos.y = curpos.y + 1
				while is_air do
					if curpos.y > maxp.y then
						-- abort if column isn't inside [minp, maxp]
						return new_postbl_with_pos(pos), {}
					end
					local nd = vmanip:get_node_at(curpos)
					-- print("^ " .. nd.name)
					add_to_postable(new_done, curpos) -- gets every node in the column, except the floor
					is_air = false
					if room_node_names.air[nd.name] then
						column_height = column_height + 1
						curpos.y = curpos.y + 1
						is_air = true
					elseif room_node_names.roof[nd.name] then
						valid_roof = true
					end
				end

				-- 2. abort if column is too small (0 or 1 nodes high)
				if column_height < 2 then
					return new_postbl_with_pos(pos), {}
				end

				-- 3. abort if column doesn't have matching floor or roof
				if not valid_floor or not valid_roof then
					return new_postbl_with_pos(pos), {}
				end

				-- 4. add the column's nodes, if its 2 high, right above the floor,
				-- if its >= 3 high, one block higher too, to allow for stairs
				local add_y = column_floor_y + 1
				if column_height > 2 then
					add_to_postable(new_todo, {x = pos.x + 1, y = add_y + 1, z = pos.z})
					add_to_postable(new_todo, {x = pos.x - 1, y = add_y + 1, z = pos.z})
					add_to_postable(new_todo, {x = pos.x, y = add_y + 1, z = pos.z + 1})
					add_to_postable(new_todo, {x = pos.x, y = add_y + 1, z = pos.z - 1})
				end
				add_to_postable(new_todo, {x = pos.x + 1, y = add_y, z = pos.z})
				add_to_postable(new_todo, {x = pos.x - 1, y = add_y, z = pos.z})
				add_to_postable(new_todo, {x = pos.x, y = add_y, z = pos.z + 1})
				add_to_postable(new_todo, {x = pos.x, y = add_y, z = pos.z - 1})
				air_cnt = air_cnt + column_height
				return new_done, new_todo
			end)
			return (air_cnt >= air_num), -- and (door_cnt >= door_min)
				--and (door_cnt <= door_max), " air " ..
				air_cnt .. "/" .. air_num
				-- .. ", doors " .. door_min .. "/" .. door_max
		end,
		description = "Build house with at least " .. air_num .. " blocks of \n air around this node",
		--"Build a room with at least " .. door_num .. " entrance(s) and at least " .. air_num .. " air",
	}
end

local function update_nodes_criteria(mgmt_pos, crit_states, bld)
	for crit_idx, crit in pairs(bld.built_criteria) do
		if crit.type == rtstools.crit_type.nodes then
			crit_states[crit_idx] = { crit.is_fulfilled(mgmt_pos, bld) }
		end
	end
end

local function building_criteria_changed(l_bld, player)
	local meta = minetest.get_meta(l_bld.pos)
	local fspec = "size[8,9]label[0.5,0.5;"
		.. minetest.formspec_escape("Management node for " .. l_bld.bld.name) .. "]"
	local yc = 0
	local all_crit_fulfilled = true
	for crit_id, crit in pairs(l_bld.bld.built_criteria) do
		local crit_str = ""
		local state_crit = l_bld.crit_states[crit_id]
		if state_crit ~= nil then
			crit_str = (state_crit[1] and "DONE " or "NOT DONE ")
				.. crit.description
				.. (state_crit[2] and (" (" .. state_crit[2] .. ")") or "")
			all_crit_fulfilled = all_crit_fulfilled and state_crit[1]
		else
			-- TODO perhaps print warning to console?? this is an error!
			crit_str = "UNKNOWN " .. crit.description
			all_crit_fulfilled = false
		end
		fspec = fspec .. "label[1," .. tostring(yc*0.5 + 1) .. ";" .. minetest.formspec_escape(crit_str) .. "]"
		yc = yc + 1
	end
	local newstate = all_crit_fulfilled and rtstools.building_state.BUILT
		or rtstools.building_state.BUILDING
	if newstate ~= l_bld.state then
		local newstate_name = rtstools.building_state_names[newstate]
		minetest.chat_send_player(player:get_player_name(), "State change for building '"
			.. l_bld.bld.name .. "' to " .. newstate_name)
		l_bld.state = newstate
		meta:set_string("infotext", l_bld.bld.name .. " (" .. newstate_name .. ")")
	end
	meta:set_string("formspec", fspec)
end

minetest.register_on_placenode(function(pos, newnode, placer, oldnode, itemstack,
		pointed_thing)
	local bld = rtstools.get_building_at_pos(pos)
	if bld then
		update_nodes_criteria(bld.pos, bld.crit_states, bld.bld)
		building_criteria_changed(bld, placer)
	end
end)

minetest.register_on_dignode(function(pos, oldnode, digger)
	local bld = rtstools.get_building_at_pos(pos)
	if bld then
		update_nodes_criteria(bld.pos, bld.crit_states, bld.bld)
		building_criteria_changed(bld, digger)
	end
end)

--------------------------------------------------------------
-- Building registration
--------------------------------------------------------------

--[[
building definition (! is required)
{
	mgmt_override = {}, -- to change the nodedef of the management node. TODO
	                    -- only use it if you know what you do
	t_name, -- the technical name, set by register_building, you don't have to care setting it :)
	name = !, -- a name for the building, stay below 20 chars :) TODO
	short_desc = ! -- a short description of the building, stay below 50 chars ;p TODO
	image = {}, -- the building's icon image. TODO
	            -- Used at various places like building menu, the management node, etc
	built_criteria = {}, -- criteria a building needs to fullfill in order to be complete TODO
	radius = !, -- the building's size
	on_addnode = {}, -- called when a node gets added inside the building's radius
	on_built = !, -- executed when a building meets the criteria TODO
	on_destroyed = !, -- executed when a building doesnt meet the criteria anymore TODO
	on_mgmt_removed = {}, -- executed when the management node gets removed
	run = {}, -- executed every RTS step (did you really believe this was _R_TS??) TODO
}
]]
-- astore:insert_area({x=0,y=0,z=0}, {x=0,y=0,z=0})
--[[
building criterion
{
	type,
	is_fulfilled = function(mgmt_pos, building_def), returns pair of bool for result and string for result string
	description = "", used in management node for display
}
]]
function rtstools.register_building(t_name, def)
	-- register the building itself
	rtsp.buildings[t_name] = def

	def.t_name = t_name
	def.mgmt_override = def.mgmt_override or {}
	def.built_criteria = def.built_criteria or {}

	-- register the management node
	local mgmt_name = t_name .. "_mgmt"
	def.mgmt_name = mgmt_name
	local mgmt_def = {
		description = def.name .. " Management",
		groups = { oddly_breakable_by_hand = 3 },
		on_construct = function(pos)
			local minp, maxp = get_edges_around_pos(pos, def.radius)
			local id = astore:insert_area(minp, maxp, '')
			assert(id)
			loaded_buildings[id] = {
				pos = pos,
				crit_states = {},
				state = rtstools.building_state.BUILDING,
				bld = def,
			}
		end,
		on_destruct = function(pos)
			local building, id = rtstools.get_building_at_pos(pos)
			if not building then
				print("ERROR: no registered building found while removing management node")
				return
			end
			astore:remove_area(id)
			loaded_buildings[id] = nil
			if def.on_mgmt_removed then
				def.on_mgmt_removed(pos, def)
			end
		end,
		on_punch = function(pos, node, puncher)
			def.area_display.spawn(pos, 10)
		end,
		on_place = function(itemstack, placer, pointed_thing)
			-- TODO: don't guess the pos that minetest.item_place choses for placing
			-- the item, but use a method that gives the pos directly
			local pos_to_place = pointed_thing.above
			if rtstools.can_place_building_at_pos(pos_to_place, def.radius) then
				minetest.item_place(itemstack, placer, pointed_thing)
			else
				for id, building in pairs(
						rtstools.get_buildings_overlapping_area(pos_to_place,
						def.radius)) do
					building.bld.area_display.spawn(building.pos, 5)
				end
				local pname = placer:get_player_name()
				minetest.chat_send_player(pname, "Would overlap with other building")
			end
		end,

		paramtype = "light", -- (pretty bad) fix for the area display being black
		-- but the engine doesnt allow more

		-- can_dig = function(pos, player)
		-- end,
	}
	-- apply the override
	for name, val in pairs(def.mgmt_override) do
		mgmt_def[name] = val
	end
	minetest.register_node(mgmt_name, mgmt_def)

	-- register the area display
	def.area_display = rtstools.register_area_display(def.radius)

end
