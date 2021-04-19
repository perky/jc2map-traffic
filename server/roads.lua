RoadType = {
	ROADTYPE_NORMAL=0,
	WATER_PATROL=1,
	GROUND_ROAM=2,
	GROUND_PATROL=3,
	AIR_PATROL=4,
	AIR_TAXI=7,
	WATER_ROAM=5,
	RAILWAY=6,
	SPLINE=8
}

RoadLanes = {
    [0] = { -- patrol path
        width = 6,
        count = 1
    },
    [1] = { -- dirt road
        width = 6,
        count = 1
    },
    [2] = { -- small asphalt
        width = 6,
        count = 2
    },
    [3] = { -- medium asphalt
        width = 7,
        count = 2
    },
    [4] = { -- highway
        width = 12,
        count = 4
    },
    [5] = { -- single lane
        width = 6,
        count = 1
    }
}

function LoadNaviagtionMesh( path )
    SetUnicode( false )
    local msg = require 'MessagePack'

    local file, file_error = io.open( path , "rb" )

    if file_error then 
            error(file_error)
        return
    end

    local temp_table = {}

    if file ~= nil then 
        local data = file:read("*a")
        if data ~= nil then
        	-- data = string.trim( data )
            temp_table = msg.unpack(data)
            file:close()
        end
    end

    local node_map = {}
    local id_list = {}
    local count = 0
    for _,node in pairs(temp_table) do
        node.position = TableToVector3( node.position )

        -- define node properties
        if node.info.sidewalk_left ~= 0 or node.info.sidewalk_right ~= 0 then
        	node.pedestrian_node = true
        end

        local road_type = node.info.road_type

        if road_type == RoadType.ROADTYPE_NORMAL 
        or road_type == RoadType.GROUND_ROAM 
        or road_type == RoadType.SPLINE 
        then
         	node.vehicle_node = true
        else
            node.vehicle_node = false
        end

        if node.vehicle_node then
            node_map[node.id] = node
            table.insert(id_list, node.id)
        end

        count = count + 1
    end

    SetUnicode( true )
    return {map = node_map, ids = id_list}
end

--- Returns a random connected neighbor
--- if a direction is specified it will not return a neighbor
--- from the opposite direction.
function GetRandomRoadNeighbor(navmesh, node, direction, no_recurse)
    local candidates = {}
    for _, adj in ipairs(node.neighbours) do
        local adj_node = navmesh.map[adj.id]
        if adj_node then
            local adj_pos = adj_node.position
            local diff = (adj_pos - node.position)
            local adj_direction = diff:Normalized()
            local dist_sqr = diff:LengthSqr()
            local max_dist = 2000
            if (direction == nil or (Vector3.Dot(direction, adj_direction) > -0.4))
            and dist_sqr < (max_dist*max_dist) 
            then
                table.insert(candidates, adj.id)
            end
        end
    end
    if #candidates == 1 then
        return navmesh.map[candidates[1]]
    elseif #candidates > 1 then
        return navmesh.map[candidates[math.random(1, #candidates)]]
    elseif direction ~= nil and (not no_recurse) then
        return GetRandomRoadNeighbor(navmesh, node, direction * -1, true)
    else
        return nil
    end
end

function GetRandomRoadNode(navmesh)
    local node_id = navmesh.ids[math.random(1, #navmesh.ids)]
    return navmesh.map[node_id]
end

function GetNearestRoad(navmesh, position)
    local closest_dist = 99999999
    local closest_node = nil
    for id, node in pairs(navmesh.map) do
        local dist = Vector3.DistanceSqr(node.position, position)
        if dist < closest_dist then
            closest_dist = dist
            closest_node = node
        end
    end
    return closest_node
end

function GetConnectedNodePositions(navmesh, start_node, max_connections)
    local edges = {}
    local open = {}
    local closed = {}
    table.insert(open, start_node)

    local alternate = false
    while #open >= 1 and #edges < max_connections do
        local idx = math.random(1, #open)
        local node = open[idx]
        table.remove(open, idx)
        
        if node and node.neighbours then
            table.insert(closed, node)
            for _, adj_node in ipairs(node.neighbours) do
                local already_in_nodes = false
                for _, other_node_id in ipairs(closed) do
                    if other_node_id == adj_node.id then
                        already_in_nodes = true
                        break
                    end
                end
                if not already_in_nodes then
                    table.insert(edges, {node.position, navmesh.map[adj_node.id].position})
                    table.insert(open, navmesh.map[adj_node.id])
                end
            end
        end
    end

    return edges
end

function GetRoadSpeed(node)
    if node.info.speed_limit == 0 then
        return CONFIG.base_virtual_speed
    elseif node.info.speed_limit == 1 then
        return CONFIG.base_virtual_speed
    elseif node.info.speed_limit == 2 then
        return CONFIG.rural_slow_speed
    elseif node.info.speed_limit == 3 then
        return CONFIG.rural_fast_speed
    elseif node.info.speed_limit == 4 then
        return CONFIG.highway_speed
    else
        return CONFIG.base_virtual_speed
    end
end

function GetLaneOffset(src_node, dst_node, desired_lane)
    local dir = (dst_node.position - src_node.position):Normalized()
    local lane_info = RoadLanes[dst_node.info.size]
    if not lane_info then return Vector3.Zero end

    local lane_width = lane_info.width
    local lane_mid = lane_width * 0.5
    if lane_info.count == 1 then
        lane_mid = lane_width * 0.25
    end
    local right = Vector3.Cross(Vector3.Down, dir)
    
    local is_one_way = (dst_node.info.traverse_type ~= 0)
    if is_one_way then
        local lane = (desired_lane % lane_info.count)
        return (right * lane_mid) + (right * lane_width * lane) + (right * lane_width * lane_info.count * -0.5)
    else
        local lane = (desired_lane % (lane_info.count/2))
        return (right * lane_mid) + (right * lane_width * lane)
    end
end