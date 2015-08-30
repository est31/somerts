-- RTS mod for minetest
-- Copyright (c) 2015 est31 <MTest31@outlook.com>
-- License: LGPL v2.1+

rtstools.register_building("somerts:lumberjack", {
	mgmt_override = {
		tiles = {"default_sandstone_brick.png^default_tool_stoneaxe.png"},
	},
	built_criteria = {
		rtstools.crit_helper.make_node_number("default:wood", 30, 5),
	},
	name = "Lumberjack",
	short_desc = "cuts down trees, plants new ones",
	radius = 5,
})

minetest.register_craft({
	output = "somerts:lumberjack_mgmt",
	recipe = {
		{"default:wood", "default:axe_stone", "default:cobble"},
		{"", "default:wood", ""},
		{"default:tree", "default:tree", "default:tree"},
	},
})
