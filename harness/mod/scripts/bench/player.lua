-- Benchmark driver (player script): fixed static camera above the player, HUD hidden.
local camera = require('openmw.camera')
local self = require('openmw.self')
local util = require('openmw.util')
local I = require('openmw.interfaces')

local cfg = nil

local function onFrame(dt)
    if not cfg then return end
    if camera.getMode() ~= camera.MODE.Static then
        camera.setMode(camera.MODE.Static, true)
    end
    -- Park the camera ahead of the player (along its heading) so the player model stays out of frame.
    local yaw = math.rad(cfg.yaw or 0)
    local ahead = util.vector3(math.sin(yaw), math.cos(yaw), 0) * (cfg.ahead or 180)
    camera.setStaticPosition(self.position + ahead + util.vector3(0, 0, cfg.camh or 110))
    camera.setYaw(math.rad(cfg.yaw or 0))
    camera.setPitch(math.rad(cfg.pitch or 0))
end

local function onBenchCamera(c)
    cfg = c
    camera.showCrosshair(false)
    if I.UI and I.UI.setHudVisibility then I.UI.setHudVisibility(false) end
    -- UI station: open the inventory (character preview render-to-texture) and the map windows.
    if c.ui and I.UI and I.UI.setMode then I.UI.setMode('Interface', { windows = { 'Inventory', 'Map' } }) end
    print(string.format('BENCH camera station=%s yaw=%s pitch=%s', tostring(c.station), tostring(c.yaw), tostring(c.pitch)))
end

return {
    engineHandlers = { onFrame = onFrame },
    eventHandlers = { BenchCamera = onBenchCamera },
}
