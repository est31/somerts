-- RTS tools mod for minetest
-- Copyright (c) 2015 est31 <MTest31@outlook.com>
-- License: LGPL v2.1+

local rtsp = ...

local rtsb = {}

--------------------------------------------------------------
-- Local helper functions
--------------------------------------------------------------

local function get_edges_around_pos(pos, boxdef)
	if type(boxdef) == "number" then
		return {
			x = pos.x - boxdef,
			y = pos.y - boxdef,
			z = pos.z - boxdef,
		}, {
			x = pos.x + boxdef,
			y = pos.y + boxdef,
			z = pos.z + boxdef,
		}
	else
		return vector.subtract(pos, boxdef),
			vector.add(pos, boxdef)
	end
end

--------------------------------------------------------------
-- Building state helpers
--------------------------------------------------------------

rtstools.building_state = {
	BUILDING = 1,
	BUILT = 2,
	BUILDING_STALE = 3,
}
rtstools.building_state_names = {
	"building",
	"built",
	"building, stale",
}

local function building_built()

end

--------------------------------------------------------------
-- Loaded buildings management
--------------------------------------------------------------

local astore = AreaStore()
local loaded_buildings = rtsp.loaded_buildings

local loaded_buildings_path = minetest.get_worldpath() .. "/rts_buildings.dat"

local function load_buildings_from_file()
	local f = io.open(loaded_buildings_path, "r")
	if f then
		local b = f:read("*all")
		loaded_buildings = {}
		for bid, building in pairs(minetest.deserialize(b)) do
			local def = rtsp.buildings[building.bld]
			local minp, maxp = get_edges_around_pos(building.pos, def.boxdef)
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
function rtstools.can_place_building_at_pos(pos, boxdef)
	local minp, maxp = get_edges_around_pos(pos, boxdef)
	for id, area in pairs(astore:get_areas_in_area(minp, maxp, true, false, false)) do
		return false
	end
	return true
end

function rtstools.get_buildings_overlapping_area(pos, boxdef)
	local minp, maxp = get_edges_around_pos(pos, boxdef)
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
-- Room search utilities
--------------------------------------------------------------

-- does a graph search.
-- traverse_func(val) returning new done nodes and new todo nodes
-- returns table of visited nodes
local function do_graph_search(initial_table, traverse_func)
	local todo_table = {}
	local done_table = {}
	for idx, val in pairs(initial_table) do
		todo_table[idx] = val
	end
	while true do
		local cur_entry
		local cur_idx
		for idx, val in pairs(todo_table) do
			cur_entry = val
			cur_idx = idx
			break
		end
		if cur_entry == nil then -- if the table was empty, the search has ended
			break
		end
		local new_done, new_todo = traverse_func(cur_entry)
		for idx, val in pairs(new_todo) do
			if done_table[idx] == nil then
				todo_table[idx] = val
			end
		end
		todo_table[cur_idx] = nil
		for idx, val in pairs(new_done) do
			todo_table[idx] = nil
			done_table[idx] = val
		end
		assert(done_table[cur_idx])
	end
	return done_table
end

local function add_to_postable(tbl, pos)
	tbl[minetest.hash_node_position(pos)] = table.copy(pos)
end

local function add_to_d_postable(tbl, pos, d)
	tbl[minetest.hash_node_position(pos)] = {
		pos = table.copy(pos),
		d = d,
	}
end

local function new_postbl_with_pos(pos)
	local res = {}
	add_to_postable(res, pos)
	return res
end

local function new_d_postbl_with_pos(pos, d)
	local res = {}
	add_to_d_postable(res, pos, d)
	return res
end

local function is_x_z_in_boundaries(x, z, minp, maxp)
	return minp.x <= x and maxp.x >= x and minp.z <= z and maxp.z >= z
end

local b_r_search_class = {
	OUTSIDE = 1,
	ROOM = 2,
	ISITWALL = 3,
	ISITWALL_NOMORE = 4,
	WALL = 5,
	NOWALL = 6,
}

local function do_room_basic_graph_search(mgmt_pos, bld, room_node_names, minp, maxp, vmanip)
	local air_cnt = 0

	-- starts the room's graph search with
	-- the nodes above and below the management node
	local init_tbl = {}
	add_to_postable(init_tbl, {x = mgmt_pos.x, y = mgmt_pos.y + 1, z = mgmt_pos.z})
	add_to_postable(init_tbl, {x = mgmt_pos.x, y = mgmt_pos.y - 1, z = mgmt_pos.z})
	local building_room_nodes = do_graph_search(init_tbl, function(pos)
		local new_done = {}
		local new_todo = {}

		-- print("Column at " .. dump(pos))

		-- 1. Check if x,z combination is outside building area boundaires
		if not is_x_z_in_boundaries(pos.x, pos.z, minp, maxp) then
			return new_d_postbl_with_pos(pos, b_r_search_class.OUTSIDE), {}
		end

		-- 2. check current column
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
				return new_d_postbl_with_pos(pos, b_r_search_class.OUTSIDE), {}
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
		-- adds the floor as room node
		add_to_d_postable(new_done, curpos,
				valid_floor and b_r_search_class.ROOM or b_r_search_class.ISITWALL)
		local column_floor_y = curpos.y
		curpos.y = curpos.y + 1
		while is_air do
			if curpos.y > maxp.y then
				-- abort if column isn't inside [minp, maxp]
				return new_d_postbl_with_pos(pos, b_r_search_class.OUTSIDE), {}
			end
			local nd = vmanip:get_node_at(curpos)
			-- print("^ " .. nd.name)
			add_to_d_postable(new_done, curpos,
				b_r_search_class.ROOM) -- gets every node in the column, except the floor
			is_air = false
			if room_node_names.air[nd.name] then
				column_height = column_height + 1
				curpos.y = curpos.y + 1
				is_air = true
			elseif room_node_names.roof[nd.name] then
				valid_roof = true
			elseif nd.name == bld.mgmt_name then
				-- the management node is a valid roof node as well
				valid_roof = true
			end
		end

		-- 2. abort if column is too small (0 or 1 nodes high)
		if column_height < 2 then
			-- print("column too small")
			return new_d_postbl_with_pos(pos, b_r_search_class.ISITWALL), {}
		end

		-- 3. abort if column doesn't have matching floor or roof
		if not valid_floor or not valid_roof then
			-- print((valid_floor and "" or "no floor ")
			--	.. (valid_roof and "" or "no roof"))
			return new_d_postbl_with_pos(pos, b_r_search_class.ISITWALL), {}
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

		-- print("valid " .. column_height)
		air_cnt = air_cnt + column_height
		return new_done, new_todo
	end)
	local building_wall_nodes = do_graph_search(building_room_nodes, function(pos_entry)
		local pos = pos_entry.pos
		local new_done = new_d_postbl_with_pos(pos, b_r_search_class.NOWALL)
		local new_todo = {}


		-- 1. Check if it is a wall candidate
		if pos_entry.d ~= b_r_search_class.ISITWALL
				and pos_entry.d ~= b_r_search_class.ISITWALL_NOMORE then
			return new_done, {}
		end

		-- 2. Check if inside building area boundaries (y level too)
		if not is_x_z_in_boundaries(pos.x, pos.z, minp, maxp)
				or pos.y < minp.y or pos.y > maxp.y then
			return new_d_postbl_with_pos(pos, b_r_search_class.OUTSIDE), {}
		end

		-- 3. Check whether its a wall at all
		local nd = vmanip:get_node_at(pos)
		if not room_node_names.wall[nd.name] then
			return new_done, {}
		end

		-- print("Wall candidate at " .. dump(pos))

		-- 4. Now add whole y column thats a wall as well too

		-- 1. check current column
		local column_height = 0
		local is_wall = true
		local curpos = {x = pos.x, y = pos.y, z = pos.z}
		-- first go down
		-- TODO until at maximum 2 + room floor
		-- TODO skip door and window openings
		while is_wall do
			if curpos.y < minp.y then
				-- abort if curpos is outside of boundaries
				return new_d_postbl_with_pos(pos, b_r_search_class.OUTSIDE), {}
			end
			local nd = vmanip:get_node_at(curpos)
			-- print("v " .. nd.name)
			is_wall = false
			if room_node_names.wall[nd.name] then
				is_wall = true
			elseif nd.name == bld.mgmt_name then
				-- the management node is a valid wall node as well
				is_wall = true
			end
			if is_wall then
				curpos.y = curpos.y - 1
			end
		end
		-- now go up
		is_wall = true
		curpos.y = curpos.y + 1
		while is_wall do
			if curpos.y < minp.y then
				-- abort if curpos is outside of boundaries
				return new_d_postbl_with_pos(pos, b_r_search_class.OUTSIDE), {}
			end
			local nd = vmanip:get_node_at(curpos)
			-- print("^ " .. nd.name)
			is_wall = false
			if room_node_names.wall[nd.name] then
				is_wall = true
			elseif nd.name == bld.mgmt_name then
				-- the management node is a valid wall node as well
				is_wall = true
			end
			if is_wall then -- gets everything, floor included
				add_to_d_postable(new_done, curpos,
					b_r_search_class.WALL)
				curpos.y = curpos.y + 1
			end
		end

		-- if its a wall with no further searching requested, dont add more
		if pos_entry.d == b_r_search_class.ISITWALL_NOMORE then
			return new_done, {}
		end

		-- 5. Add neighbours as candidates for further wall nodes
		local add_y = pos.y
		add_to_d_postable(new_todo, {x = pos.x + 1, y = add_y, z = pos.z}, b_r_search_class.ISITWALL_NOMORE)
		add_to_d_postable(new_todo, {x = pos.x - 1, y = add_y, z = pos.z}, b_r_search_class.ISITWALL_NOMORE)
		add_to_d_postable(new_todo, {x = pos.x, y = add_y, z = pos.z + 1}, b_r_search_class.ISITWALL_NOMORE)
		add_to_d_postable(new_todo, {x = pos.x, y = add_y, z = pos.z - 1}, b_r_search_class.ISITWALL_NOMORE)

		return new_done, new_todo
	end)

	-- incorporate building_wall_nodes and building_room_nodes into building_nodes, with the room nodes
	-- overriding
	local building_nodes = {}

	for idx, val in pairs(building_wall_nodes) do
		if val.d == b_r_search_class.WALL then
			building_nodes[idx] = val
		end
	end
	for idx, val in pairs(building_room_nodes) do
		if val.d == b_r_search_class.ROOM then
			building_nodes[idx] = val
		end
	end
	return building_nodes, air_cnt
end


--------------------------------------------------------------
-- Building plans management
--------------------------------------------------------------

local rel_positions = {
	{x =  1, y =  0, z =  0},
	{x = -1, y =  0, z =  0},
	{x =  0, y =  1, z =  0},
	{x =  0, y = -1, z =  0},
	{x =  0, y =  0, z =  1},
	{x =  0, y =  0, z = -1},
}

-- maps building name to its plan
-- TODO: make this player wise
-- TODO: save this to file
local building_plans = rtsp.building_plans

local function chat_send_player(player_name_or_nil, msg)
	if player_name_or_nil then
		minetest.chat_send_player(player_name_or_nil, msg)
	end
end

function update_building_plans_if_needed(mgmt_pos, bld_def, player_name)
	local plans_entry = building_plans[bld_def.t_name]
	if plans_entry then
		return
	else
		chat_send_player(player_name, "Using building '"
			.. bld_def.name .. "' for building plan")
		local plan = {}

		local minp, maxp = get_edges_around_pos(mgmt_pos, bld_def.boxdef)
		local vmanip = minetest.get_voxel_manip(minp, maxp)

		-- first get a list of nodes of the building
		local building_nodes = do_room_basic_graph_search(mgmt_pos, bld_def,
			bld_def.room_node_names, minp, maxp, vmanip)
		plan.building_nodes = building_nodes
		-- print(dump(building_nodes))

		-- then find a path to build the building
		local init_tbl = new_postbl_with_pos({x = mgmt_pos.x, y = mgmt_pos.y + 1, z = mgmt_pos.z})
		local pathidx = 1
		local path = {}

		-- TODO find better search algorithm, right now we are impl. dependent O_o
		do_graph_search(init_tbl, function(pos, val)
			-- print("traversing " .. dump(pos))
			local new_done = new_postbl_with_pos(pos)
			local new_todo = {}

			local node = vmanip:get_node_at(pos)
			path[pathidx] = { pos = vector.subtract(pos, mgmt_pos), node = node }
			pathidx = pathidx + 1

			for rpi, rpos in pairs(rel_positions) do
				local cpos = vector.add(pos, rpos)
				local cpos_h = minetest.hash_node_position(cpos)
				if building_nodes[cpos_h] then
					new_todo[cpos_h] = cpos
				end
			end
			return new_done, new_todo
		end)
		plan.path = path
		-- print(dump(path))
		building_plans[bld_def.t_name] = plan
	end
end

local building_display = rtstools.register_area_display(0)

minetest.register_abm({
	nodenames = {"group:rts_tools_mgmt"},
	interval = 1,
	chance = 1,
	action = function(mgmt_pos, node, active_object_count, active_object_count_wider)
		local l_bld = rtstools.get_building_at_pos(mgmt_pos)
		if l_bld.state == rtstools.building_state.BUILDING  then
			local plan_entry = building_plans[l_bld.bld.t_name]
			if plan_entry then
				local next_state = l_bld.build_progress_state and (l_bld.build_progress_state + 1) or 1
				l_bld.build_progress_state = next_state
				local pathel = plan_entry.path[next_state]
				if pathel then
					if pathel.node.name ~= l_bld.bld.mgmt_name then
						local setp = vector.add(pathel.pos, mgmt_pos)
						minetest.set_node(setp, pathel.node)
						building_display.spawn(setp, 2)
						-- print("placing '" .. pathel.node.name .. "' at " .. dump(vector.add(pathel.pos, mgmt_pos)))

						-- tell building logic of the added node
						rtsb.update_building_state(l_bld, l_bld.owner_name)
					end
				else
					print("error, reached invalid path element at " .. next_state .. "! possibly end (which shouldnt be reached)?")
					l_bld.state = rtstools.building_state.BUILDING_STALE
					l_bld.build_progress_state = l_bld.build_progress_state - 1
				end
			end
		elseif l_bld.state == rtstools.building_state.BUILT then
			l_bld.build_progress_state = nil
		end
	end,
})

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
			local minp, maxp = get_edges_around_pos(mgmt_pos, bld.boxdef)
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

-- door_num: the number of at least two high openings filled
-- room_node_names: { air = {}, door = {}, wall = {}, roof = {}, floor = {} }
-- TODO: doors and walls recognition (esp. doors are hard problem :p)
function rtstools.crit_helper.make_room_basic(room_node_names, door_min, door_max, air_num)
	return {
		type = rtstools.crit_type.nodes,
		is_fulfilled = function(mgmt_pos, bld)
			local minp, maxp = get_edges_around_pos(mgmt_pos, bld.boxdef)
			local vmanip = minetest.get_voxel_manip(minp, maxp)
			local air_cnt = 0
			local door_cnt = 0

			local building_nodes, air_cnt = do_room_basic_graph_search(mgmt_pos, bld, room_node_names, minp, maxp, vmanip)

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

local function building_criteria_changed(l_bld, player_name)
	local meta = minetest.get_meta(l_bld.pos)
	local fspec = "size[8,9]label[0.5,0.5;"
		.. minetest.formspec_escape("Management node for " .. l_bld.bld.name) .. "]"
		.. "image[0,1;1,1;" .. l_bld.bld.image .. "]"
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
		chat_send_player(player_name, "State change for building '"
			.. l_bld.bld.name .. "' to " .. newstate_name)
		if newstate == rtstools.building_state.BUILT then
			update_building_plans_if_needed(l_bld.pos, l_bld.bld, player_name)
		end
		l_bld.state = newstate
		meta:set_string("infotext", l_bld.bld.name .. " (" .. newstate_name .. ")")
	end
	meta:set_string("formspec", fspec)
end

function rtsb.update_building_state(l_bld, player_name)
	update_nodes_criteria(l_bld.pos, l_bld.crit_states, l_bld.bld)
	building_criteria_changed(l_bld, player_name)
end

minetest.register_on_placenode(function(pos, newnode, placer, oldnode, itemstack,
		pointed_thing)
	local l_bld = rtstools.get_building_at_pos(pos)
	if l_bld then
		rtsb.update_building_state(l_bld, placer:get_player_name())
	end
end)

minetest.register_on_dignode(function(pos, oldnode, digger)
	local l_bld = rtstools.get_building_at_pos(pos)
	if l_bld then
		rtsb.update_building_state(l_bld, digger:get_player_name())
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
	image = !, -- the building's icon image.
	            -- Used at various places like building menu, the management node, etc
	built_criteria = {}, -- criteria a building needs to fullfill in order to be complete TODO
	boxdef = !, -- the building's claimed area, where only the building itself can exist.
	            -- either a table with two edges {min, max}, or a number specifying the cube's radius
	room_node_names = !, -- the node names for the rooms, see do_room_basic_graph_search
	on_addnode = {}, -- called when a node gets added inside the building's boxdef
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
		groups = {
			oddly_breakable_by_hand = 3,

			-- to allow group based abms, etc
			rts_tools_mgmt = 1,
			},
		on_construct = function(pos)
			local minp, maxp = get_edges_around_pos(pos, def.boxdef)
			local id = astore:insert_area(minp, maxp, '')
			assert(id)
			loaded_buildings[id] = {
				pos = pos,
				crit_states = {},
				state = rtstools.building_state.BUILDING,
				bld = def,
				owner_name = nil, -- TODO we need to set the owner name here somehow
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
			if rtstools.can_place_building_at_pos(pos_to_place, def.boxdef) then
				minetest.item_place(itemstack, placer, pointed_thing)
			else
				local cnt = 0
				for id, building in pairs(
						rtstools.get_buildings_overlapping_area(pos_to_place,
						def.boxdef)) do
					building.bld.area_display.spawn(building.pos, 5)
					cnt = cnt + 1
				end
				local pname = placer:get_player_name()
				minetest.chat_send_player(pname,
					(cnt > 1 and "Would overlap with other buildings"
						or "Would overlap with another building"))
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
	def.area_display = rtstools.register_area_display(def.boxdef)

end
