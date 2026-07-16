# ScreenTranslator

独立 macOS 截图翻译工具。常驻菜单栏，支持快捷键框选屏幕区域，本机 OCR 后调用 OpenAI 兼容的 `/v1/chat/completions` 接口翻译。

## 默认接口

- API 地址：`https://kaizo.top/v1/chat/completions`
- 模型：`gpt-5.4-mini` 或 `gpt-5.4`
- 目标语言：`中文`

首次运行后在菜单栏点击 `译` -> `设置`，选择模型、粘贴密钥并保存。API Key 会以明文写入当前用户的应用配置，不再访问 macOS Keychain；之后打开设置时也会直接显示。

## 运行

```bash
cd ScreenTranslator
swift run
```

也可以构建成 `.app`：

```bash
cd ScreenTranslator
chmod +x scripts/build_app.sh
./scripts/build_app.sh
open build/ScreenTranslator.app
```

## 使用

- 菜单栏点击 `译` -> `截图翻译`
- 或使用快捷键：`Control + Option + T`
- 拖动选择屏幕区域，松开后出现 `翻译` / `取消` 按钮，点 `翻译` 或按回车确认；重新拖动可调整选区；按 `Esc` 或右键随时退出
- 等待 OCR 和翻译完成，结果会显示在悬浮窗口（按 `Esc` 可关闭）
- 翻译期间菜单栏图标显示 `…`，完成后恢复为 `译`
- 菜单栏 `显示上次结果` 可重新打开最近一次翻译窗口

### 结果窗口

- `复制原文` / `复制译文`，复制后有状态提示
- `重新翻译`：对当前原文按最新设置再次翻译
- 设置中可开启“翻译完成后自动复制译文”

### 设置

- API Key 默认以密文显示，可点眼睛图标切换明文
- 模型支持手动输入，也可以从下拉列表选择
- 目标语言支持下拉选择常用语言，也可以直接输入任意语言
- `测试连接`：用当前填写的地址、模型和 Key 发送一次试翻译验证配置

### 翻译历史

- 支持按关键字搜索原文/译文
- 支持删除单条记录；清空历史会二次确认
- 记录仅保留近 7 天

## macOS 权限

首次使用可能需要授权：

- 屏幕录制：允许程序读取截图内容
- 输入监听或辅助功能：如果快捷键无法触发，请给运行程序的宿主授权

如果通过 `swift run` 启动，macOS 可能把权限记到 Terminal/iTerm；如果通过 `.app` 启动，权限会记到 `ScreenTranslator.app`。

## 当前限制

- 截图框选优先覆盖鼠标所在屏幕。
- OCR 使用 Apple Vision，本地完成，不上传截图；开启自动语言检测，覆盖中英日韩法德西俄葡。
- 只上传 OCR 识别后的文本到翻译接口。
