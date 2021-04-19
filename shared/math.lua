function Vector3Lerp(a, b, t)
    local x = math.lerp(a.x, b.x, t)
    local y = math.lerp(a.y, b.y, t)
    local z = math.lerp(a.z, b.z, t)
    return Vector3(x, y, z)
end

function Vector3ToTable( vec )
    return {x = vec.x, y = vec.y, z = vec.z}
end

function TableToVector3( t )
    if type(t) == 'table' then
    	if t and t.x and t.y and t.z then
        	return Vector3( t.x, t.y, t.z )
        end
    end
    return nil
end

function IsWithinDistance(a, b, threshold)
    return Vector3.DistanceSqr(a, b) <= (threshold * threshold)
end

function WrapRadianToDegrees(theta)
    local deg = math.deg(theta)
    if deg < 0 then
        return -deg
    else
        return 360 - deg
    end
end

function DegreesDifference(theta1, theta2)
    return (theta2 - theta1 + 180) % 360 - 180
end

function CalcPID(pid_state, pid_vals, target, input, dt)
    local error_val = input - target
    -- Proportional
    local p_val = pid_vals.p * error_val
    -- Integral
    pid_state.integral = pid_state.integral + (error_val * dt)
    local i_val = pid_vals.i * pid_state.integral
    -- Derivative
    local derivative = (error_val - pid_state.last_error_val) / dt
    local d_val = pid_vals.d * derivative
    
    local result = p_val + i_val + d_val

    if result > pid_vals.max then
        result = pid_vals.max
    elseif result < pid_vals.min then
        result = pid_vals.min
    end

    pid_state.last_error_val = error_val
    return result * pid_vals.ratio
end

function MakePIDState()
    return {
        integral = 0,
        last_error_val = 0
    }
end