-- TRAFFIC (client) by Luke Perkin (luke@locogame.co.uk)
-- This script used the JCMP-AI script from jaxm as a reference.

local virtual_vehicles = {}
local flat_angle = Angle(0, math.pi/2, 0)

function RenderDebugInfo(args)
    if (not DEV_MODE) or CONFIG.debug_draw ~= 1 then return end

    for id, virtual_vehicle in pairs(virtual_vehicles) do
        local obj = WorldNetworkObject.GetById(virtual_vehicle.object_id)
        local pos = obj:GetPosition() + Vector3(0, 1.0, 0)
        if IsWithinDistance(pos, LocalPlayer:GetPosition(), 400) then 
            RenderWorldSpaceCircle(pos, flat_angle, 0.5, Color.Red, true)
            Render:DrawLine(pos, pos + virtual_vehicle.velocity, Color.Red)
        end
    end
    
    for vehicle in Client:GetVehicles() do
        if vehicle:IsValid() then
            local vpos = vehicle:GetPosition()
            local virtual_id = vehicle:GetValue("virtual_vehicle_id")
            local npc_input = vehicle:GetValue("npc_input")
            
            if virtual_id 
            and npc_input 
            and IsWithinDistance(LocalPlayer:GetPosition(), vpos, 120) 
            then
                Render:DrawLine(vpos, vpos + Vector3(0, 5, 0), Color.Red)
                local txt = string.format("top_speed: %.2f\npos_in: %.3f\nspeed_in: %.3f\naccel_in: %.3f\nspeed_cur: %.3f\nspeed_t: %.3f", 
                    vehicle:GetTopSpeed(),
                    npc_input.pos_correction, 
                    npc_input.speed_correction, 
                    npc_input.accelerate_amount,
                    vehicle:GetLinearVelocity():Length(),
                    npc_input.target_speed)
                RenderWorldSpaceText(vpos + Vector3(0, 5, 0), txt, 40, Color.White)
            end
        end
    end
end

function RenderHUD(args)
    if CONFIG.minimap_draw ~= 1 then return end

    for id, virtual_vehicle in pairs(virtual_vehicles) do
        local minimap_pos, onscreen = Render:WorldToMinimap(virtual_vehicle.position)
        Render:FillCircle(minimap_pos, 3, Color.White)
    end
end

function OnPostTick(args)
    local dt = args.delta
    for id, virtual_vehicle in pairs(virtual_vehicles) do
        local object = WorldNetworkObject.GetById(virtual_vehicle.object_id)
        if object then
            virtual_vehicle.position = object:GetPosition()
            virtual_vehicle.direction = object:GetValue("direction")
            virtual_vehicle.speed = object:GetValue("speed")
            virtual_vehicle.velocity = virtual_vehicle.direction * virtual_vehicle.speed
        end
    end

    -- Create PID values.
    -- These are constructed in tick so they can be easily modified during runtime.
    local pos_pid_vals = {
        p = CONFIG.pos_pid_p,
        i = CONFIG.pos_pid_i,
        d = CONFIG.pos_pid_d,
        min = CONFIG.pos_pid_min,
        max = CONFIG.pos_pid_max,
        ratio = CONFIG.pos_pid_ratio
    }
    local speed_pid_vals = {
        p = CONFIG.speed_pid_p,
        i = CONFIG.speed_pid_i,
        d = CONFIG.speed_pid_d,
        min = CONFIG.speed_pid_min,
        max = CONFIG.speed_pid_max,
        ratio = CONFIG.speed_pid_ratio
    }
    local turn_pid_vals = {
        p = CONFIG.turn_pid_p,
        i = CONFIG.turn_pid_i,
        d = CONFIG.turn_pid_d,
        min = CONFIG.turn_pid_min,
        max = CONFIG.turn_pid_max,
        ratio = CONFIG.turn_pid_ratio
    }

    local valid_vehicles = {}
    for vehicle in Client:GetVehicles() do
        if IsValid(vehicle) then
            local virtual_id = vehicle:GetValue("virtual_vehicle_id")
            local is_driver = (IsValid(LocalPlayer:GetVehicle()) 
                               and LocalPlayer:GetVehicle() == vehicle
                               and LocalPlayer:GetSeat() == VehicleSeat.Driver)
            
            if virtual_id and (not is_driver) then
                local virtual_vehicle = virtual_vehicles[virtual_id]
                if virtual_vehicle and (not virtual_vehicle.stolen) then
                    table.insert(valid_vehicles, {vehicle, virtual_vehicle})
                end
            end
        end
    end
    
    for _, vehicle_pair in ipairs(valid_vehicles) do
        local vehicle = vehicle_pair[1]
        local virtual_vehicle = vehicle_pair[2]
        
        local npc = ClientActor.GetById(virtual_vehicle.npc_id)
        if IsValid(npc) then
            local virtual_vehicle_object = WorldNetworkObject.GetById(virtual_vehicle.object_id)

            -- The NPC enters the vehicle once.
            if (not npc:GetVehicle()) and (not vehicle:GetValue("has_npc")) then
                npc:SetPosition(vehicle:GetPosition())
                npc:EnterVehicle(vehicle, VehicleSeat.Driver)
                vehicle:SetValue("has_npc", true)
                Network:Send("VehicleInfo", {
                    vehicle_id = vehicle:GetId(),
                    virtual_vehicle_id = virtual_vehicle.object_id,
                    top_speed = vehicle:GetTopSpeed(),
                    max_rpm = vehicle:GetMaxRPM(),
                    mass = vehicle:GetMass()
                })
            end

            local target_pos = virtual_vehicle_object:GetPosition()
            local dist = Vector3.Distance(vehicle:GetPosition(), target_pos)
            if dist > CONFIG.max_client_dist_from_virtual then
                -- teleport to target position if too far away
                vehicle:SetPosition(target_pos + Vector3(0, 2.5, 0))
                vehicle:SetAngle(Angle.FromVectors(Vector3.Forward, virtual_vehicle.direction))
                vehicle:SetLinearVelocity(virtual_vehicle.direction * virtual_vehicle.speed)
                virtual_vehicle.pos_pid = MakePIDState()
                virtual_vehicle.speed_pid = MakePIDState()
                virtual_vehicle.turn_pid = MakePIDState()
            else
                -- This is the meat of the NPC traffic logic right here.
                local pos_correction = CalcPID(virtual_vehicle.pos_pid, 
                                               pos_pid_vals, 
                                               0, 
                                               dist, 
                                               dt)
                local is_ahead = Vector3.Dot((target_pos - vehicle:GetPosition()):Normalized(), virtual_vehicle.direction) < 0
                if is_ahead then
                    pos_correction = pos_correction * -1
                end
                local speed_correction = CalcPID(virtual_vehicle.speed_pid, 
                                                 speed_pid_vals, 
                                                 (virtual_vehicle.speed + 0.7 + pos_correction), 
                                                 vehicle:GetLinearVelocity():Length(), 
                                                 dt)
                local accelerate_amount = speed_correction
                local action = Action.Accelerate
                if accelerate_amount < 0 then
                    action = Action.Reverse
                end
                npc:ClearInput()
                npc:SetInput(action, math.min(math.abs(accelerate_amount), 1))

                local target_turn_to_pos = target_pos + (virtual_vehicle.direction * CONFIG.turn_target_ahead)
                local dir_to_target = (target_turn_to_pos - vehicle:GetPosition()):Normalized()
                local target_angle = Angle.FromVectors(Vector3.Forward, dir_to_target)
                local vehicle_heading = WrapRadianToDegrees(vehicle:GetAngle().yaw)
                local target_heading = WrapRadianToDegrees(target_angle.yaw)
                local delta_yaw = DegreesDifference(vehicle_heading, target_heading)
                local turn_amount = CalcPID(virtual_vehicle.turn_pid, turn_pid_vals, 0, delta_yaw, dt)
                if math.abs(delta_yaw) > 0 and dist >= CONFIG.min_dist_to_turn then
                    local turn_action = Action.TurnLeft
                    if delta_yaw > 0 then
                        turn_action = Action.TurnRight
                    end
                    npc:SetInput(turn_action, math.abs(turn_amount))
                end
                -- End meatiness.

                if DEV_MODE then
                    vehicle:SetValue("npc_input", {
                        pos_correction = pos_correction,
                        speed_correction = speed_correction,
                        accelerate_amount = accelerate_amount,
                        target_speed = virtual_vehicle.speed
                    })
                end
            end
        end
    end
end

function PlayerEnterVehicle(args)
    if args.is_driver then
        local virtual_id = args.vehicle:GetValue("virtual_vehicle_id")
        local virtual_vehicle = virtual_vehicles[virtual_id]
        if virtual_vehicle then
            local npc = ClientActor.GetById(virtual_vehicle.npc_id)
            if IsValid(npc) then
                npc:ClearInput()
                npc:SetHealth(0)
            end
            virtual_vehicle.stolen = true
        end
    end
end

function OnVirtualVehicleStreamIn(id, object)
    local npc = ClientActor.Create(AssetLocation.Game, {
        model_id = 1,
        position = object:GetPosition(),
        angle = Angle(0,0,0)
    })
    virtual_vehicles[id] = {
        object_id = id,
        position = object:GetPosition(),
        direction = Vector3.Forward,
        velocity = Vector3.Zero,
        last_pos = Vector3.Zero,
        pos_pid = MakePIDState(),
        speed_pid = MakePIDState(),
        turn_pid = MakePIDState(),
        npc_id = npc:GetId()
    }
end

function OnVirtualVehicleStreamOut(id, object)
    local virtual_vehicle = virtual_vehicles[id]
    if virtual_vehicle then
        local npc = ClientActor.GetById(virtual_vehicle.npc_id)
        if IsValid(npc) then
            npc:ExitVehicle()
            npc:Remove()
        end
    end
    virtual_vehicles[id] = nil
end

function LocalPlayerChat(args)
    if DEV_MODE then
        local cmd_args = args.text:split(" ")
        if cmd_args[1] == "config" then
            HandleConfigChatCommand(cmd_args)
        end
    end
    return true
end

function TrafficModuleLoad()
    if DEV_MODE then
        Events:Subscribe("GameRenderOpaque", RenderDebugInfo)
    end
    
    Events:Subscribe("PostTick", OnPostTick)
    Events:Subscribe("Render", RenderHUD)
    Events:Subscribe("PlayerEnterVehicle", PlayerEnterVehicle)
    Events:Subscribe("LocalPlayerEnterVehicle", PlayerEnterVehicle)
    Events:Subscribe("LocalPlayerChat", LocalPlayerChat)
    Events:Subscribe("WorldNetworkObjectCreate", function(args)
        if args.object:GetValue("type") == "virtual_vehicle" then
            local id = args.object:GetId()
            if virtual_vehicles[id] then return end
            OnVirtualVehicleStreamIn(id, args.object)
        end
    end)
    Events:Subscribe("WorldNetworkObjectDestroy", function(args)
        if args.object:GetValue("type") == "virtual_vehicle" then
            local id = args.object:GetId()
            if not virtual_vehicles[id] then return end
            OnVirtualVehicleStreamOut(id, args.object)
        end
    end)
end

Events:Subscribe("ModuleLoad", TrafficModuleLoad)


