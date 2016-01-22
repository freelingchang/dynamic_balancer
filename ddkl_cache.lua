--
-- Created by IntelliJ IDEA.
-- User: vim
-- Date: 16/1/7
-- Time: 下午3:59
-- To change this template use File | Settings | File Templates.
--
-- mydata.lua
local _M = {}

local lrucache = require "resty.lrucache"
local c = lrucache.new(200)

function _M.get_server()
    return c:get("addr")
end

function _M.set_server(addr)
    return c:set("addr",addr)
end

function _M.get_lrucache()
    return c
end

return _M

