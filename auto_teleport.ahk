#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

SetWorkingDir A_ScriptDir
SetTitleMatchMode 2
CoordMode "Mouse", "Screen"
CoordMode "Pixel", "Screen"

global ScriptEnabled := true
global Config := LoadConfig()
global LastProcessedHour := ""
global LastWindowMissingHour := ""
global OverlayGui := ""
global LogFile := A_ScriptDir "\logs\automation.log"

EnsureRuntimePaths()
ValidateTemplateAtStartup()
SetTimer CheckSchedule, 1000
Log("Script started.")
TrayTip "传奇自动传送", "脚本已启动。F8 开关，F9 测试，F10 显示识别区域，Esc 退出。"

F8::ToggleScript()
F9::ManualRun()
F10::ShowSearchOverlay()
Esc::ExitScript()

CheckSchedule() {
    global Config, ScriptEnabled, LastProcessedHour

    if !ScriptEnabled {
        return
    }

    if !IsWithinTriggerWindow() {
        return
    }

    currentHourKey := FormatTime(A_Now, "yyyyMMddHH")
    if (LastProcessedHour = currentHourKey) {
        return
    }

    if RunTeleportFlow("timer") {
        LastProcessedHour := currentHourKey
    }
}

ManualRun() {
    RunTeleportFlow("manual")
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

IsWithinTriggerWindow() {
    global Config

    minute := A_Min + 0
    second := A_Sec + 0
    nowSeconds := minute * 60 + second
    targetSeconds := Config.ActiveMinute * 60

    return (
        nowSeconds >= targetSeconds - Config.PreTriggerSeconds
        && nowSeconds <= targetSeconds + Config.PostTriggerSeconds
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
