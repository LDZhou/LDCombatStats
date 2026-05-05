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
    if self.timer < 2 then return end
    self.timer = 0
    if InCombatLockdown() then return end

    -- 超时保护: pending inspect 超过 5 秒还没回应, 强制清理
    -- 防止 INSPECT_READY 因目标离线/跨阶段/距离过远等原因永不返回, 导致后续永久卡死
    if currentInspectUnit and (GetTime() - (self.lastInspect or 0)) > 5 then
        ClearInspectPlayer()
        currentInspectUnit = nil
        currentInspectGUID = nil
    end
    -- 已经有 pending 的 inspect, 本轮跳过
    if currentInspectUnit then return end

    local prefix = IsInRaid() and "raid" or "party"
    local num = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
    local units = {"player"}
    for i = 1, num do table.insert(units, prefix..i) end

    for _, unit in ipairs(units) do
        if UnitExists(unit) and UnitIsConnected(unit) and UnitIsPlayer(unit) then
            local guid = UnitGUID(unit)
            if guid then
                ns.PlayerInfoCache[guid] = ns.PlayerInfoCache[guid] or { score = 0, ilvl = 0, lastInspect = 0 }
                local c = ns.PlayerInfoCache[guid]

                -- 1. 大秘境评分 (不需要 Inspect)
                if c.score == 0 and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
                    local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
                    if summary and summary.currentSeasonScore then
                        c.score = summary.currentSeasonScore
                    end
                end

                -- 2. 装等
                if unit == "player" then
                    local _, equipped = GetAverageItemLevel()
                    c.ilvl = math.floor(equipped or 0)
                else
                    -- 队友装等需要 inspect; 30秒一次
                    local needsInspect = (c.ilvl == 0) or ((GetTime() - (c.lastInspect or 0)) > 30)
                    if needsInspect and CanInspect(unit) then
                        self.lastInspect = GetTime()
                        currentInspectUnit = unit
                        currentInspectGUID = guid  -- 用 GUID 比对而不是 unit token, 防止队友重排
                        NotifyInspect(unit)
                        return
                    end
                end
            end
        end
    end
end)

inspectScanner:SetScript("OnEvent", function(self, event, guid)
    if event == "INSPECT_READY" then
        -- 直接用事件返回的 guid 比对, 不依赖 unit token
        if currentInspectGUID and currentInspectGUID == guid then
            local c = ns.PlayerInfoCache[guid]
            if c and currentInspectUnit and UnitExists(currentInspectUnit) then
                local ilvl = C_PaperDollInfo.GetInspectItemLevel(currentInspectUnit)
                if ilvl then c.ilvl = math.floor(ilvl) end
                c.lastInspect = GetTime()
            end
        end
        ClearInspectPlayer()
        currentInspectUnit = nil
        currentInspectGUID = nil
    end
end)