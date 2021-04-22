DEV_MODE = false

CONFIG = {
    -- Server configs
    max_virtual_vehicles = 1000,
    stream_distance = 800,
    speed_multiplier = 0.8,
    uphill_slower = 0.55,
    default_top_speed = 30,
    stuck_check_distance = 1.5,
    stuck_check_interval = 3,
    create_new_vehicle_when_stolen = false,
    turn_dot_to_slow = 0.25,
    turn_slow_duration = 1.8,
    turn_slow_ratio = 0.3,
    turn_slow_distance = 25,
    stop_duration = 2,

    -- Road speed limits
    base_virtual_speed = 19,
    highway_speed = 28,
    rural_slow_speed = 14,
    rural_fast_speed = 22,
    
    -- Client configs
    max_client_dist_from_virtual = 110,
    debug_draw = 0,
    minimap_draw = 0,
    turn_target_ahead = 3,
    min_dist_to_turn = 0.5,

    -- PID values
    -- see https://en.wikipedia.org/wiki/PID_controller for information
    -- PID ratio is a multiplier of the final PID output.
    pos_pid_p = 0.05,
    pos_pid_i = 0.0005,
    pos_pid_d = 0.02,
    pos_pid_min = -8,
    pos_pid_max = 8,
    pos_pid_ratio = 3,

    speed_pid_p = 1,
    speed_pid_i = 0.01,
    speed_pid_d = 0.01,
    speed_pid_min = -1.0,
    speed_pid_max = 1.0,
    speed_pid_ratio = -1,

    turn_pid_p = 0.009,
    turn_pid_i = 0.00001,
    turn_pid_d = 0.00001,
    turn_pid_min = -1,
    turn_pid_max = 1,
    turn_pid_ratio = 1
}

function HandleConfigChatCommand(cmd_args)
    local key = cmd_args[2]
    local value = tonumber(cmd_args[3])
    CONFIG[key] = value
    print("Set Config: " .. key .. " to " .. tostring(value))
end