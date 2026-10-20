local H = require("harness")

-- Device-side files cannot run off-device, so guard the one bug class that bit us:
-- a loop variable named `_` shadows gettext's `_`, and calling `_("...")` inside
-- such a loop raises "attempt to call local '_' (a number value)" in KOReader.
H.test("no gettext call inside a loop whose variable is named _", function()
    for file in io.popen("ls main.lua audiobookshelf/*.lua"):lines() do
        local lines = {}
        for l in io.lines(file) do lines[#lines + 1] = l end
        for i = 1, #lines do
            local indent = lines[i]:match("^(%s*)for%s+_%s*,")
            if indent then
                local j = i + 1
                while j <= #lines and not lines[j]:match("^" .. indent .. "end") do
                    if lines[j]:find("[^%w_]_%(") or lines[j]:find("^%s*_%(") then
                        error(file .. ":" .. j .. ": _() called inside `for _,` loop opened at line " .. i)
                    end
                    j = j + 1
                end
            end
        end
    end
end)
