-- TRAFFIC (server) by Luke Perkin (luke@locogame.co.uk)
-- This script used the JCMP-AI script from jaxm as a reference.
-- This uses the GroundVehicleNavigation binary data from that.

LandVehicleModels = {
    1, 2, 4, 7, 8, 9, 
    10, 11, 12, 13, 15, 18, 
    21, 22, 23, 26, 29,
    31, 32, 33, 35, 36, 
    40, 41, 42, 43, 44, 46, 47, 48, 49,
    52, 54, 55, 56, 
    60, 61, 63, 66, 68, 
    70, 71, 72, 73, 74, 76, 77, 78, 79,
    83, 84, 86, 87, 89,
    90, 91
}
math.randomseed(os.time())
local navmesh = nil
local virtual_vehicles = {}
local stuck_check_timer = Timer()

function ModuleLoad()
    navmesh = LoadNaviagtionMesh( 'GroundVehicleNavigation' )
    for i = 1, CONFIG.max_virtual_vehicles do
        local node = GetRandomRoadNode(navmesh)
        local entity = CreateVirtualVehicle(node)
    end
    Events:Subscribe("PlayerChat", PlayerChat)
    Events:Subscribe("PlayerEnterVehicle", PlayerEnterVehicle)
    Events:Subscribe("PostTick", Tick)
end

function ModuleUnload()
    for id, object in pairs(virtual_vehicles) do
        local vehicle = Vehicle.GetById(object:GetValue("vehicle_id"))
        vehicle:Remove()
        object:Remove()
    end
    navmesh = nil
    virtual_vehicles = nil
end

function CreateVehicle(virtual_vehicle, node)
    local vehicle = Vehicle.Create(LandVehicleModels[math.random(1, #LandVehicleModels)], 
        node.position + Vector3(0, 3, 0), 
        Angle(0, 0, 0))
    vehicle:SetNetworkValue("virtual_vehicle_id", virtual_vehicle:GetId())
    vehicle:SetInvulnerable(false)
    vehicle:SetHealth(0.8)
    vehicle:SetStreamDistance(CONFIG.stream_distance)
    virtual_vehicle:SetNetworkValue("vehicle_id", vehicle:GetId())
    return vehicle
end

function CreateVirtualVehicle(node)
    local entity = WorldNetworkObject.Create(node.position)
    entity:SetNetworkValue("type", "virtual_vehicle")
    entity:SetValue("road_id", node.id)
    local neighbour = GetRandomRoadNeighbor(navmesh, node, nil)
    if neighbour then
        entity:SetValue("next_road_id", neighbour.id)
    end
    entity:SetValue("top_speed", CONFIG.default_top_speed)
    entity:SetValue("desired_lane", math.random(1,4))
    entity:SetValue("stuck_position", node.position)
    entity:SetStreamDistance(CONFIG.stream_distance)
    CreateVehicle(entity, node)
    virtual_vehicles[entity:GetId()] = entity
    return entity
end

function Tick(args)
    if not navmesh then return end

    local dt = args.delta
    local do_stuck_check = false
    if stuck_check_timer:GetSeconds() >= CONFIG.stuck_check_interval then
        stuck_check_timer:Restart()
        do_stuck_check = true
    end

    for id, entity in pairs(virtual_vehicles) do
        local pos = entity:GetPosition()
        local node = navmesh.map[entity:GetValue("road_id")]
        local next_node = navmesh.map[entity:GetValue("next_road_id")]

        local is_stuck = false
        if do_stuck_check then
            is_stuck = IsWithinDistance(pos, 
                                        entity:GetValue("stuck_position"), 
                                        CONFIG.stuck_check_distance)
            entity:SetValue("stuck_position", pos)
        end
        
        local needed_new_nodes = false
        while is_stuck or (node == nil) or (next_node == nil) do
            node = GetRandomRoadNode(navmesh)
            next_node = GetRandomRoadNeighbor(navmesh, node, nil)
            is_stuck = false
            needed_new_nodes = true
        end
        
        if needed_new_nodes then
            entity:SetValue("road_id", node.id)
            entity:SetValue("next_road_id", next_node.id)
            entity:SetValue("next_next_road_id", nil)
            entity:SetPosition(node.position)
        end

        -- Create new vehicle if it doesn't exist
        local vehicle = Vehicle.GetById(entity:GetValue("vehicle_id"))
        if not IsValid(vehicle) then
            CreateVehicle(entity, node)
        end

        local desired_lane = entity:GetValue("desired_lane")
        local lane_offset = GetLaneOffset(node, next_node, desired_lane)
        local src_pos = node.position + lane_offset
        local dst_pos = next_node.position + lane_offset
        local dir = (dst_pos - pos):Normalized()

        local slow_for_next_turn = entity:GetValue("slow_for_next_turn")
        local arrive_dist = 3
        if slow_for_next_turn then
            arrive_dist = 10
        end
 
        if not IsWithinDistance(pos, dst_pos, arrive_dist) then
            local road_speed = GetRoadSpeed(node)
            local top_speed = entity:GetValue("top_speed")
            local uphill = 1 - (math.max(Vector3.Dot(Vector3.Up, dir), 0) * CONFIG.uphill_slower)
            local speed = math.min(road_speed * uphill, top_speed) * CONFIG.speed_multiplier
            
            local slow_time = entity:GetValue("slow_time")
            if slow_time and Server:GetElapsedSeconds() > slow_time then
                slow_time = false
                entity:SetValue("slow_time", false)
            end

            if slow_for_next_turn or slow_time then
                if IsWithinDistance(pos, dst_pos, CONFIG.turn_slow_distance) 
                or IsWithinDistance(pos, src_pos, CONFIG.turn_slow_distance) then
                    speed = speed * CONFIG.turn_slow_ratio
                else
                    entity:SetValue("slow_time", false)
                    entity:SetNetworkValue("slow_for_next_turn", false)
                    slow_time = false
                    slow_for_next_turn = false
                end
            end

            entity:SetNetworkValue("speed", speed)
            entity:SetNetworkValue("direction", dir)

            local next_pos = pos + (dir * speed * dt)

            entity:SetPosition(next_pos)
            vehicle:SetStreamPosition(next_pos + Vector3(0, 2, 0))
        else
            -- If this was a slow turn, continue to be slow for little duration.
            if slow_for_next_turn and not entity:GetValue("slow_time") then
                entity:SetNetworkValue("slow_for_next_turn", false)
                entity:SetValue("slow_time", Server:GetElapsedSeconds() + CONFIG.turn_slow_duration)
            end
            -- Get the next road node.
            local last_dir = (dst_pos - src_pos):Normalized()
            local next_neighbour_id = entity:GetValue("next_next_road_id")
            local neighbour = nil
            if next_neighbour_id then
                neighbour = navmesh.map[next_neighbour_id]
                entity:SetValue("next_next_road_id", nil)
            else
                neighbour = GetRandomRoadNeighbor(navmesh, next_node, last_dir)
            end
            if neighbour then   
                entity:SetValue("road_id", next_node.id)
                entity:SetValue("next_road_id", neighbour.id)
                entity:SetPosition(dst_pos)
                -- Look one node ahead to predict a turn.
                -- TODO: refactor this for N node lookahead.
                local new_dir = (neighbour.position - next_node.position):Normalized()
                local next_neighbour = GetRandomRoadNeighbor(navmesh, neighbour, new_dir)
                if next_neighbour then
                    entity:SetValue("next_next_road_id", next_neighbour.id)
                    -- if turn has a large radius then temporarily slow it down.
                    local next_dir = (next_neighbour.position - neighbour.position):Normalized()
                    local turn_dot = Vector3.Dot(next_dir, new_dir)
                    if turn_dot <= CONFIG.turn_dot_to_slow then
                        slow_for_next_turn = true
                        entity:SetNetworkValue("slow_for_next_turn", true)
                    end
                end
            else
                ClearVirtualVehicleNodes(entity)
            end
        end

    end
    
    for vehicle in Server:GetVehicles() do
        if IsValid(vehicle) and vehicle:GetValue("virtual_vehicle_id") ~= nil then
            local id = vehicle:GetValue("virtual_vehicle_id")
            local explode_time = vehicle:GetValue("explode_time")
            if (vehicle:GetHealth() <= 0) or (explode_time and Server:GetElapsedSeconds() > explode_time) then
                print("vehicle exploded")
                RemoveVirtualVehicle(id)
                vehicle:Remove()
            end
        end
    end
end

function ClearVirtualVehicleNodes(entity)
    entity:SetValue("road_id", 0)
    entity:SetValue("next_road_id", 0)
    entity:SetValue("next_next_road_id", nil)
end

function OnVehicleInfo(vehicle_info)
    local virtual_vehicle = WorldNetworkObject.GetById(vehicle_info.virtual_vehicle_id)
    if virtual_vehicle then
        virtual_vehicle:SetValue("top_speed", vehicle_info.top_speed)
    end
end

function PlayerChat(args)
    if DEV_MODE then
        local cmd_args = args.text:split(" ")
        if cmd_args[1] == "config" then
            HandleConfigChatCommand(cmd_args)
        end
    end
    return true
end

function RemoveVirtualVehicle(id)
    local entity = WorldNetworkObject.GetById(id)
    if entity then
        virtual_vehicles[id] = nil
        entity:Remove()
        if CONFIG.create_new_vehicle_when_stolen then
            local node = GetRandomRoadNode(navmesh)
            local new_entity = CreateVirtualVehicle(node)
        end
    end
end

function OnVehicleOutOfBounds(args)
    local vehicle = Vehicle.GetById(args.vehicle_id)
    if IsValid(vehicle) then
        local virtual_vehicle_id = vehicle:GetValue("virtual_vehicle_id")
        if virtual_vehicle_id then
            local virtual_vehicle = WorldNetworkObject.GetById(virtual_vehicle_id)
            if virtual_vehicle then
                local top_speed = virtual_vehicle:GetValue("top_speed")
                top_speed = math.max(5, top_speed - 3)
                if top_speed <= 5 then
                    RemoveVirtualVehicle(virtual_vehicle_id)
                else
                    virtual_vehicle:SetValue("top_speed", top_speed)
                    virtual_vehicle:SetValue("slow_time", Server:GetElapsedSeconds() + CONFIG.stop_duration)
                end
            end
        end
    end
end

function PlayerEnterVehicle(args)
    local virtual_vehicle_id = args.vehicle:GetValue("virtual_vehicle_id")
    if args.is_driver and virtual_vehicle_id then
        RemoveVirtualVehicle(virtual_vehicle_id)
    end
end

function OnDamageTrafficVehicle(args)
    local vehicle = Vehicle.GetById(args.vehicle_id)
    if IsValid(vehicle) then
        local health = vehicle:GetHealth()
        health = math.max(0, health - args.damage)
        vehicle:SetHealth(health)
        if health <= 0.2 then
            vehicle:SetValue("explode_time", Server:GetElapsedSeconds() + 20)
            local virtual_vehicle_id = vehicle:GetValue("virtual_vehicle_id")
            if virtual_vehicle_id then
                RemoveVirtualVehicle(virtual_vehicle_id)
            end
        end
    end
end

function PrintIfNearPlayer(msg, pos)
    local is_near = false
    for player in Server:GetPlayers() do
        if IsWithinDistance(player:GetPosition(), pos, 35) then
            is_near = true
            break
        end
    end
    if is_near then
        print(msg)
    end
end

Events:Subscribe("ModuleLoad", ModuleLoad)
Events:Subscribe("ModuleUnload", ModuleUnload)
Network:Subscribe("VehicleInfo", OnVehicleInfo)
Network:Subscribe("VehicleOutOfBounds", OnVehicleOutOfBounds)
Network:Subscribe("DamageTrafficVehicle", OnDamageTrafficVehicle)