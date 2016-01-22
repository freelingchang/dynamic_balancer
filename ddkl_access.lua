--
-- Created by IntelliJ IDEA.
-- User: vim
-- Date: 15/12/10
-- Time: 下午2:39
-- To change this template use File | Settings | File Templates.
--
local _M = {}
EXPIRE_TIME = 60

function get_redis(app_name)
    local redis = require "resty.redis";
    local cjson = require "cjson"
    local red = redis:new()
    red:set_timeout(100) -- 100 ms

    -- 初始值设置
    local redis_host = "10.0.3.61"
    local redis_port = "6379"

    local res, err = red:connect(redis_host, redis_port)
    if not res then
        ngx.log(ngx.ERR,"connect redis failed: "..err)
        return
    end

    local res_json, err = red:get(app_name)
    if not res_json then
        ngx.log(ngx.ERR,"get key failed : "..app_name)
        return
    end
    local res_s = cjson.decode(res_json)
    return res_s
end


function split(str,sep)
    -- 字符串分割
    local result = {}
    local s_start,s_end = string.find(str,sep)
    local s1 = string.sub (str, 0 ,s_start-1 )
    local s2 = string.sub (str, s_start+1)
    table.insert(result,s1)
    table.insert(result,s2)
    return result
end

function get_server_backup(app_name)
    local upstream = require "ngx.upstream"
    local get_servers = upstream.get_servers
    local get_upstreams = upstream.get_upstreams

    local res_s = {}
    local upstream_name = app_name.."_backup"
    local servers = upstream.get_servers(upstream_name)
    if not servers then
        ngx.log(ngx.ERR,"not find server")
        return
    end
    local group1 = {}
    for k, v in pairs(servers) do
        local  line = {}
        local host = split(v["addr"],":")
        local addr = host[1]
        local port = host[2]
        line["ip"] = addr
        line["weight"] = 10
        line["current_weight"] = 10
        table.insert(group1,line)
    end
    res_s["group1"] = group1
    return res_s
end

function list_backup_server(app_name)
    local upstream = require "ngx.upstream"
    local get_servers = upstream.get_servers
    local get_upstreams = upstream.get_upstreams

    local upstream_name = app_name.."_backup"
    local servers = upstream.get_servers(upstream_name)
    for k, v in pairs(servers) do
        local addr = split(v['addr'],":")
        ngx.log(ngx.ERR,addr[1])
    end
end

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

function select_upstream(peer)
    -- 选择一个服务器
    -- 先把权值转化为数字
    convert_tonumber(peer)
    local MAX = table.getn(peer)
    while 1 == 1 do
        for i=1,MAX,1 do
            -- 这个地方出了问题,数组不存在 --
            if peer[i]["current_weight"] > 0 then
                n = i -- n为第一个current_weight大于0的服务器下标
                while i < MAX do
                    i= i+1 -- i从n的下一个服务器开始遍历
                    if peer[i]["current_weight"] > 0 then
                        current = peer[n]["current_weight"] * 1000 / peer[i]["current_weight"]
                        weight = peer[n]["weight"] *1000 / peer[i]["weight"]

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
        i = 1

        while i < MAX+1 do
            peer[i]["current_weight"] = peer[i]["weight"];
            i = i +1
        end
        n = 1
        return n
    end

end

function is_tester(res_s)
    local testiplist = res_s["testiplist"]
    -- 判断是否为测试者,通过比较用户IP是否在testiplist 数组内来判断
    local ip = ngx.var.remote_addr
    if in_array(ip,testiplist) then
        ngx.header.TEST = "true"
        return true
    else
        ngx.header.TEST = "false"
        return false
    end
end

function get_server(app_name)
    local cjson = require "cjson"
    local cache = require "resty.ddkl_cache";
    local ddkl_cache = cache.get_lrucache()
    -- local ddkl_cache = ngx.shared.my_cache
    local result = ddkl_cache:get(app_name)
    if  result ~= nil then
        -- ngx.say(result)
        result_t = result
        local n = select_upstream(result_t)
        -- ngx.say(new_result_str)
        ddkl_cache:set(app_name,result_t,EXPIRE_TIME)
    else
        ngx.log(ngx.ERR,"get cache failed")
    end
    cache.set_server(result_t[n]["ip"])
    return result_t[n]["ip"]
end

function set_share_cache(res_s,app_name,group)
    local cache = require "resty.ddkl_cache";
    local cjson = require "cjson"
    local ddkl_cache = cache.get_lrucache()
    local host_list = {}
    if group == "all" then
        local group1 =  res_s["group1"]
        local group2 =  res_s["group2"]
        for k,v in ipairs(group1) do
            table.insert(host_list,v)
        end
        if group2 then
            for k,v in ipairs(group2) do
                table.insert(host_list,v)
            end
        end
    else
        host_list =  res_s[group]
    end
    local cache_flags = ddkl_cache:get(app_name.."cache")
    if not cache_flags then
        ngx.log(ngx.ERR,"cache expire")
        ddkl_cache:set(app_name.."cache","1",EXPIRE_TIME)
        ngx.log(ngx.ERR,"set expire and set cache")
        ddkl_cache:set(app_name,host_list,EXPIRE_TIME)
    else
        local result = ddkl_cache:get(app_name)
        if not result then
            ngx.log(ngx.ERR,"set cache")
            ddkl_cache:set(app_name,host_list,EXPIRE_TIME)
        end
    end
end

function select_group(res_s)
    local deploy = tonumber(res_s["deploy"])
    local group
    if deploy == 1 then
        -- 进入测试阶段,符合测试IP的转发到group2组 的服务器上,普通用户转发到group1组 服务器上
        if is_tester(res_s) then
            group = "group2"
        else
            group = "group1"
        end
    elseif deploy == 2 then
        group = "group2"
        --  测试通过,所有用户转发到 group2组,开始更新group的服务器
    elseif deploy == 0 then
        -- 全部更新成功,合并group,和group2,按权重轮询
        group = "all"
    else
        -- 全部更新成功,合并group,和group2,按权重轮询
        group = "all"
    end
    return group
end

-- 主逻辑开始 ---
function _M.core(app_name)
    local cache = require "resty.ddkl_cache";
    local cjson = require "cjson"
    local ddkl_cache = cache.get_lrucache()
    local res_s

    local result = ddkl_cache:get(app_name.."info")
    if not result then
        res_s = get_redis(app_name)
        if not res_s then
            ngx.log(ngx.ERR,"get upstream from cfg")
            res_s = get_server_backup(app_name)
            if not res_s then
                ngx.log(ngx.ERR,"not find upstream")
            end
        end
        ddkl_cache:set(app_name.."info",res_s,EXPIRE_TIME)
    else
        res_s = result
    end
    local group = select_group(res_s)
    set_share_cache(res_s,app_name,group)
end

return _M
