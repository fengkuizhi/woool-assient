# 传奇活动自动点击

这是一个面向 Windows 10 的 `AutoHotkey v2` 脚本。它会在每小时 `40` 分附近检查传奇游戏窗口，在左上区域识别“立即传送”按钮并自动点击。

## 文件

- `auto_teleport.ahk`：主脚本
- `config.ini`：配置文件
- `assets/teleport_button.png`：你需要自己提供的按钮模板图
- `logs/automation.log`：运行日志，脚本启动后自动生成

## 安装与运行

1. 在 Windows 10 上安装 `AutoHotkey v2`
2. 把本目录复制到 Windows 10 电脑
3. 准备按钮模板图：
   - 游戏里弹出活动窗口时截图
   - 只裁出“立即传送”按钮，尽量紧贴按钮边缘
   - 保存为 `assets/teleport_button.png`
4. 检查 `config.ini`：
   - `GameWindowTitle` 改成你的游戏窗口标题关键字
   - `RegionX/RegionY/RegionW/RegionH` 默认只搜窗口左上区域
   - `ClickOffsetX/ClickOffsetY` 默认点击模板图内部偏中间的位置
5. 双击运行 `auto_teleport.ahk`

## 热键

- `F8`：启用/暂停自动点击
- `F9`：立即手动测试一次识别和点击
- `F10`：显示当前识别区域覆盖层，便于确认搜索范围
- `Esc`：退出脚本

## 调参建议

如果 `F9` 找不到按钮，优先检查下面几项：

1. 模板图是否裁得过大
2. `GameWindowTitle` 是否能匹配到窗口
3. `RegionW/RegionH` 是否覆盖了弹窗区域
4. `Variation` 是否太低

建议调参顺序：

1. 先按 `F10` 确认识别区域
2. 再按 `F9` 测试
3. 如果能识别但点偏了，调整 `ClickOffsetX/ClickOffsetY`
4. 如果识别不稳定，把 `Variation` 从 `25` 往上试到 `35-45`
5. 如果找不到窗口标题，可用 AutoHotkey 自带的 `Window Spy` 看窗口标题后回填到 `GameWindowTitle`

## 限制

- 游戏窗口不能最小化
- 第一版按桌面层识别和鼠标点击实现，不处理更底层的输入拦截
- 如果你切换了分辨率、UI 缩放或游戏界面样式，可能需要重截模板图
