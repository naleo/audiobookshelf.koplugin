local H = { tests = {}, passed = 0, failures = 0 }

local function show(v)
    if type(v) == "table" then
        local parts = {}
        for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(x) end
        table.sort(parts)
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return tostring(v)
end

function H.test(name, fn)
    H.tests[#H.tests + 1] = { name = name, fn = fn }
end

function H.eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "values differ") .. ": expected " .. show(expected) .. ", got " .. show(actual), 2)
    end
end

function H.truthy(v, msg)
    if not v then error(msg or "expected a truthy value", 2) end
end

function H.run()
    for _, t in ipairs(H.tests) do
        local ok, err = pcall(t.fn)
        if ok then
            H.passed = H.passed + 1
            print("PASS " .. t.name)
        else
            H.failures = H.failures + 1
            print("FAIL " .. t.name .. "\n     " .. tostring(err))
        end
    end
    print(string.format("%d passed, %d failed", H.passed, H.failures))
    return H.failures == 0
end

return H
