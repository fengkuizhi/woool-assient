#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

SetWorkingDir A_ScriptDir
SetTitleMatchMode 2
CoordMode "Mouse", "Screen"
CoordMode "Pixel", "Screen"

global ScriptEnabled := true
global Config := LoadConfig()
global LastTeleportHour := ""
global LastExpCardHour := ""
global LastWindowMissingHour := ""
global OverlayGui := ""
global LogFile := A_ScriptDir "\logs\automation.log"

EnsureRuntimePaths()
ValidateTemplateAtStartup()
SetTimer CheckSchedule, 1000
Log("Script started.")
TrayTip "传奇自动操作", "脚本已启动。F8 开关，F9 传送测试，F7 经验卡测试，F10 显示识别区域，Esc 退出。"

F8::ToggleScript()
F9::ManualRun()
F7::ManualExpCardRun()
F10::ShowSearchOverlay()
Esc::ExitScript()

CheckSchedule() {
    global ScriptEnabled

    if !ScriptEnabled {
        return
    }

    RunScheduledTeleport()
    RunScheduledExpCard()
}

ManualRun() {
    RunTeleportFlow("manual")
}

ManualExpCardRun() {
    RunExpCardFlow("manual")
}

RunScheduledTeleport() {
    global Config, LastTeleportHour

    if !IsWithinTriggerWindow(Config.ActiveMinute, Config.PreTriggerSeconds, Config.PostTriggerSeconds) {
        return
    }

    currentHourKey := FormatTime(A_Now, "yyyyMMddHH")
    if (LastTeleportHour = currentHourKey) {
        return
    }

    if RunTeleportFlow("timer") {
        LastTeleportHour := currentHourKey
    }
}

RunScheduledExpCard() {
    global Config, LastExpCardHour

    if !Config.ExpCardEnabled {
        return
    }

    if !IsWithinTriggerWindow(Config.ExpCardActiveMinute, Config.ExpCardPreTriggerSeconds, Config.ExpCardPostTriggerSeconds) {
        return
    }

    currentHourKey := FormatTime(A_Now, "yyyyMMddHH")
    if (LastExpCardHour = currentHourKey) {
        return
    }

    if RunExpCardFlow("timer") {
        LastExpCardHour := currentHourKey
    }
}

RunTeleportFlow(triggerSource := "manual") {
    global Config, LastWindowMissingHour

    hwnd := FindGameWindow()
    if !hwnd {
        hourKey := FormatTime(A_Now, "yyyyMMddHH")
        if (LastWindowMissingHour != hourKey || triggerSource = "manual") {
            Log("Game window not found for title match: " Config.GameWindowTitle)
            if (triggerSource = "manual") {
                MsgBox "没有找到游戏窗口。请先确认 config.ini 里的 GameWindowTitle。", "传奇自动传送", "Icon!"
            }
            LastWindowMissingHour := hourKey
        }
        return false
    }

    if !EnsureWindowActive(hwnd) {
        Log("Failed to activate game window.")
        if (triggerSource = "manual") {
            MsgBox "无法激活游戏窗口。", "传奇自动传送", "Icon!"
        }
        return false
    }

    region := GetSearchRect(hwnd)
    if !region {
        Log("Failed to compute search region.")
        return false
    }

    attempt := 0
    while (attempt < Config.RetryCount) {
        attempt += 1
        found := FindTeleportButton(region)
        if found {
            clickX := found.x + Config.ClickOffsetX
            clickY := found.y + Config.ClickOffsetY
            Log(Format("Matched template at ({1}, {2}), clicking ({3}, {4}), attempt {5}/{6}.",
                found.x, found.y, clickX, clickY, attempt, Config.RetryCount))
            ClickTeleport(clickX, clickY)
            Sleep Config.PostClickVerifyDelayMs

            if !FindTeleportButton(region) {
                Log("Teleport button disappeared after click.")
                return true
            }
        } else {
            Log(Format("Template not found in region x={1}, y={2}, w={3}, h={4}, attempt {5}/{6}.",
                region.x, region.y, region.w, region.h, attempt, Config.RetryCount))
        }

        Sleep Config.RetryIntervalMs
    }

    Log("Run finished without success.")
    if (triggerSource = "manual") {
        MsgBox "没有找到“立即传送”按钮，或点击后弹窗未消失。请检查模板图片和识别区域。", "传奇自动传送", "Icon!"
    }
    return false
}

RunExpCardFlow(triggerSource := "manual") {
    global Config, LastWindowMissingHour

    if !Config.ExpCardEnabled {
        Log("Exp card flow skipped because ExpCard.Enabled is off.")
        if (triggerSource = "manual") {
            MsgBox "经验卡功能未启用。请先在 config.ini 里把 [ExpCard] 的 Enabled 改成 1。", "传奇自动操作", "Icon!"
        }
        return false
    }

    if (Config.ExpCardX < 0 || Config.ExpCardY < 0) {
        Log("Exp card flow skipped because ExpCardX/ExpCardY is not configured.")
        if (triggerSource = "manual") {
            MsgBox "经验卡坐标未配置。请先在 config.ini 里填写 [ExpCard] 的 RelativeX/RelativeY。", "传奇自动操作", "Icon!"
        }
        return false
    }

    hwnd := FindGameWindow()
    if !hwnd {
        hourKey := FormatTime(A_Now, "yyyyMMddHH")
        if (LastWindowMissingHour != hourKey || triggerSource = "manual") {
            Log("Game window not found for exp card flow: " Config.GameWindowTitle)
            if (triggerSource = "manual") {
                MsgBox "没有找到游戏窗口。请先确认 config.ini 里的 GameWindowTitle。", "传奇自动操作", "Icon!"
            }
            LastWindowMissingHour := hourKey
        }
        return false
    }

    if !EnsureWindowActive(hwnd) {
        Log("Failed to activate game window for exp card flow.")
        if (triggerSource = "manual") {
            MsgBox "无法激活游戏窗口。", "传奇自动操作", "Icon!"
        }
        return false
    }

    clickPoint := GetWindowRelativePoint(hwnd, Config.ExpCardX, Config.ExpCardY)
    if !clickPoint {
        Log("Failed to compute exp card click point.")
        if (triggerSource = "manual") {
            MsgBox "无法计算经验卡点击坐标。", "传奇自动操作", "Icon!"
        }
        return false
    }

    DoubleClickPoint(clickPoint.x, clickPoint.y, Config.ExpCardDoubleClickIntervalMs)
    Log(Format("Double-clicked exp card at screen ({1}, {2}) from relative ({3}, {4}).",
        clickPoint.x, clickPoint.y, Config.ExpCardX, Config.ExpCardY))
    return true
}

FindGameWindow() {
    global Config

    DetectHiddenWindows false
    return WinExist(Config.GameWindowTitle)
}

EnsureWindowActive(hwnd) {
    global Config

    target := "ahk_id " hwnd
    if WinActive(target) {
        return true
    }

    try {
        WinActivate target
        return WinWaitActive(target, , Config.ActivateTimeoutMs / 1000)
    } catch {
        return false
    }
}

GetSearchRect(hwnd) {
    global Config

    try {
        WinGetPos &windowX, &windowY, &windowW, &windowH, "ahk_id " hwnd
    } catch {
        return false
    }

    if (windowW <= 0 || windowH <= 0) {
        return false
    }

    x := windowX + Config.RegionX
    y := windowY + Config.RegionY
    w := Min(Config.RegionW, windowW - Config.RegionX)
    h := Min(Config.RegionH, windowH - Config.RegionY)

    if (w <= 0 || h <= 0) {
        return false
    }

    return {
        x: x,
        y: y,
        w: w,
        h: h,
        x2: x + w - 1,
        y2: y + h - 1
    }
}

GetWindowRelativePoint(hwnd, offsetX, offsetY) {
    try {
        WinGetPos &windowX, &windowY, &windowW, &windowH, "ahk_id " hwnd
    } catch {
        return false
    }

    if (windowW <= 0 || windowH <= 0) {
        return false
    }

    if (offsetX >= windowW || offsetY >= windowH) {
        return false
    }

    return {
        x: windowX + offsetX,
        y: windowY + offsetY
    }
}

FindTeleportButton(region) {
    global Config

    imageSpec := "*" Config.Variation " " Config.TemplatePath
    try {
        matched := ImageSearch(&foundX, &foundY, region.x, region.y, region.x2, region.y2, imageSpec)
        if matched {
            return {x: foundX, y: foundY}
        }
    } catch as err {
        Log("ImageSearch error: " err.Message)
    }
    return false
}

ClickTeleport(x, y) {
    MouseMove x, y, 0
    Click
}

DoubleClickPoint(x, y, intervalMs := 120) {
    MouseMove x, y, 0
    Click
    Sleep intervalMs
    Click
}

ShowSearchOverlay() {
    global OverlayGui

    hwnd := FindGameWindow()
    if !hwnd {
        MsgBox "没有找到游戏窗口。", "传奇自动传送", "Icon!"
        return
    }

    if !EnsureWindowActive(hwnd) {
        MsgBox "无法激活游戏窗口。", "传奇自动传送", "Icon!"
        return
    }

    region := GetSearchRect(hwnd)
    if !region {
        MsgBox "无法计算识别区域。", "传奇自动传送", "Icon!"
        return
    }

    if IsObject(OverlayGui) {
        try OverlayGui.Destroy()
    }

    OverlayGui := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x20")
    OverlayGui.BackColor := "EEAA22"
    OverlayGui.Show(Format("x{1} y{2} w{3} h{4} NA", region.x, region.y, region.w, region.h))
    WinSetTransparent 90, OverlayGui.Hwnd
    SetTimer RemoveOverlay, -2000

    ToolTip Format("识别区域 x={1} y={2} w={3} h={4}", region.x, region.y, region.w, region.h), region.x, region.y - 24
    SetTimer ClearTooltip, -2000
}

RemoveOverlay() {
    global OverlayGui

    if IsObject(OverlayGui) {
        try OverlayGui.Destroy()
    }
    OverlayGui := ""
}

ClearTooltip() {
    ToolTip
}

ToggleScript() {
    global ScriptEnabled

    ScriptEnabled := !ScriptEnabled
    state := ScriptEnabled ? "已启用" : "已暂停"
    Log("Script toggled: " state)
    TrayTip "传奇自动传送", "脚本" state
}

ExitScript() {
    Log("Script exited.")
    ExitApp
}

IsWithinTriggerWindow(activeMinute, preTriggerSeconds, postTriggerSeconds) {
    minute := A_Min + 0
    second := A_Sec + 0
    nowSeconds := minute * 60 + second
    targetSeconds := activeMinute * 60

    return (
        nowSeconds >= targetSeconds - preTriggerSeconds
        && nowSeconds <= targetSeconds + postTriggerSeconds
    )
}

LoadConfig() {
    configPath := A_ScriptDir "\config.ini"
    if !FileExist(configPath) {
        MsgBox "缺少 config.ini。", "传奇自动传送", "Icon!"
        ExitApp
    }

    config := {}
    config.GameWindowTitle := IniRead(configPath, "Game", "GameWindowTitle", "传奇")
    config.ActiveMinute := ReadIniInt(configPath, "Schedule", "ActiveMinute", 40)
    config.PreTriggerSeconds := ReadIniInt(configPath, "Schedule", "PreTriggerSeconds", 5)
    config.PostTriggerSeconds := ReadIniInt(configPath, "Schedule", "PostTriggerSeconds", 20)
    config.RegionX := ReadIniInt(configPath, "Search", "RegionX", 0)
    config.RegionY := ReadIniInt(configPath, "Search", "RegionY", 0)
    config.RegionW := ReadIniInt(configPath, "Search", "RegionW", 520)
    config.RegionH := ReadIniInt(configPath, "Search", "RegionH", 300)
    config.TemplatePath := ResolvePath(IniRead(configPath, "Search", "TemplatePath", "assets\teleport_button.png"))
    config.Variation := ReadIniInt(configPath, "Search", "Variation", 25)
    config.ClickOffsetX := ReadIniInt(configPath, "Click", "ClickOffsetX", 60)
    config.ClickOffsetY := ReadIniInt(configPath, "Click", "ClickOffsetY", 18)
    config.RetryCount := ReadIniInt(configPath, "Click", "RetryCount", 3)
    config.RetryIntervalMs := ReadIniInt(configPath, "Click", "RetryIntervalMs", 900)
    config.PostClickVerifyDelayMs := ReadIniInt(configPath, "Click", "PostClickVerifyDelayMs", 700)
    config.ExpCardEnabled := ReadIniInt(configPath, "ExpCard", "Enabled", 0)
    config.ExpCardActiveMinute := ReadIniInt(configPath, "ExpCard", "ActiveMinute", 0)
    config.ExpCardPreTriggerSeconds := ReadIniInt(configPath, "ExpCard", "PreTriggerSeconds", 5)
    config.ExpCardPostTriggerSeconds := ReadIniInt(configPath, "ExpCard", "PostTriggerSeconds", 20)
    config.ExpCardX := ReadIniInt(configPath, "ExpCard", "RelativeX", -1)
    config.ExpCardY := ReadIniInt(configPath, "ExpCard", "RelativeY", -1)
    config.ExpCardDoubleClickIntervalMs := ReadIniInt(configPath, "ExpCard", "DoubleClickIntervalMs", 120)
    config.ActivateTimeoutMs := ReadIniInt(configPath, "Window", "ActivateTimeoutMs", 2500)
    return config
}

ReadIniInt(configPath, section, key, defaultValue) {
    value := IniRead(configPath, section, key, defaultValue)
    return value + 0
}

ResolvePath(pathValue) {
    if RegExMatch(pathValue, "^[A-Za-z]:\\") || SubStr(pathValue, 1, 2) = "\\" {
        return pathValue
    }
    return A_ScriptDir "\" pathValue
}

EnsureRuntimePaths() {
    DirCreate A_ScriptDir "\logs"
    DirCreate A_ScriptDir "\assets"
}

ValidateTemplateAtStartup() {
    global Config

    if FileExist(Config.TemplatePath) {
        return
    }

    warning := "没有找到按钮模板图片：" Config.TemplatePath "`n`n请把“立即传送”按钮截图保存到这个路径，然后按 F9 手动测试。"
    Log("Template image missing at startup: " Config.TemplatePath)
    MsgBox warning, "传奇自动传送", "Icon!"
}

Log(message) {
    global LogFile

    timestamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    FileAppend timestamp " | " message "`n", LogFile, "UTF-8"
}
