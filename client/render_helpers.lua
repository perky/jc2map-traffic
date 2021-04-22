function RenderWorldSpaceCircle(position, angle, radius, color, fill)
    local transform = Transform3()
    transform:Translate(position)
    transform:Rotate(angle)
    Render:SetTransform(transform)
    if fill then
        Render:FillCircle(Vector3.Zero, radius, color)
    else
        Render:DrawCircle(Vector3.Zero, radius, color)
    end
    Render:ResetTransform()
end

function RenderWorldSpaceText(position, text, font_size, color)
    local text_size = Render:GetTextSize( text, font_size )
    local transform = Transform3()
    transform:Translate(position)
    transform:Scale( 0.01 )
    local text_angle = Angle( Camera:GetAngle().yaw, 0, math.pi ) * Angle( math.pi, 0, 0 )
    transform:Rotate(text_angle)
    transform:Translate( -Vector3( text_size.x, text_size.y, 0 )/2 )
    Render:SetTransform(transform)
    Render:DrawText(Vector3.Zero, text, color, font_size)
    Render:ResetTransform()
end