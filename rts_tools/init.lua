-- RTS tools mod for minetest
-- Copyright (c) 2015 est31 <MTest31@outlook.com>
-- License: LGPL v2.1+

rtstools = {}

local rtsp = {}
rtsp.buildings = {}

local modpath = minetest.get_modpath(minetest.get_current_modname()) .. "/"
local rtsp_dofile = function (name) assert(loadfile(modpath .. name))(rtsp) end

rtsp_dofile("building.lua")

--function rtstools.show_
