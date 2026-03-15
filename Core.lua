--[[
    Light Damage - Core.lua
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
        alpha           = 0.5,
        enableAnim      = true,
        animDuration    = 0.4,
    },
    fade = {
        unfadeOnHover       = true,
        fadeBars            = false,
        barsWhen            = "ooc",        -- "always" / "ooc"
        barsNeverInInstance = false,
        barsAlpha           = 0.3,
        fadeBody            = false,
        bodyWhen            = "ooc",        -- "always" / "ooc"
        bodyNeverInInstance = false,
        bodyAlpha           = 0.15,
        delay               = 1.5,
        enableAnim          = true,
        animDuration        = 0.5,
    },
    window = {
        width = 400, height = 280,
        point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -20, y = 180,
        alpha = 0.92, scale = 1.0, configScale = 1.0,locked = false, visible = true,
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
        showRealm     = false,
        classColors   = true,
        -- ★ 新增和完善的外观默认项
        barHeight     = 19,
        barThickness  = 19,
        barVOffset    = 0,
        barGap        = 1,
        barAlpha      = 0.85, -- 透明度默认调高，解决太淡的问题
        barTexture    = "Interface\\Buttons\\WHITE8X8",
        font          = STANDARD_TEXT_FONT,
        fontSizeBase  = 13,
        fontOutline   = "OUTLINE",
        fontShadow    = false,
        textColorMode = "white",       -- "class" / "white" / "custom"
        textColor     = {1.0, 1.0, 1.0},
    },
    split = {
        enabled           = true,         
        splitDir          = "TB",         
        primaryMode       = "damage",
        secondaryMode     = "healing",
        primaryPos        = 1,            
        
        -- ★ 新增：双数据模式的场景开关
        splitShowMPlus    = true,
        splitShowRaid     = true,
        splitShowDungeon  = true,
        splitShowOutdoor  = false,
        
        showOverall       = true,         
        overallDir        = "LR",         
        currentPos        = 1,            
        
        -- ★ 新增：总计窗口的场景开关
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
    wasInInstance    = false,  -- 上一帧是否在副本内（用于检测离开）
    instanceType     = nil,
    inMythicPlus     = false,
    mythicPlusLevel  = 0,
    playerGUID       = nil,
    playerName       = nil,
    playerClass      = nil,
}


-- ============================================================
-- 初始化
-- ============================================================
-- ============================================================
-- 初始化
-- ============================================================
function Core:OnInitialize()
    if not self._initialized then
        self._initialized = true

        -- 1. 初始化全局配置库
        if not LDCombatStatsGlobal then LDCombatStatsGlobal = { profiles = {} } end
        if not LDCombatStatsGlobal.profiles["默认"] then
            -- 继承旧配置：如果当前角色有旧配置，则将当前配置升级为全账号“默认”配置
            if LDCombatStatsDB and LDCombatStatsDB.window then
                LDCombatStatsGlobal.profiles["默认"] = {
                    window = CopyTable(LDCombatStatsDB.window),
                    display = CopyTable(LDCombatStatsDB.display),
                    split = CopyTable(LDCombatStatsDB.split),
                    mythicPlus = CopyTable(LDCombatStatsDB.mythicPlus),
                    tracking = CopyTable(LDCombatStatsDB.tracking),
                    smartRefresh = CopyTable(LDCombatStatsDB.smartRefresh),
                    useBlizzMeter = LDCombatStatsDB.useBlizzMeter
                }
            else
                LDCombatStatsGlobal.profiles["默认"] = CopyTable(ns.defaults)
            end
        end

        -- ★ 新增：版本配置自动平滑迁移 (旧版 -> 四宫格新版)
        for pName, profile in pairs(LDCombatStatsGlobal.profiles) do
            local sp = profile.split
            local mp = profile.mythicPlus
            if sp and mp then
                -- 检查是否存在旧的 overallColumnMode 字段，如果存在说明是旧配置
                if mp.overallColumnMode ~= nil then
                    -- 1. 迁移右侧全程栏的开启状态
                    sp.showOverall = (mp.overallColumnMode ~= "off")
                    sp.overallShowMode = mp.overallColumnMode
                    mp.overallColumnMode = nil -- 清除旧字段
                    
                    -- 2. 映射到经典视觉外观：左右分割(当前在左)，上下分割(主数据在上)
                    sp.splitDir = "TB"
                    sp.overallDir = "LR"
                    sp.primaryPos = 1
                    sp.currentPos = 1

                    -- 3. 转换自适应比例
                    if sp.priRatio then
                        sp.tbRatio = sp.priRatio
                        sp.priRatio = nil
                    end
                    if sp.ovrRatio then
                        -- 原本的 ovrRatio 是指“右侧(全程)”的宽度占比
                        -- 现在的 lrRatio 是指“左侧”的宽度占比，所以用 1 减去旧值即可完美还原
                        sp.lrRatio = 1 - sp.ovrRatio 
                        sp.ovrRatio = nil
                    end
                end
            end
        end

        -- 2. 初始化角色数据
        if not LDCombatStatsDB then LDCombatStatsDB = {} end
        if not LDCombatStatsDB.activeProfile or not LDCombatStatsGlobal.profiles[LDCombatStatsDB.activeProfile] then
            LDCombatStatsDB.activeProfile = "默认"
        end

        -- 3. 清理旧的角色级配置数据(节约空间，只保留战斗历史等)
        local CONFIG_KEYS = { window=true, display=true, split=true, mythicPlus=true, tracking=true, smartRefresh=true, useBlizzMeter=true, detailWindow=true, detailDisplay=true, collapse=true, fade=true }
        for k in pairs(CONFIG_KEYS) do
            if LDCombatStatsDB[k] then LDCombatStatsDB[k] = nil end
        end

        -- 4. 建立智能代理数据指针 ns.db 
        -- 外观和设置写入全局共享，历史战斗数据留在角色独享
        ns.db = setmetatable({}, {
            __index = function(t, k)
                if CONFIG_KEYS[k] then
                    return LDCombatStatsGlobal.profiles[LDCombatStatsDB.activeProfile][k]
                else
                    return LDCombatStatsDB[k]
                end
            end,
            __newindex = function(t, k, v)
                if CONFIG_KEYS[k] then
                    LDCombatStatsGlobal.profiles[LDCombatStatsDB.activeProfile][k] = v
                else
                    LDCombatStatsDB[k] = v
                end
            end
        })

        ns:MergeDefaults(LDCombatStatsGlobal.profiles[LDCombatStatsDB.activeProfile], ns.defaults)


        ns.state.playerGUID = UnitGUID("player")
        ns.state.playerName = UnitName("player")
        local _, classEng   = UnitClass("player")
        ns.state.playerClass = classEng

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
                    -- ★ 二次校验：确认这些 session 不是暴雪残留的空壳
                    --   如果最新的 session 时长为0且无名称，说明是 stale 数据，不设 baseline
                    local latestSess = ss[cnt]
                    local isStale = (latestSess.durationSeconds or 0) == 0
                                and (latestSess.name == nil or latestSess.name == "")
                    if isStale then
                        -- 残留空壳，跳过设置，等真正的战斗产生后再对齐
                    else
                        local offset = ns.state.inCombat and 1 or 0
                        ns.CombatTracker._baselineSessionCount = math.max(0, cnt - offset)
                        ns.CombatTracker._lastProcessedCount   = math.max(0, cnt - offset)
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
        
        -- ★ 自动关闭暴雪原生统计
        C_Timer.After(2, function()
            local possibleCVars = {
                "damageMeterResetOnNewInstance",
                "damageMeterEnabled" 
            }
            local setter = (C_CVar and C_CVar.SetCVar) or SetCVar
            for _, cvar in ipairs(possibleCVars) do
                pcall(setter, cvar, "0")
            end
        end)

        -- ★ 把所有的 RegisterEvent 放在这里
        local events = {
            "ZONE_CHANGED_NEW_AREA",
            "ENCOUNTER_START",
            "ENCOUNTER_END",
            "GROUP_ROSTER_UPDATE",
            "CHALLENGE_MODE_START",
            "CHALLENGE_MODE_COMPLETED",
            "CHALLENGE_MODE_RESET",
            "PLAYER_DEAD",
            "PLAYER_LOGOUT",
        }
        

        -- 1. 注册主框架事件
        for _, ev in ipairs(events) do
            self:RegisterEvent(ev)
        end

        -- 2. 注册战斗追踪器事件
        if ns.CombatTracker then
            ns.CombatTracker:RegisterEvents()
        end

        -- 3. 注册战斗日志事件
        -- local cleuFrame = CreateFrame("Frame")
        -- cleuFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        -- cleuFrame:SetScript("OnEvent", function()
        --     if not ns.DeathTracker then return end
        --     local ts, sub, _, sg, sn, sf, dg, dn, df, p1, p2, p3, p4 = CombatLogGetCurrentEventInfo()

        --     if sub == "SWING_DAMAGE" then
        --         ns.DeathTracker:RecordIncomingDamage(dg, dn, df, p1, 0, L["近战"], p3 or 1, sg, sn)
        --     elseif sub == "SPELL_DAMAGE" or sub == "SPELL_PERIODIC_DAMAGE" or sub == "RANGE_DAMAGE" then
        --         ns.DeathTracker:RecordIncomingDamage(dg, dn, df, p4, p1, p2, p3, sg, sn)
        --     elseif sub == "SPELL_HEAL" or sub == "SPELL_PERIODIC_HEAL" then
        --         ns.DeathTracker:RecordIncomingHeal(dg, dn, df, p4, p1, p2, sg, sn)
        --     elseif sub == "UNIT_DIED" then
        --         ns.DeathTracker:OnUnitDied(dg, dn, df, ts)
        --     end
        -- end)



    end -- <--- 这是 if not self._initialized then 的结束

    -- 无论是不是第一次进世界，都要执行的常规操作
    SLASH_LDCS1 = "/ldcs"
    SLASH_LDCS2 = "/ldstats"
    SlashCmdList["LDCS"] = function(msg) ns:HandleSlashCommand(msg) end

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
        -- ★ 修复「进副本右侧列不显示」：ZONE_CHANGED_NEW_AREA 在加载屏幕期间
        --   触发时 frame:IsShown()=false，Layout() 直接 return。
        --   PLAYER_ENTERING_WORLD 在加载结束后触发，此处补一次强制刷新。
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

        -- 出副本 → 开放世界
        if wasInInstance and not ns.state.isInInstance then
            if ns.MythicPlus and ns.MythicPlus:IsActive() then
                ns.MythicPlus:OnLeaveInstance()
            end
            if ns.UI then
                C_Timer.After(0.1, function() ns.UI:Layout() end)
            end
        end

        -- 开放世界 → 进副本
        -- ★ Layout() 交给 PLAYER_ENTERING_WORLD 的 0.3s timer 负责，
        --   这里不调用（加载屏幕期间 frame 不可见）
        if not wasInInstance and ns.state.isInInstance then
            if not ns.state.inMythicPlus then
                if ns.CombatTracker then
                    ns.CombatTracker:ResetBaselineToCurrentCount()
                end
                if ns.Segments then
                    local name = GetInstanceInfo() or L["副本"]
                    -- 改用 string.format 和 L 翻译表
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
    LoggingCombat(true)
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

    -- ★ 修复暴雪API的坑：地下堡(scenario)的 inInstance 会返回 false
    -- 我们手动将这几种明确的战斗副本类型强制判定为“在副本内”
    if instanceType == "scenario" or instanceType == "party" or instanceType == "raid" or instanceType == "arena" or instanceType == "pvp" then
        inInstance = true
    end

    -- ★ 强制排除：把房屋小区直接视为户外非副本
    if instanceType == "neighborhood" or instanceType == "interior" then
        inInstance = false
    end

    -- 保存上一帧的状态（供事件处理使用）
    ns.state.wasInInstance = ns.state.isInInstance
    ns.state.isInInstance = inInstance
    ns.state.instanceType = instanceType

    local wasInMPlus      = ns.state.inMythicPlus
    ns.state.inMythicPlus = false

    -- 识别大秘境
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

    -- ★ 核心：场景分类器 (mplus / raid / dungeon / outdoor)
    local cat = "outdoor"
    if inInstance then
        if instanceType == "raid" then
            cat = "raid"
        elseif instanceType == "party" or instanceType == "scenario" or instanceType == "arena" or instanceType == "pvp" then
            cat = "dungeon" -- 包含地下堡、竞技场、战场、普通/英雄/M0地下城等
        end
    end
    if ns.state.inMythicPlus then
        cat = "mplus"
    end
    
    local oldCat = ns.state.instanceCategory
    ns.state.instanceCategory = cat

    -- ★ 核心修复：跨越场景时，自动恢复或降级双栏模式
    if oldCat ~= cat and ns.db and ns.db.split then
        local isActive = false
        if cat == "mplus" and ns.db.split.splitShowMPlus then isActive = true end
        if cat == "raid" and ns.db.split.splitShowRaid then isActive = true end
        if cat == "dungeon" and ns.db.split.splitShowDungeon then isActive = true end
        if cat == "outdoor" and ns.db.split.splitShowOutdoor then isActive = true end

        if isActive and ns.db.split.enabled then
            -- 如果新场景允许双栏，并且总开关开着，进本瞬间自动帮你切回双栏
            ns.db.display.mode = "split"
        elseif not isActive and ns.db.display.mode == "split" then
            -- 如果新场景不允许双栏（比如出本回城），自动降级为单栏伤害
            ns.db.display.mode = ns.db.split.primaryMode or "damage"
        end
    end

    if ns.state.inMythicPlus and not wasInMPlus then
        if ns.MythicPlus then ns.MythicPlus:OnEnterDungeon() end
    end
end

-- ============================================================
-- 工具函数
-- ============================================================
function ns:MergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = CopyTable(v)
            else
                ns:MergeDefaults(target[k], v)
            end
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

-- ============================================================
-- 斜杠命令
-- ============================================================
function ns:HandleSlashCommand(msg)
    msg = (msg or ""):lower():trim()

    if msg == "" then
        -- 如果只输入了 /ldcs，直接打开设置面板
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
        -- 避免拼接陷阱，这里直接用条件判断输出完整的翻译句子
        if ns.db.window.locked then
            print(L["|cff00ccff[Light Damage]|r 已锁定"])
        else
            print("|cff00ccff[Light Damage]|r " .. L["已解锁"]) 
        end


    -- ============================================================
    -- 隐藏开发者命令 (不在 help 显示)
    -- ============================================================
    
    -- 强行切换语言测试: /ldcs lang enUS
    elseif msg:match("^lang") then
        -- 提取输入的语言代码，注意因为前面用了 :lower()，所以要做一下匹配映射
        local langInput = msg:match("lang%s+(%w+)"):lower()
        local targetLang = "zhCN"
        
        if langInput == "enus" then targetLang = "enUS"
        elseif langInput == "zhtw" then targetLang = "zhTW"
        end
        
        if ns.SwitchLanguage then
            ns:SwitchLanguage(targetLang)
            -- 如果配置面板开着，强行刷新它
            if ns.Config and ns.Config.RefreshUI then 
                ns.Config:RefreshUI() 
            end
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

function ns:SwitchMode(mode)
    ns.db.display.mode = mode
    if ns.UI then ns.UI:Refresh() end
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


-- ============================================================
-- 获取当前显示数据
-- ============================================================
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

function ns:SaveSessionHistory()
    if not ns.Segments then return end
    local maxSeg = ns.db and ns.db.tracking and ns.db.tracking.maxSegments or 30  -- ★ 补上定义

    -- ★ 修复核心：判断是否处于预览模式。如果是，取出被藏起来的真实数据
    local historyToSave = ns.Segments.history
    local overallToSave = ns.Segments.overall
    
    if ns.Config and ns.Config._previewActive and ns.Config._pvSave then
        historyToSave = ns.Config._pvSave.history or {}
        overallToSave = ns.Config._pvSave.overall
    end

    local toSave = {}
    for i, seg in ipairs(historyToSave) do
        if i > maxSeg then break end
        local compact = {
            type             = seg.type,
            name             = seg.name,
            startTime        = seg.startTime,
            endTime          = seg.endTime,
            duration         = seg.duration,
            isActive         = false,
            totalDamage      = seg.totalDamage,
            totalHealing     = seg.totalHealing,
            totalDamageTaken = seg.totalDamageTaken,
            encounterName    = seg.encounterName,
            success          = seg.success,
            mythicLevel      = seg.mythicLevel,
            mapName          = seg.mapName,
            _isMerged        = seg._isMerged,
            _isBoss          = seg._isBoss,
            _instanceTag     = seg._instanceTag,
            _preKeystone     = seg._preKeystone,
            _mythicLevel     = seg._mythicLevel,
            _mapName         = seg._mapName,
            _builtByMythicPlus = seg._builtByMythicPlus,
            _sessionID       = seg._sessionID,   -- ★ 记录官方会话ID用于重载同步
            _sessionIdx      = seg._sessionIdx,  -- ★ 记录官方会话索引
            players          = {},
            deathLog         = {},
        }
        for guid, pd in pairs(seg.players) do
            compact.players[guid] = {
                guid            = pd.guid,
                name            = pd.name,
                class           = pd.class,
                specID          = pd.specID,
                ilvl            = pd.ilvl   or 0,
                score           = pd.score  or 0,
                damage          = pd.damage,
                healing         = pd.healing,
                damageTaken     = pd.damageTaken,
                deaths          = pd.deaths,
                interrupts      = pd.interrupts,
                dispels         = pd.dispels,
                spells          = pd.spells or {},
                damageTakenSpells = pd.damageTakenSpells or {},
                interruptSpells = pd.interruptSpells or {},
                dispelSpells    = pd.dispelSpells or {},
                pets            = pd.pets or {},
                activeTime      = pd.activeTime,
                lastActionTime  = 0,
            }
        end

        -- ★ 新增：将该段落的死亡日志复制到存档对象中
        if seg.deathLog then
            for _, dr in ipairs(seg.deathLog) do
                table.insert(compact.deathLog, CopyTable(dr))
            end
        end

        table.insert(toSave, compact)
    end
    ns.db.savedHistory = toSave

    -- ★ 新增：同时保存 overall，reload 后右栏数据得以恢复
    local ovr = overallToSave
    if ovr and (ovr.totalDamage > 0 or ovr.totalHealing > 0) then
        local compactOvr = {
            name             = ovr.name,
            duration         = ovr.duration,
            totalDamage      = ovr.totalDamage,
            totalHealing     = ovr.totalHealing,
            totalDamageTaken = ovr.totalDamageTaken,
            players          = {},
        }
        for guid, pd in pairs(ovr.players) do
            compactOvr.players[guid] = {
                guid            = pd.guid,
                name            = pd.name,
                class           = pd.class,
                specID          = pd.specID or (ns.PlayerInfoCache[guid] and ns.PlayerInfoCache[guid].specID), -- ★
                ilvl            = pd.ilvl or (ns.PlayerInfoCache[guid] and ns.PlayerInfoCache[guid].ilvl) or 0, -- ★
                score           = pd.score or (ns.PlayerInfoCache[guid] and ns.PlayerInfoCache[guid].score) or 0, -- ★
                damage          = pd.damage,
                healing         = pd.healing,
                damageTaken     = pd.damageTaken,
                deaths          = pd.deaths,
                interrupts      = pd.interrupts,
                dispels         = pd.dispels,
                spells          = pd.spells          or {},
                damageTakenSpells = pd.damageTakenSpells or {},
                interruptSpells = pd.interruptSpells or {},
                dispelSpells    = pd.dispelSpells    or {},
                pets            = pd.pets            or {},
                activeTime      = pd.activeTime,
                lastActionTime  = 0,
            }
        end

        -- ★ 新增：保存 Overall 的死亡日志
        compactOvr.deathLog = {}
        if ovr.deathLog then
            for _, dr in ipairs(ovr.deathLog) do
                table.insert(compactOvr.deathLog, CopyTable(dr))
            end
        end

        ns.db.savedOverall = compactOvr
        else
            ns.db.savedOverall = nil
        end
        
        -- ★ 保存底层基准线进度
        if ns.CombatTracker then
            ns.db.savedBaseline = ns.CombatTracker._baselineSessionCount or 0
            ns.db.savedLastProcessed = ns.CombatTracker._lastProcessedCount or 0
        end
    end

function ns:LoadSessionHistory()
    if not ns.Segments then return end
    if not ns.db.savedHistory or #ns.db.savedHistory == 0 then return end
    ns.Segments.history = {}
    for _, seg in ipairs(ns.db.savedHistory) do
        table.insert(ns.Segments.history, seg)
    end
    if #ns.Segments.history > 0 then
        ns.Segments.viewIndex = 1
    end

    -- ★ 新增：恢复 overall，保证 reload 后右栏立即有数据
    local saved = ns.db.savedOverall
    if saved and (saved.totalDamage or 0) > 0 then
        ns.Segments.overall = ns.Segments:NewSegment("overall", saved.name or L["总计"])
        ns.Segments.overall.isActive         = false
        ns.Segments.overall.duration         = saved.duration         or 0
        ns.Segments.overall.totalDamage      = saved.totalDamage      or 0
        ns.Segments.overall.totalHealing     = saved.totalHealing     or 0
        ns.Segments.overall.totalDamageTaken = saved.totalDamageTaken or 0
        for guid, pd in pairs(saved.players or {}) do
            -- ★ 确保旧数据也有默认值，防止报错
            pd.specID = pd.specID or nil
            pd.ilvl   = pd.ilvl or 0
            pd.score  = pd.score or 0
            ns.Segments.overall.players[guid] = pd
        end

        -- ★ 新增：将存档的死亡记录恢复到 Overall 中
        if saved.deathLog then
            for _, dr in ipairs(saved.deathLog) do
                table.insert(ns.Segments.overall.deathLog, dr)
            end
        end

        -- 保存快照，供 RebuildOverall 在新战斗结束后叠加数据
        ns.Segments._preReloadOverallData = {
            totalDamage      = saved.totalDamage      or 0,
            totalHealing     = saved.totalHealing     or 0,
            totalDamageTaken = saved.totalDamageTaken or 0,
            duration         = saved.duration         or 0,
            players          = CopyTable(saved.players or {}),
        }
    end

    -- ★ 恢复底层基准线进度
    if ns.CombatTracker then
        ns.CombatTracker._baselineSessionCount = ns.db.savedBaseline or 0
        ns.CombatTracker._lastProcessedCount = ns.db.savedLastProcessed or 0
    end
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

function ns:SwitchProfile(name)
    if not LDCombatStatsGlobal.profiles[name] then return end
    
    -- 1. 记录切换前的语言设置
    local oldLang = ns.db.display and ns.db.display.language or "auto"

    LDCombatStatsDB.activeProfile = name
    ns:MergeDefaults(LDCombatStatsGlobal.profiles[name], ns.defaults)

    -- 2. 记录切换后的语言设置
    local newLang = ns.db.display and ns.db.display.language or "auto"

    if ns.UI and ns.UI.frame then
        -- 补上切换配置时的即时位置与大小刷新
        local w = ns.db.window
        ns.UI.frame:SetSize(w.width, w.height)
        ns.UI.frame:ClearAllPoints()
        ns.UI.frame:SetPoint(w.point, UIParent, w.relPoint, w.x, w.y)
        
        ns.UI.frame:SetScale(w.scale or 1.0)
        ns.UI.frame:SetAlpha(w.alpha or 0.92)
        ns.UI:ApplyTheme()
        ns.UI:Layout()
    end
    if ns.Config then
        if ns.Config.panel then 
            ns.Config:RefreshUI() 
            -- ★ 切换配置时同步刷新设置界面自身的缩放
            local cScale = ns.db.window and ns.db.window.configScale or 1.0
            ns.Config.panel:SetScale(cScale)
            if ns.Config._pvSwitcher then ns.Config._pvSwitcher:SetScale(cScale) end
        end
        if ns.Config.RefreshTitle then ns.Config:RefreshTitle() end
    end
    
    local displayName = (name == "默认") and L["默认"] or name
    print(L["|cff00ccff[Light Damage]|r 已应用 "] .. displayName .. L["的配置"])

    -- 3. 如果发现语言不一致，直接触发重载
    if oldLang ~= newLang then
        ReloadUI()
    end
end

function ns:CreateProfile(name)
    if not name or name == "" or LDCombatStatsGlobal.profiles[name] then return false end
    -- 基于当前正在使用的配置创建
    LDCombatStatsGlobal.profiles[name] = CopyTable(LDCombatStatsGlobal.profiles[LDCombatStatsDB.activeProfile])
    ns:SwitchProfile(name)
    return true
end

function ns:DeleteProfile(name)
    if name == "默认" or not LDCombatStatsGlobal.profiles[name] then return end
    LDCombatStatsGlobal.profiles[name] = nil
    if LDCombatStatsDB.activeProfile == name then
        ns:SwitchProfile("默认")
    end
end

function ns:RenameProfile(oldName, newName)
    if oldName == "默认" or not LDCombatStatsGlobal.profiles[oldName] then return false end
    if not newName or newName == "" or LDCombatStatsGlobal.profiles[newName] then return false end

    -- 复制数据到新名字
    LDCombatStatsGlobal.profiles[newName] = CopyTable(LDCombatStatsGlobal.profiles[oldName])
    LDCombatStatsGlobal.profiles[oldName] = nil

    -- 如果正在使用这个被改名的配置，更新指针并刷新界面
    if LDCombatStatsDB.activeProfile == oldName then
        LDCombatStatsDB.activeProfile = newName
        if ns.Config and ns.Config.RefreshTitle then ns.Config:RefreshTitle() end
    end
    print(L["|cff00ccff[Light Damage]|r 配置已重命名为 "] .. newName)
    return true
end

-- ============================================================
-- ★ 新增：队伍玩家信息扫描器 (装等、大秘境评分、专精)
-- ============================================================
ns.PlayerInfoCache = {}

local inspectScanner = CreateFrame("Frame")
inspectScanner:RegisterEvent("GROUP_ROSTER_UPDATE")
inspectScanner:RegisterEvent("PLAYER_ENTERING_WORLD")
inspectScanner:RegisterEvent("INSPECT_READY")
local currentInspectUnit = nil

inspectScanner:SetScript("OnUpdate", function(self, elapsed)
    self.timer = (self.timer or 0) + elapsed
    -- 每 2 秒扫描一次，避免卡顿
    if self.timer > 2 then
        self.timer = 0
        if InCombatLockdown() then return end

        local prefix = IsInRaid() and "raid" or "party"
        local num = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
        local units = {"player"}
        for i = 1, num do table.insert(units, prefix..i) end

        for _, unit in ipairs(units) do
            if UnitExists(unit) and UnitIsConnected(unit) and UnitIsPlayer(unit) then
                local guid = UnitGUID(unit)
                if guid then
                    ns.PlayerInfoCache[guid] = ns.PlayerInfoCache[guid] or { score = 0, ilvl = 0, specID = nil }
                    local c = ns.PlayerInfoCache[guid]

                    -- 1. 获取大秘境评分 (不需要 Inspect)
                    if c.score == 0 and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
                        local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
                        if summary and summary.currentSeasonScore then
                            c.score = summary.currentSeasonScore
                        end
                    end

                    -- 2. 获取专精和装等
                    if unit == "player" then
                        local specIdx = GetSpecialization()
                        if specIdx then c.specID = GetSpecializationInfo(specIdx) end
                        local _, equipped = GetAverageItemLevel()
                        c.ilvl = math.floor(equipped or 0)
                    else
                        -- 队友需要发起 Inspect 请求
                        if not c.specID and CanInspect(unit) and (GetTime() - (self.lastInspect or 0) > 2) then
                            self.lastInspect = GetTime()
                            currentInspectUnit = unit
                            NotifyInspect(unit)
                            break -- 每次只 Inspect 一个
                        end
                    end
                end
            end
        end
    end
end)

inspectScanner:SetScript("OnEvent", function(self, event, guid)
    if event == "INSPECT_READY" and currentInspectUnit and UnitGUID(currentInspectUnit) == guid then
        local c = ns.PlayerInfoCache[guid]
        if c then
            c.specID = GetInspectSpecialization(currentInspectUnit)
            local ilvl = C_PaperDollInfo.GetInspectItemLevel(currentInspectUnit)
            if ilvl then c.ilvl = math.floor(ilvl) end
        end
        ClearInspectPlayer()
        currentInspectUnit = nil
    end
end)