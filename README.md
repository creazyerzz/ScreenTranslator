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
- 拖动选择屏幕区域
- 等待 OCR 和翻译完成，结果会显示在悬浮窗口

## macOS 权限

首次使用可能需要授权：

- 屏幕录制：允许程序读取截图内容
- 输入监听或辅助功能：如果快捷键无法触发，请给运行程序的宿主授权

如果通过 `swift run` 启动，macOS 可能把权限记到 Terminal/iTerm；如果通过 `.app` 启动，权限会记到 `ScreenTranslator.app`。

## 当前限制

- 截图框选优先覆盖鼠标所在屏幕。
- OCR 使用 Apple Vision，本地完成，不上传截图。
- 只上传 OCR 识别后的文本到翻译接口。
