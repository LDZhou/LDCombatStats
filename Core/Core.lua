--[[
    Light Damage - Core.lua
    核心初始化、事件路由、状态管理
]]

local addonName, ns = ...
local L = ns.L

-- 动态获取 .toc 文件中的版本号
local currentVersion = C_AddOns.GetAddOnMetadata(addonName, "Version")
if currentVersion == "@project-version@" then
    currentVersion = "Dev"
end

ns.version   = currentVersion
ns.addonName = addonName

local Core = CreateFrame("Frame")
ns.Core = Core

-- ============================================================
-- 默认配置
-- ============================================================
ns.defaults = {
    collapse = {
        autoCollapse    = false,
        neverInInstance = true,
        delay           = 1.5,
        enableAnim      = true,
        animDuration    = 0.4,
    },
    fade = {
        unfadeOnHover       = true,
        fadeBars            = false,
        barsWhen            = "ooc",
        barsNeverInInstance = false,
        barsAlpha           = 0.3,
        fadeBody            = false,
        bodyWhen            = "ooc",
        bodyNeverInInstance = false,
        bodyAlpha           = 0.15,
        delay               = 1.5,
        enableAnim          = true,
        animDuration        = 0.5,
    },
    window = {
        width = 400, height = 280,
        point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -20, y = 180,
        alpha = 0.92, scale = 1.0, configScale = 1.0, locked = false, visible = true,
        rememberSceneSize = false,
        sceneAnchor = "TOPLEFT",
        sceneSizes = {},
        themeColor = {0, 0.85, 0.85, 0.05},
        bgColor    = {0, 0.7, 0.7, 0},
        ovrBgColor = {1, 1, 1, 0.05},
    },
    detailWindow = {
        width = 380, height = 420,
    },
    detailDisplay = {
        barHeight     = 20,
        barThickness  = 20,
        barVOffset    = 0,
        barGap        = 1,
        barAlpha      = 0.92,
        barTexture    = "Interface\\Buttons\\WHITE8X8",
        font          = STANDARD_TEXT_FONT,
        fontSizeBase  = 10,
        fontOutline   = "OUTLINE",
        fontShadow    = false,
    },
    display = {
        mode          = "split",
        showPerSecond = true,
        showPercent   = true,
        showRank      = true,
        showSpecIcon  = true,
        iconPack      = "default",
        showRealm     = false,
        classColors   = true,
        barHeight     = 19,
        barThickness  = 19,
        barVOffset    = 0,
        barGap        = 1,
        barAlpha      = 0.85,
        barTexture    = "Interface\\Buttons\\WHITE8X8",
        font          = STANDARD_TEXT_FONT,
        fontSizeBase  = 13,
        fontOutline   = "OUTLINE",
        fontShadow    = false,
        textColorMode = "white",
        textColor     = {1.0, 1.0, 1.0},
        alwaysShowSelf = false,
        useShortTabs   = false,
        damageTakenView = "friendly",
    },
    split = {
        enabled           = true,
        splitDir          = "TB",
        primaryMode       = "damage",
        secondaryMode     = "healing",
        primaryPos        = 1,
        splitShowMPlus    = true,
        splitShowRaid     = true,
        splitShowDungeon  = true,
        splitShowOutdoor  = false,
        showOverall       = true,
        overallDir        = "LR",
        currentPos        = 1,
        overallShowMPlus  = true,
        overallShowRaid   = true,
        overallShowDungeon= true,
        overallShowOutdoor= false,
        tbRatio           = 0.55,
        lrRatio           = 0.50,
    },
    mythicPlus = {
        enabled           = true,
        autoSegment       = true,
        autoCleanTrash    = true,
        genOverallMPlus   = true,
        genOverallRaid    = true,
        genOverallDungeon = true,
        cleanTrashMPlus   = true,
        cleanTrashRaid    = true,
        cleanTrashDungeon = true,
    },
    tracking = {
        mergePlayerPets = true,
        autoReset       = false,
        minCombatTime   = 2,
        deathLogSize    = 15,
        maxSegments     = 20,
    },
    smartRefresh = {
        combatInterval = 0.3,
        idleInterval   = 2.0,
    },
    useBlizzMeter = true,
}

-- ============================================================
-- 运行时状态
-- ============================================================
ns.state = {
    inCombat         = false,
    combatStartTime  = 0,
    combatEndTime    = 0,
    isInInstance     = false,
    wasInInstance    = false,
    instanceType     = nil,
    inMythicPlus     = false,
    mythicPlusLevel  = 0,
    playerGUID       = nil,
    playerName       = nil,
    damageTakenView  = nil,
    playerClass      = nil,
}



-- ============================================================
-- 初始化
-- ============================================================
function Core:OnInitialize()
    if not self._initialized then
        self._initialized = true

        -- ★ SavedVariables 迁移 (LDCombatStats → LightDamage)
        --   桥接插件 (AddOns/LDCombatStats) 负责让 WoW 加载旧 SavedVariables，
        --   此处在 PLAYER_LOGIN 时执行实际迁移，对用户完全无感。
        if LDCombatStatsGlobal and type(LDCombatStatsGlobal) == "table" and next(LDCombatStatsGlobal) then
            if not LightDamageGlobal or not next(LightDamageGlobal) or not LightDamageGlobal.profiles then
                LightDamageGlobal = LDCombatStatsGlobal
            end
            LDCombatStatsGlobal = nil
        end
        if LDCombatStatsDB and type(LDCombatStatsDB) == "table" and next(LDCombatStatsDB) then
            if not LightDamageDB or not next(LightDamageDB) then
                LightDamageDB = LDCombatStatsDB
            end
            LDCombatStatsDB = nil
        end

        -- 1. 初始化全局配置库
        if not LightDamageGlobal then LightDamageGlobal = { profiles = {} } end
        if not LightDamageGlobal.profiles["默认"] then
            if LightDamageDB and LightDamageDB.window then
                LightDamageGlobal.profiles["默认"] = {
                    window = CopyTable(LightDamageDB.window),
                    display = CopyTable(LightDamageDB.display),
                    split = CopyTable(LightDamageDB.split),
                    mythicPlus = CopyTable(LightDamageDB.mythicPlus),
                    tracking = CopyTable(LightDamageDB.tracking),
                    smartRefresh = CopyTable(LightDamageDB.smartRefresh),
                    useBlizzMeter = LightDamageDB.useBlizzMeter
                }
            else
                LightDamageGlobal.profiles["默认"] = CopyTable(ns.defaults)
            end
        end

        -- 版本配置自动平滑迁移 (旧版 -> 四宫格新版)
        for pName, profile in pairs(LightDamageGlobal.profiles) do
            local sp = profile.split
            local mp = profile.mythicPlus
            if sp and mp then
                if mp.overallColumnMode ~= nil then
                    sp.showOverall = (mp.overallColumnMode ~= "off")
                    sp.overallShowMode = mp.overallColumnMode
                    mp.overallColumnMode = nil
                    sp.splitDir = "TB"
                    sp.overallDir = "LR"
                    sp.primaryPos = 1
                    sp.currentPos = 1
                    if sp.priRatio then
                        sp.tbRatio = sp.priRatio
                        sp.priRatio = nil
                    end
                    if sp.ovrRatio then
                        sp.lrRatio = 1 - sp.ovrRatio
                        sp.ovrRatio = nil
                    end
                end
            end
        end

        -- 2. 初始化角色数据
        if not LightDamageDB then LightDamageDB = {} end
        if not LightDamageDB.activeProfile or not LightDamageGlobal.profiles[LightDamageDB.activeProfile] then
            LightDamageDB.activeProfile = "默认"
        end

        -- 3. 清理旧的角色级配置数据
        local CONFIG_KEYS = { window=true, display=true, split=true, mythicPlus=true, tracking=true, smartRefresh=true, useBlizzMeter=true, detailWindow=true, detailDisplay=true, collapse=true, fade=true }
        for k in pairs(CONFIG_KEYS) do
            if LightDamageDB[k] then LightDamageDB[k] = nil end
        end

        -- 4. 建立智能代理数据指针 ns.db
        ns.db = setmetatable({}, {
            __index = function(t, k)
                if CONFIG_KEYS[k] then
                    return LightDamageGlobal.profiles[LightDamageDB.activeProfile][k]
                else
                    return LightDamageDB[k]
                end
            end,
            __newindex = function(t, k, v)
                if CONFIG_KEYS[k] then
                    LightDamageGlobal.profiles[LightDamageDB.activeProfile][k] = v
                else
                    LightDamageDB[k] = v
                end
            end
        })

        ns:MergeDefaults(LightDamageGlobal.profiles[LightDamageDB.activeProfile], ns.defaults)

        ns.state.playerGUID = UnitGUID("player")
        ns.state.playerName = UnitName("player")
        local _, classEng   = UnitClass("player")
        ns.state.playerClass = classEng
        ns.state.damageTakenView = ns.db.display.damageTakenView or "friendly"

        if ns.Segments then
            ns.Segments:Init()
            ns:LoadSessionHistory()
        else
            print(L["|cffff3333[Light Damage] ERROR:|r Segments 模块未加载"])
            return
        end

        if ns.MythicPlus   then ns.MythicPlus:Init()   end
        if ns.DeathTracker then ns.DeathTracker:Init()  end
        if ns.Analysis     then ns.Analysis:Init()     end

        C_Timer.After(3, function()
            if ns.CombatTracker and not ns.state.isInInstance then
                local ss  = C_DamageMeter.GetAvailableCombatSessions()
                local cnt = ss and #ss or 0
                if cnt > 0 and ns.CombatTracker._baselineSessionCount == 0 then
                    local latestSess = ss[cnt]
                    local isStale = (latestSess.durationSeconds or 0) == 0
                                and (latestSess.name == nil or latestSess.name == "")
                    if not isStale then
                        local offset = ns.state.inCombat and 1 or 0
                        ns.CombatTracker._baselineSessionCount = math.max(0, cnt - offset)
                        ns.CombatTracker._lastProcessedCount   = math.max(0, cnt - offset)
                        ns.CombatTracker._initialBaselineSet   = true
                    end
                    
                    if ns.Segments and ns.Segments.overall then
                        local hasData = ns.Segments.overall.totalDamage > 0
                                     or ns.Segments.overall.totalHealing > 0
                        if not hasData then
                            ns.Segments.overall.players = {}
                        end
                    end
                end
            end
        end)

        ns:StartSmartRefresh()
        
        -- 自动关闭暴雪原生统计
        C_Timer.After(2, function()
            local possibleCVars = { "damageMeterResetOnNewInstance", "damageMeterEnabled" }
            local setter = (C_CVar and C_CVar.SetCVar) or SetCVar
            for _, cvar in ipairs(possibleCVars) do
                pcall(setter, cvar, "0")
            end
        end)

        -- 注册事件
        local events = {
            "ZONE_CHANGED_NEW_AREA", "ENCOUNTER_START", "ENCOUNTER_END",
            "GROUP_ROSTER_UPDATE", "CHALLENGE_MODE_START",
            "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET",
            "PLAYER_DEAD", "PLAYER_LOGOUT",
        }
        for _, ev in ipairs(events) do self:RegisterEvent(ev) end
        if ns.CombatTracker then ns.CombatTracker:RegisterEvents() end
    end

    -- 无论是不是第一次进世界，都要执行的常规操作
    SLASH_LDCS1 = "/ldcs"
    SLASH_LDCS2 = "/ldstats"
    SLASH_LD1 = "/ld"
    SLASH_LD2 = "/lightdamage"
    SlashCmdList["LDCS"] = function(msg) ns:HandleSlashCommand(msg) end
    SlashCmdList["LD"] = function(msg) ns:HandleSlashCommand(msg) end

    ns:UpdateInstanceStatus()
    ns:InvalidateGUIDCache()

    C_Timer.After(0.1, function()
        if ns.UI then ns.UI:EnsureCreated() end
    end)
end

-- ============================================================
-- 事件路由
-- ============================================================
function Core:OnEvent(event, ...)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        Core:OnInitialize()
        if event == "PLAYER_LOGIN" then return end
    end

    if event == "ENCOUNTER_START" then
        ns:OnEncounterStart(...)
    elseif event == "ENCOUNTER_END" then
        ns:OnEncounterEnd(...)
    elseif event == "PLAYER_ENTERING_WORLD" then
        ns:InvalidateGUIDCache()
        C_Timer.After(0.3, function()
            ns:UpdateInstanceStatus()
            ns:InvalidateGUIDCache()
            if ns.UI and ns.UI:IsVisible() then
                ns.UI:Layout()
                if ns.UI.CheckAutoCollapse then
                    ns.UI:CheckAutoCollapse(true)
                end
            end
        end)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        local wasInInstance = ns.state.isInInstance
        ns:UpdateInstanceStatus()
        ns:InvalidateGUIDCache()

        if wasInInstance and not ns.state.isInInstance then
            if ns.MythicPlus and ns.MythicPlus:IsActive() then
                ns.MythicPlus:OnLeaveInstance()
            end
            if ns.UI then
                C_Timer.After(0.1, function() ns.UI:Layout() end)
            end
        end

        if not wasInInstance and ns.state.isInInstance then
            if not ns.state.inMythicPlus then
                if ns.CombatTracker then
                    ns.CombatTracker:ResetBaselineToCurrentCount()
                end
                if ns.Segments then
                    local name = GetInstanceInfo() or L["副本"]
                    ns.Segments.overall = ns.Segments:NewSegment("overall", string.format(L["%s [全程]"], name))
                end
            end
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        ns:InvalidateGUIDCache()
    elseif event == "CHALLENGE_MODE_START" then
        if ns.MythicPlus then ns.MythicPlus:OnStart(...) end
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        if ns.MythicPlus then ns.MythicPlus:OnCompleted(...) end
    elseif event == "CHALLENGE_MODE_RESET" then
        if ns.MythicPlus then ns.MythicPlus:OnReset() end
    elseif event == "PLAYER_DEAD" then
        if ns.DeathTracker then ns.DeathTracker:OnPlayerDead() end
    elseif event == "PLAYER_LOGOUT" then
        ns:SaveSessionHistory()
    end
end

Core:SetScript("OnEvent", Core.OnEvent)
Core:RegisterEvent("PLAYER_LOGIN")
Core:RegisterEvent("PLAYER_ENTERING_WORLD")

-- ============================================================
-- 战斗状态管理
-- ============================================================
function ns:EnterCombat()
    ns.state.inCombat        = true
    ns.state.combatStartTime = GetTime()
    if ns.Segments then ns.Segments:OnCombatStart() end
    if ns.UI       then ns.UI:OnCombatStateChanged(true) end
end

function ns:LeaveCombat()
    ns.state.inCombat        = false
    ns.state.combatStartTime = 0
    ns.state.combatEndTime   = GetTime()
    if ns.Segments then ns.Segments:OnCombatEnd() end
    if ns.UI       then ns.UI:OnCombatStateChanged(false) end
end

function ns:OnEncounterStart(encounterID, name, difficultyID, groupSize)
    -- LoggingCombat(true)
    if ns.Segments then
        ns.Segments:OnEncounterStart(encounterID, name, difficultyID, groupSize)
    end
end

function ns:OnEncounterEnd(encounterID, name, difficultyID, groupSize, success)
    if ns.Segments then
        ns.Segments:OnEncounterEnd(encounterID, name, difficultyID, groupSize, success)
    end
end

-- ============================================================
-- 智能刷新系统
-- ============================================================
function ns:StartSmartRefresh()
    local elapsed      = 0
    local refreshFrame = CreateFrame("Frame")

    refreshFrame:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        local interval = ns.state.inCombat
            and ns.db.smartRefresh.combatInterval
            or  ns.db.smartRefresh.idleInterval
        if interval < 0.1 then interval = 0.1 end

        if elapsed >= interval then
            elapsed = 0
            if ns.CombatTracker then
                ns.CombatTracker:PullCurrentData()
            end
            if ns.DetailView and ns.DetailView:IsVisible() then
                pcall(function() ns.DetailView:Refresh() end)
            end
        end
    end)
end

-- ============================================================
-- 副本状态检测
-- ============================================================
function ns:UpdateInstanceStatus()
    local inInstance, instanceType = IsInInstance()

    if instanceType == "scenario" or instanceType == "party" or instanceType == "raid" or instanceType == "arena" or instanceType == "pvp" then
        inInstance = true
    end
    if instanceType == "neighborhood" or instanceType == "interior" then
        inInstance = false
    end

    ns.state.wasInInstance = ns.state.isInInstance
    ns.state.isInInstance = inInstance
    ns.state.instanceType = instanceType

    local wasInMPlus      = ns.state.inMythicPlus
    ns.state.inMythicPlus = false

    if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
        local mapID = C_ChallengeMode.GetActiveChallengeMapID()
        ns.state.inMythicPlus = (mapID ~= nil)

        if mapID and C_ChallengeMode.GetActiveKeystoneInfo then
            local ok, level = pcall(function()
                local info = { C_ChallengeMode.GetActiveKeystoneInfo() }
                local lv = info[1]
                if type(lv) ~= "number" or lv <= 0 then lv = info[8] end
                return type(lv) == "number" and lv or 0
            end)
            ns.state.mythicPlusLevel = ok and level or 0
        end
    else
        local _, _, difficultyID = GetInstanceInfo()
        ns.state.inMythicPlus = (difficultyID == 8)
    end

    -- 场景分类器
    local cat = "outdoor"
    if inInstance then
        if instanceType == "raid" then
            cat = "raid"
        elseif instanceType == "party" or instanceType == "scenario" or instanceType == "arena" or instanceType == "pvp" then
            cat = "dungeon"
        end
    end
    if ns.state.inMythicPlus then
        cat = "mplus"
    end
    
    local oldCat = ns.state.instanceCategory
    ns.state.instanceCategory = cat

    -- 跨越场景时自动恢复或降级双栏模式
    if oldCat ~= cat and ns.db and ns.db.split then
        local isActive = false
        if cat == "mplus" and ns.db.split.splitShowMPlus then isActive = true end
        if cat == "raid" and ns.db.split.splitShowRaid then isActive = true end
        if cat == "dungeon" and ns.db.split.splitShowDungeon then isActive = true end
        if cat == "outdoor" and ns.db.split.splitShowOutdoor then isActive = true end

        if isActive and ns.db.split.enabled then
            ns.db.display.mode = "split"
        elseif not isActive and ns.db.display.mode == "split" then
            ns.db.display.mode = ns.db.split.primaryMode or "damage"
        end
    end

    if ns.state.inMythicPlus and not wasInMPlus then
        if ns.MythicPlus then ns.MythicPlus:OnEnterDungeon() end
    end

    -- 按场景记忆窗口尺寸
    if oldCat ~= cat and ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then
        if ns.UI.ApplySceneSize then ns.UI:ApplySceneSize(cat) end
    end

    -- 进出副本时刷新渐隐状态（修复"副本中永不隐藏"不即时生效）
    if oldCat ~= cat and ns.UI and ns.UI.CheckAutoFade then
        ns.UI:CheckAutoFade(true)
    end
end

-- ============================================================
-- 斜杠命令
-- ============================================================
function ns:HandleSlashCommand(msg)
    msg = (msg or ""):lower():trim()

    if msg == "" then
        if ns.Config then ns.Config:Toggle() end

    elseif msg == "help" then
        print(L["|cff00ccff[Light Damage]|r 命令:"])
        print(L["  /ldcs show    - 显示/隐藏窗口"])
        print(L["  /ldcs reset   - 重置所有数据"])
        print(L["  /ldcs config  - 配置面板"])
        print(L["  /ldcs lock    - 锁定/解锁窗口"])

    elseif msg == "show" or msg == "toggle" then
        if ns.UI then ns.UI:Toggle() end

    elseif msg == "reset" then
        if ns.Segments then ns.Segments:ResetAll() end
        print(L["|cff00ccff[Light Damage]|r 数据已重置"])

    elseif msg == "config" then
        if ns.Config then ns.Config:Toggle() end

    elseif msg == "lock" then
        ns.db.window.locked = not ns.db.window.locked
        if ns.UI then ns.UI:UpdateLock() end
        if ns.db.window.locked then
            print(L["|cff00ccff[Light Damage]|r 已锁定"])
        else
            print("|cff00ccff[Light Damage]|r " .. L["已解锁"])
        end

    elseif msg:match("^lang") then
        local langInput = msg:match("lang%s+(%w+)"):lower()
        local targetLang = "zhCN"
        if langInput == "enus" then targetLang = "enUS"
        elseif langInput == "zhtw" then targetLang = "zhTW" end
        if ns.SwitchLanguage then
            ns:SwitchLanguage(targetLang)
            if ns.Config and ns.Config.RefreshUI then ns.Config:RefreshUI() end
        end

    elseif msg == "baseline" then
        if ns.CombatTracker then
            ns.CombatTracker:ResetBaselineToCurrentCount()
            if ns.Segments then
                ns.Segments.overall = ns.Segments:NewSegment("overall", L["总计"])
            end
            print(L["|cff00ccff[Light Damage]|r Baseline 已手动重置"])
        end
    elseif msg == "debug" then
        ns:PrintDebugInfo()
    elseif msg == "api" then
        if ns.CombatTracker then ns.CombatTracker:DebugAPI() end
    elseif msg == "sessions" then
        if ns.CombatTracker then ns.CombatTracker:DebugSessions() end
    elseif msg == "recap" then
        ns:DebugRecapFields()
    elseif msg == "deathdebug" then
        ns:DebugDeathRecapIDs()
    elseif msg == "overheal" then
        local sessions = C_DamageMeter.GetAvailableCombatSessions()
        local s = sessions and sessions[#sessions]
        if not s then print(L["无历史 session"]); return end
        local ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromID,
            s.sessionID, Enum.DamageMeterType.HealingDone, UnitGUID("player"))
        if not ok or not src or not src.combatSpells then
            print(L["无治疗数据"]); return
        end
        local totalOH = 0
        for _, sp in ipairs(src.combatSpells) do
            local name = C_Spell and C_Spell.GetSpellName(sp.spellID) or sp.spellID
            print(string.format("  [%s] heal=%d  overkill=%d",
                name, sp.totalAmount, sp.overkillAmount or 0))
            totalOH = totalOH + (sp.overkillAmount or 0)
        end
        print(string.format(L["总 overkillAmount 合计: %d"], totalOH))
    end
end

-- ============================================================
-- 调试信息
-- ============================================================
function ns:PrintDebugInfo()
    print("|cff00ccff[Light Damage Debug]|r")
    print("  initialized:", Core._initialized)
    print("  inCombat:", ns.state.inCombat)
    print("  UnitAffectingCombat:", UnitAffectingCombat("player"))
    print("  playerGUID:", ns.state.playerGUID)
    print("  isInInstance:", ns.state.isInInstance)
    print("  inMythicPlus:", ns.state.inMythicPlus)
    print("  Segments:", ns.Segments ~= nil)
    if ns.Segments then
        print("  Segments.overall:", ns.Segments.overall ~= nil)
        print("  Segments.current:", ns.Segments.current ~= nil)
        if ns.Segments.overall then
            local count = 0
            for _ in pairs(ns.Segments.overall.players) do count = count + 1 end
            print("  overall players:", count)
            print("  overall totalDamage:", ns.Segments.overall.totalDamage)
            print("  overall totalHealing:", ns.Segments.overall.totalHealing)
        end
        if ns.Segments.current then
            local count = 0
            for _ in pairs(ns.Segments.current.players) do count = count + 1 end
            print("  current players:", count)
            print("  current totalDamage:", ns.Segments.current.totalDamage)
            print("  current totalHealing:", ns.Segments.current.totalHealing)
        end
        print("  history count:", #ns.Segments.history)
        print("  viewIndex:", tostring(ns.Segments.viewIndex))
    end
    print("  CombatTracker baseline:", ns.CombatTracker and ns.CombatTracker._baselineSessionCount or "N/A")
    print("  CombatTracker lastProcessed:", ns.CombatTracker and ns.CombatTracker._lastProcessedCount or "N/A")
    print("  UI:", ns.UI ~= nil)
    if ns.UI then print("  UI visible:", ns.UI:IsVisible()) end
end

function ns:DebugDeathRecapIDs()
    print(L["=== [Light Damage] 死亡 RecapID 诊断 ==="])
    local sessions = C_DamageMeter.GetAvailableCombatSessions()
    local n = sessions and #sessions or 0
    print(string.format(L["共 %d 个 session"], n))

    for i, s in ipairs(sessions or {}) do
        local ok, deathSess = pcall(C_DamageMeter.GetCombatSessionFromID,
            s.sessionID, Enum.DamageMeterType.Deaths)
        if ok and deathSess and deathSess.combatSources and #deathSess.combatSources > 0 then
            print(string.format("  [Session %d] dur=%.0fs name=%s",
                i, s.durationSeconds or 0, tostring(s.name)))
            for _, src in ipairs(deathSess.combatSources) do
                print(string.format("    name=%-20s deaths=%s recapID=%s",
                    tostring(src.name),
                    tostring(src.totalAmount),
                    tostring(src.deathRecapID)))
            end
        end
    end
    print(L["=== 结束 ==="])
end

function ns:DebugRecapFields()
    if not C_DeathRecap then print(L["[Light Damage] C_DeathRecap 不存在"]); return end
    if not C_DeathRecap.HasRecapEvents or not C_DeathRecap.HasRecapEvents() then
        print(L["[Light Damage] 没有死亡记录，先死一次"]); return
    end
    local events = C_DeathRecap.GetRecapEvents and C_DeathRecap.GetRecapEvents()
    if not events or #events == 0 then print(L["[Light Damage] 返回空"]); return end
    local maxHP = C_DeathRecap.GetRecapMaxHealth and C_DeathRecap.GetRecapMaxHealth()
    print(string.format(L["[Light Damage] maxHealth=%s 共%d条，打印前3条字段:"], tostring(maxHP), #events))
    for i = 1, math.min(3, #events) do
        local ev = events[i]
        print(string.format("  [%d]:", i))
        for k, v in pairs(ev) do
            print(string.format("    .%s = %s (%s)", tostring(k), tostring(v), type(v)))
        end
    end
end

function ns:SwitchMode(mode)
    ns.db.display.mode = mode
    if ns.UI then ns.UI:Refresh() end
end

function ns:GetDisplayData()
    local seg = ns.Segments and ns.Segments:GetViewSegment()
    if not seg then return {} end
    return ns.Analysis and ns.Analysis:GetSorted(seg, ns.db.display.mode) or {}
end

function ns:GetOverallData()
    local seg = ns.Segments and ns.Segments:GetOverallSegment()
    if not seg then return {} end
    return ns.Analysis and ns.Analysis:GetSorted(seg, ns.db.display.mode) or {}
end