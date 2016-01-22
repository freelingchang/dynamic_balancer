local _M = {}

function in_array(b,list)
    -- 判断元素是否在table内
    if not list then
        return false
    end
    if list then
        for k, v in pairs(list) do
            if v ==b then
                return true
            end
        end
        return false
    end
end

function convert_tonumber(ip_table)
    -- 转换weight 为数字
    local n = table.getn(ip_table)
    local i
    for i=1,n,1 do
        ip_table[i]['weight'] = tonumber(ip_table[i]['weight'])
        ip_table[i]['current_weight'] = tonumber(ip_table[i]['current_weight'])
    end

end

function select_upstream(peer)
    -- 选择一个服务器
    -- 先转化为数字
    convert_tonumber(peer)
    local MAX = table.getn(peer)
    while 1 == 1 do
        for i=1,MAX,1 do
            -- 这个地方出了问题,数组不存在 --
            if peer[i]["current_weight"] > 0 then
                local n = i -- n为第一个current_weight大于0的服务器下标
                while i < MAX do
                    i= i+1 -- i从n的下一个服务器开始遍历
                    if peer[i]["current_weight"] > 0 then
                        local current = peer[n]["current_weight"] * 1000 / peer[i]["current_weight"]
                        local weight = peer[n]["weight"] *1000 / peer[i]["weight"]

                        if current  > weight then
                            peer[n]["current_weight"]  = peer[n]["current_weight"] - 1
                            return n
                        end
                        n = i
                    end
                end
                if peer[i]["current_weight"] > 0 then
                    n = i
                end
                peer[n]["current_weight"]  = peer[n]["current_weight"] - 1
                return n
            end
        end
        local i = 1

        while i < MAX+1 do
            peer[i]["current_weight"] = peer[i]["weight"];
            i = i +1
        end
        local n = 1
        return n
    end

end

function _M.get_server(app_name)
    local balancer = require "ngx.balancer"
    local cache = require "resty.ddkl_cache"
    local ddkl_cache = cache.get_lrucache()
    local host

    local result_t = ddkl_cache:get(app_name)
    if  result_t ~= nil then
        -- ngx.say(result)
        local state_name, status_code = balancer.get_last_failure()
        if state_name == "failed" then
            -- 如果服务器上次failed 了,则写入缓存,下次get到直接跳过
            local ret = ddkl_cache:get(app_name.."last_server")
            ddkl_cache:set(app_name..ret,"1",120)
        end

        -- 设置最大next 尝试次数
        local MAX = table.getn(result_t)
        if ngx.ctx.tries == nil then
            ngx.ctx.tries = MAX*10-1
        end
        balancer.set_more_tries(ngx.ctx.tries)
        ngx.ctx.tries = ngx.ctx.tries -1
        local n = select_upstream(result_t)
        host = result_t[n]["ip"]
        -- 如果服务器上次failed 了,直接跳过,设置die时间,缓存过期控制
        local i = 1
        local k = 0
        while i < MAX*10 do
            local ret = ddkl_cache:get(app_name..host)
            if ret then
                n = select_upstream(result_t)
                host = result_t[n]["ip"]
            else
                k = 1
                break
            end
            i = i +1
        end
        -- ngx.say(new_result_str)
        ddkl_cache:set(app_name,result_t,60)
        ddkl_cache:set(app_name.."last_server",host)
        if k == 0 then
            ngx.log(ngx.ERR,"all server die")
            ngx.exit(ngx.WARN)
        end

    else
        ngx.log(ngx.ERR,"get cache failed")
    end
    return host
end

return _M
