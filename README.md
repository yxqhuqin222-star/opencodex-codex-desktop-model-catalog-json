# OpenCodex Codex Desktop Model Menu

把本机 OpenCodex 已配置的模型接入 Codex Desktop 原生模型菜单，并把菜单收窄到少量可用模型。

这个项目来自一次实际调试后的稳定方案。核心原则：

- 保留 Codex 原生 OpenAI provider，不新增 model_provider 或 [model_providers.*]。
- 只用顶层 openai_base_url = "http://127.0.0.1:10100/v1" 接入本地 OpenCodex 路由器。
- 用 model_catalog_json 控制 Desktop 原生模型菜单。
- 不修改 Codex 任务数据库，不执行 history recover。
- Kimi 走 moonshot-cn，避免内置 moonshot 固定区域端点导致 401。
- GLM 走 zai 原生路径，不保留 qwen-cloud 的 GLM 镜像。

## 保留的模型

默认只保留这些模型；本机不存在的 slug 会自动跳过。

- gpt-5.6-terra
- gpt-5.5
- deepseek/deepseek-v4-flash
- deepseek/deepseek-v4-pro
- qwen-cloud/qwen3.8-max
- qwen-cloud/qwen3-coder-plus
- moonshot-cn/kimi-k3
- moonshot-cn/kimi-k2.7-code
- zai/glm-5.2
- zai/glm-5.3
- qwen-cloud/MiniMax-MiniMax-M3

## 使用方式

先确认本机已安装并配置 OpenCodex：

    ocx status
    ocx provider list

然后运行：

    bash scripts/apply-opencodex-desktop-menu.sh

脚本会备份配置、启用 moonshot-cn、设置顶层 openai_base_url 和 model_catalog_json、执行 ocx sync、硬裁剪 catalog、刷新 Desktop 模型缓存，并真实调用测试 Kimi、GLM、Qwen、DeepSeek。

刷新 Desktop 菜单时，如果使用：

    ocx sync-cache --restart-codex

当前 Codex 任务会短暂断开。这是 app-server 重启的预期副作用，不代表任务历史被删除。

## Kimi 注意事项

不要使用内置 moonshot provider。OpenCodex 的内置 moonshot 可能固定走 https://api.moonshot.ai/v1。如果你的 key 是中国区 Moonshot/Kimi key，就会 401。脚本使用自定义 moonshot-cn -> https://api.moonshot.cn/v1。

也不要保留 qwen-cloud/kimi-* 或 qwen-cloud/kimi-kimi-*，这类镜像容易触发阿里侧 The product is not activated。

## 验证

脚本最后会真实请求：

- moonshot-cn/kimi-k2.7-code
- moonshot-cn/kimi-k3
- zai/glm-5.2
- zai/glm-5.3
- qwen-cloud/qwen3.8-max
- deepseek/deepseek-v4-flash

不要只看 ocx provider test，真实推理返回指定文本才算可用。

## 回滚

脚本会在 ~/.codex/backups/opencodex-desktop-menu-<timestamp>/ 下备份配置。需要回滚时，把备份文件复制回原位置，再重启 OpenCodex。

