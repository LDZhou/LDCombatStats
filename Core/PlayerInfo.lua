--[[
    Light Damage - PlayerInfo.lua
    队伍玩家信息扫描器 (装等、大秘境评分)
]]

local addonName, ns = ...

ns.PlayerInfoCache = {}

local inspectScanner = CreateFrame("Frame")
inspectScanner:RegisterEvent("GROUP_ROSTER_UPDATE")
inspectScanner:RegisterEvent("PLAYER_ENTERING_WORLD")
inspectScanner:RegisterEvent("INSPECT_READY")

-- 当前 pending 的 inspect 状态
local currentInspectUnit = nil
local currentInspectGUID = nil

inspectScanner:SetScript("OnUpdate", function(self, elapsed)
    self.timer = (self.timer or 0) + elapsed
    if self.timer < 0.5 then return end   -- 2.0 → 0.5, 4× 加速
    self.timer = 0
    if InCombatLockdown() then return end

    -- ★ 用户正在观察队友时让出 inspect 通道
    if InspectFrame and InspectFrame:IsShown() then
        -- 顺便清掉自己 pending 的状态，防止干扰
        if currentInspectUnit then
            currentInspectUnit = nil
            currentInspectGUID = nil
        end
        return
    end

    local prefix = IsInRaid() and "raid" or "party"
    local num = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
    local units = {"player"}
    for i = 1, num do table.insert(units, prefix..i) end

    -- Phase 1: 不需要 inspect 的字段 (score + 自己的 ilvl), 一次性全队扫描
    for _, unit in ipairs(units) do
        if UnitExists(unit) and UnitIsConnected(unit) and UnitIsPlayer(unit) then
            local guid = UnitGUID(unit)
            if guid then
                ns.PlayerInfoCache[guid] = ns.PlayerInfoCache[guid] or { score = 0, ilvl = 0, lastInspect = 0 }
                local c = ns.PlayerInfoCache[guid]

                if c.score == 0 and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
                    local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
                    if summary and summary.currentSeasonScore then
                        c.score = summary.currentSeasonScore
                    end
                end

                if unit == "player" and c.ilvl == 0 then
                    local _, equipped = GetAverageItemLevel()
                    c.ilvl = math.floor(equipped or 0)
                end
            end
        end
    end

    -- Phase 2: inspect (一次只能一个 pending)
    if currentInspectUnit and (GetTime() - (self.lastInspect or 0)) > 5 then
        ClearInspectPlayer()
        currentInspectUnit = nil
        currentInspectGUID = nil
    end
    if currentInspectUnit then return end

    for _, unit in ipairs(units) do
        if unit ~= "player" and UnitExists(unit) and UnitIsConnected(unit) and UnitIsPlayer(unit) then
            local guid = UnitGUID(unit)
            if guid then
                local c = ns.PlayerInfoCache[guid]
                -- 稳定锁:成功一次就再不重发, 避免覆盖/碰撞
                if c and c.ilvl == 0 and CanInspect(unit) then
                    self.lastInspect = GetTime()
                    currentInspectUnit = unit
                    currentInspectGUID = guid
                    NotifyInspect(unit)
                    return
                end
            end
        end
    end
end)

inspectScanner:SetScript("OnEvent", function(self, event, guid)
    if event == "INSPECT_READY" then
        -- ★ 只处理自己发起的 inspect，别人的事件直接放过
        if not currentInspectGUID then return end
        if currentInspectGUID ~= guid then return end

        local c = ns.PlayerInfoCache[guid]
        if c and currentInspectUnit and UnitExists(currentInspectUnit) then
            local ilvl = C_PaperDollInfo.GetInspectItemLevel(currentInspectUnit)
            if ilvl then c.ilvl = math.floor(ilvl) end
            c.lastInspect = GetTime()
        end

        -- ★ 只在 InspectFrame 没打开时清——打开时让暴雪自己管
        if not (InspectFrame and InspectFrame:IsShown()) then
            ClearInspectPlayer()
        end
        currentInspectUnit = nil
        currentInspectGUID = nil
    end
end)