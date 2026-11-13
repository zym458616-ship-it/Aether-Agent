# Aether

> 运行在 App 进程内的全权限 AI 智能体（iOS dylib，越狱 / roothide / rootless / 侧载注入均可）

Aether 把一个大模型 Agent 塞进任意 App 的进程里。打开悬浮球，告诉它要做什么，它会**真的**去看当前界面、点按滑动、敲 shell 命令、读写文件——而不是"演示"。

```
注入 dylib → 悬浮球 → 填 API/Key → 选模型 → 发任务 → 它自己干活
```

---

## 一、它到底能做什么

| 能力 | 实现方式（不是模拟） |
| --- | --- |
| 真实终端 | `posix_spawn` 起 `/var/jb/usr/bin/sh`（或 `/bin/sh`），管道读 stdout/stderr，支持超时与 kill |
| 读取任意文件 | `NSFileManager` / POSIX，受进程沙盒限制可读全局只读区 |
| 查看当前界面 | 遍历 `UIWindow` → `UIView` 树，输出元素 id、类名、文字、坐标 |
| 接管操控 | `IOHIDEvent` 数字仪注入真触摸；不可用时降级为控件语义点击（`sendActions` / 手势识别器 / `didSelectRow`） |
| 截图 | `drawViewHierarchyInRect:` 合成所有窗口，JPEG 存盘，可直传视觉模型 |
| 网络 | 任意 URLSession 请求 |
| 应用管理 | `LSApplicationWorkspace` 枚举 / 启动 |
| 上下文管理 | 估算 token + 服务端 `usage` 双轨，超限自动裁剪历史，面板实时显示占用 |

工具清单共 **22 个**，全部在「设置 → 能力清单」里可直接看到，也可以让模型自己列。

## 二、面板长什么样

- **悬浮球**：56pt 渐变球，可拖动、自动吸边、位置持久化；点一下开面板，长按出快捷菜单（新任务 / 终端 / 截图 / 隐藏）。
- **对话页**：流式输出、思考过程折叠、工具调用卡片（点开看完整入参与返回）、上下文占用条、停止按钮。
- **终端页**：真终端。命令历史、`cd` 切换目录、快捷命令条、退出码提示。
- **设置页**：协议（OpenAI 兼容 / Anthropic）、API 地址、Key（密文显示 + 一键粘贴）、模型列表拉取、最大上下文、最大步数、温度、流式/工具/视觉/思考/触感开关、系统提示词、悬浮球不透明度、数据清理。
- **历史页**：SQLite 持久化，按时间排序，左滑删除，点开继续。

## 三、配置与使用

1. **注入**：把 `Aether.dylib` 放进 IPA 的 `Payload/xxx.app/Frameworks/`，用你惯用的工具（ESign / TrollFools / Azule / Sideloadly / 越狱插件）注入并重签。
2. 打开目标 App，右侧出现悬浮球。
3. 点球 → 设置页：
   - 协议：`OpenAI 兼容`（绝大多数中转站、DeepSeek、Qwen、GLM、Ollama 都选这个）或 `Anthropic`
   - API 地址：`https://api.openai.com` / `https://api.deepseek.com` / 你的中转站，`/v1` 会自动补齐
   - API Key：填完点「测试连接 / 拉取模型」
   - 模型：点「模型」→ 刷新列表 → 选一个，或手动输入
4. 回对话页，输入任务，发送。
5. 之后的 Key / 模型 / 任务记录都会缓存，再打开 App 直接可用。

### 推荐任务写法

```
先 ui_dump 看看当前是什么页面，然后帮我把「深色模式」开关打开，打开后截图确认
```

明确「先观察 → 再操作 → 再验证」，成功率最高。

## 四、编译

无需本地 Mac，推送到 GitHub 后由 Actions 的 macOS runner 编译：

```
scripts/build.sh
```

产出 `build/Aether.dylib`：`arm64 + arm64e` 通用，ad-hoc 签名，`install_name = @executable_path/Frameworks/Aether.dylib`。

本地编译需要 macOS + Xcode Command Line Tools。

## 五、权限与限制（重要，请读完）

- Aether 运行在**宿主 App 的进程与沙盒**里。它能做的，就是该进程能做的：
  - 越狱环境（Dopamine / palera1n / roothide 等）：可以通过 `/var/jb` 使用完整 Unix 工具链；跨 App 沙盒读写仍然受内核沙盒约束。
  - 纯侧载（TrollStore / 企业签）：没有越狱，`/var/jb` 不存在，会退化为 `/bin/sh`，能操作的是 App 自身容器。
- **触摸注入**走私有 `IOHIDEvent` 接口。部分系统版本 / 未授权进程会拒绝派发，此时自动降级为语义点击（对 UIKit 控件、单元格、手势识别器有效，对纯自绘游戏界面无效）。工具返回里会体现结果，模型能感知并换策略。
- 不要指望它绕过 App 的付费墙、反作弊或做账号批量操作——那是滥用，也没写在代码里。
- API Key 存在宿主 App 的 `NSUserDefaults` 里，明文。共用设备请注意。

## 六、目录结构

```
Sources/
  Aether.h          统一接口
  Aether.m          构造函数入口
  AAConfig.m        配置持久化 + 主题 + 工具函数
  AAStore.m         SQLite 会话/消息持久化 + token 估算
  AAClient.m        OpenAI / Anthropic 流式客户端（含 tool_calls 解析）
  AAExecutor.m      posix_spawn 真实命令执行
  AAUIBridge.m      界面树 / 触摸注入 / 截图
  AATools.m         22 个工具的真实实现
  AAAgent.m         Agent 循环（工具调用、上下文裁剪、步数预算）
  AAOverlay.m       窗口 / 悬浮球 / 面板外壳
  AAChatUI.m        对话渲染（markdown-lite、工具卡片、输入器）
  AATerminalUI.m    终端
  AASettingsUI.m    设置 + 历史
scripts/build.sh    编译脚本
```

## 七、许可

MIT。仅供个人设备上的自动化与调试使用，请遵守当地法律与目标 App 的服务条款。
