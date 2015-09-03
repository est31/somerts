-- RTS mod for minetest
-- Copyright (c) 2015 est31 <MTest31@outlook.com>
-- License: LGPL v2.1+

local simple_buildings_room_node_names = {
	air = {
		["air"] = true,
	},
	door = {}, -- TODO
	wall = {}, -- TODO
	roof = {
		["default:wood"] = true,
		["default:tree"] = true,
	},
	floor = {
		["default:dirt"] = true,
		["default:wood"] = true,
	},
}

rtstools.register_building("somerts:lumberjack", {
	mgmt_override = {
		tiles = {"default_sandstone_brick.png^default_tool_stoneaxe.png"},
	},
	built_criteria = {
		rtstools.crit_helper.make_node_number("default:wood", 30),
		rtstools.crit_helper.make_room_basic(simple_buildings_room_node_names, 1, 1, 18),
	},
	name = "Lumberjack",
	short_desc = "cuts down trees, plants new ones",
	radius = 5,
	room_node_names = simple_buildings_room_node_names,
})

minetest.register_craft({
	output = "somerts:lumberjack_mgmt",
	recipe = {
		{"default:wood", "default:axe_stone", "default:cobble"},
		{"", "default:wood", ""},
		{"default:tree", "default:tree", "default:tree"},
	},
})
