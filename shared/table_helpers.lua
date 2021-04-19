
function DumpTable(prefix, tbl)
    for k,v in pairs(tbl) do
        if type(v) == "table" then
            local next_prefix = prefix .. "::" .. tostring(k)
            DumpTable(next_prefix, v)
        else
            print(prefix .. " -> " .. tostring(k) .. ": " .. tostring(v))
        end
    end
end

function TableContains(haystack, needle)
    local found = false
    for i,v in ipairs(haystack) do
        if v == needle then
            found = true
            break
        end
    end
    return found
end