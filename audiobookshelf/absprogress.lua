local M = { FINISHED_WITHIN = 10 }

function M.body(current, duration)
    duration = tonumber(duration) or 0
    current = tonumber(current) or 0
    if duration < 0 then duration = 0 end
    if current < 0 then current = 0 end
    if duration > 0 and current > duration then current = duration end
    local progress = 0
    if duration > 0 then progress = current / duration end
    return {
        currentTime = current,
        duration = duration,
        progress = progress,
        isFinished = duration > 0 and (duration - current) <= M.FINISHED_WITHIN,
    }
end

return M
