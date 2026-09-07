-- Benchmark driver (global script). The station is selected by the cell the game
-- was started in via `--start "<cell>"`; each station pins weather + time of day,
-- teleports the player to a fixed spot and tells the player script where to put
-- the camera. Route stations hop between points to exercise cell streaming.
local world = require('openmw.world')
local core = require('openmw.core')
local util = require('openmw.util')

local CELL = 8192

local STATIONS = {
    ['seyda neen'] = {
        name = 'seyda', region = 'Bitter Coast Region', weather = 'clear', hour = 10,
        pos = util.vector3(-11200, -70700, 400), yaw = 160, pitch = 4, camh = 110,
    },
    ['balmora'] = {
        name = 'balmora', region = 'West Gash Region', weather = 'clear', hour = 10,
        pos = util.vector3(-19264, -16528, 200), yaw = 0, pitch = 2, camh = 110,
    },
    ['vivec, arena'] = {
        name = 'vivec', region = 'Ascadian Isles Region', weather = 'clear', hour = 10,
        pos = util.vector3(38330, -86700, 2400), yaw = 180, pitch = 12, camh = 450,
    },
    ['ald-ruhn'] = {
        name = 'aldruhn', region = 'Ashlands Region', weather = 'clear', hour = 10,
        pos = util.vector3(-13000, 52500, 3000), yaw = 330, pitch = 14, camh = 700,
    },
    ['grazelands region'] = {
        name = 'grazelands', region = 'Grazelands Region', weather = 'clear', hour = 10,
        pos = util.vector3(86016, 86016, 3000), yaw = 0, pitch = 4, camh = 300,
    },
    ['pelagiad'] = {
        -- Sky station: camera pitched up over open ground to compare sky/cloud rendering.
        name = 'sky', region = 'Ascadian Isles Region', weather = 'clear', hour = 10,
        pos = util.vector3(2000, -57000, 2000), yaw = 0, pitch = -60, camh = 400,
    },
    ['balmora, guild of mages'] = {
        -- UI station: inventory (character preview) + local/global map windows open over an interior.
        name = 'ui', yaw = 0, pitch = 0, camh = 110, ahead = 30, ui = true,
    },
    ['vivec, foreign quarter lower waistworks'] = {
        name = 'interior', yaw = 90, pitch = 0, camh = 110, ahead = 30,
    },
    ['bitter coast region'] = {
        -- Continuous glide along the Seyda Neen -> Balmora corridor at a fixed speed, so the
        -- engine's predictive cell preloader (which extrapolates from per-frame movement) gets
        -- a fair test. The camera follows the player; z is snapped to ground each step.
        name = 'route', region = 'Bitter Coast Region', weather = 'clear', hour = 10,
        yaw = 0, pitch = 6, camh = 250, speed = 1000,
        route = {
            { -11000, -70000 }, { -11000, -62000 }, { -13000, -54000 }, { -15000, -46000 },
            { -17000, -38000 }, { -19000, -30000 }, { -19000, -22000 }, { -19264, -16528 },
        },
    },
}

local state = { frame = 0, station = nil, player = nil, ready = false, routeIdx = 1, routeT = 0, cellsEntered = 0, lastCell = nil }

local function log(fmt, ...)
    print(string.format('BENCH ' .. fmt, ...))
end

local function teleportTo(player, x, y, z, yawDeg)
    local cell = world.getExteriorCell(math.floor(x / CELL), math.floor(y / CELL))
    player:teleport(cell, util.vector3(x, y, z), {
        onGround = true,
        rotation = util.transform.rotateZ(math.rad(yawDeg or 0)),
    })
end

local function setup(player, st)
    if st.region and st.weather then
        local rec = core.weather.records[st.weather]
        if rec then
            core.weather.changeWeather(st.region, rec)
        else
            log('WARN weather record %s not found', st.weather)
        end
    end
    if st.hour then
        local hour = (core.getGameTime() / 3600) % 24
        local delta = (st.hour - hour) % 24
        if delta > 0.05 then world.advanceTime(delta) end
    end
    if st.route then
        state.routeIdx = 1
        teleportTo(player, st.route[1][1], st.route[1][2], 2000, st.yaw)
    elseif st.pos then
        teleportTo(player, st.pos.x, st.pos.y, st.pos.z, st.yaw)
    end
    player:sendEvent('BenchCamera', { yaw = st.yaw, pitch = st.pitch, camh = st.camh, ahead = st.ahead, station = st.name, ui = st.ui })
end

local function onUpdate(dt)
    state.frame = state.frame + 1
    if not state.player then
        state.player = world.players[1]
        if not state.player then return end
        -- Unnamed exterior cells report an empty name; fall back to the region id so wilderness
        -- stations can be keyed by region ("Grazelands Region", "Bitter Coast Region").
        local cell = state.player.cell
        local cellName = cell and cell.name or ''
        if cellName == '' and cell and cell.region then cellName = cell.region end
        cellName = cellName:lower()
        state.station = STATIONS[cellName]
        if not state.station then
            log('no station for start cell "%s"', cellName)
            return
        end
        log('station=%s startcell="%s" frame=%d', state.station.name, cellName, state.frame)
        return
    end
    local st = state.station
    if not st then return end
    -- Give the engine a few frames to finish placing the player before we touch the world.
    if state.frame == 10 then
        setup(state.player, st)
        return
    end
    if state.frame == 40 and not state.ready then
        world.setGameTimeScale(0)
        state.ready = true
        log('station=%s ready frame=%d simtime=%.2f', st.name, state.frame, core.getSimulationTime())
    end
    if state.ready and st.route then
        -- Glide: advance a parameter along the current segment at st.speed units/s and place the
        -- player there each frame (ground-snapped). Wraps to the start when the route ends.
        local a, b = st.route[state.routeIdx], st.route[state.routeIdx + 1]
        if not b then
            state.routeIdx, state.routeT = 1, 0
            a, b = st.route[1], st.route[2]
            log('route wrap simtime=%.2f cells=%d', core.getSimulationTime(), state.cellsEntered)
        end
        local dx, dy = b[1] - a[1], b[2] - a[2]
        local len = math.sqrt(dx * dx + dy * dy)
        state.routeT = state.routeT + st.speed * dt
        if state.routeT >= len then
            state.routeT = state.routeT - len
            state.routeIdx = state.routeIdx + 1
            return
        end
        local f = state.routeT / len
        local x, y = a[1] + dx * f, a[2] + dy * f
        local yaw = math.deg(math.atan2(dx, dy))
        teleportTo(state.player, x, y, 3000, yaw)
        local cell = state.player.cell
        local key = cell and (cell.gridX .. ',' .. cell.gridY) or ''
        if key ~= state.lastCell then
            state.lastCell = key
            state.cellsEntered = state.cellsEntered + 1
            log('route cell=%s pos=(%d,%d) simtime=%.2f', key, x, y, core.getSimulationTime())
        end
    end
end

return {
    engineHandlers = { onUpdate = onUpdate },
}
