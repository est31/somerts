-- RTS tools mod for minetest
-- Copyright (c) 2015 est31 <MTest31@outlook.com>
-- License: LGPL v2.1+

rtstools = {}

local rtsp = {}
rtsp.buildings = {}
rtsp.loaded_buildings = {}
rtsp.building_plans = {}

local modpath = minetest.get_modpath(minetest.get_current_modname()) .. "/"
local rtsp_dofile = function (name) assert(loadfile(modpath .. name))(rtsp) end

rtsp_dofile("area_display.lua")
rtsp_dofile("building.lua")
rtsp_dofile("built_criteria.lua")

--function rtstools.show_

