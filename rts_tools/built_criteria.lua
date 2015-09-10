-- RTS tools mod for minetest
-- Copyright (c) 2015 est31 <MTest31@outlook.com>
-- License: LGPL v2.1+

local rtsp = ...

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
			local minp, maxp = rtsp.get_edges_around_pos(mgmt_pos, bld.boxdef)
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
			local minp, maxp = rtsp.get_edges_around_pos(mgmt_pos, bld.boxdef)
			local vmanip = minetest.get_voxel_manip(minp, maxp)
			local air_cnt = 0
			local door_cnt = 0

			local building_nodes, air_cnt = rtsp.do_room_basic_graph_search(mgmt_pos, bld, room_node_names, minp, maxp, vmanip)

			return (air_cnt >= air_num), -- and (door_cnt >= door_min)
				--and (door_cnt <= door_max), " air " ..
				air_cnt .. "/" .. air_num
				-- .. ", doors " .. door_min .. "/" .. door_max
		end,
		description = "Build house with at least " .. air_num .. " blocks of \n air around this node",
		--"Build a room with at least " .. door_num .. " entrance(s) and at least " .. air_num .. " air",
	}
end

function rtsp.update_nodes_criteria(mgmt_pos, crit_states, bld)
	for crit_idx, crit in pairs(bld.built_criteria) do
		if crit.type == rtstools.crit_type.nodes then
			crit_states[crit_idx] = { crit.is_fulfilled(mgmt_pos, bld) }
		end
	end
end
