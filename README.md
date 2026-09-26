# Codex Windows 更新后启动修复工具

[English summary](#english-summary) · [GitHub 仓库](https://github.com/ledi0903/codex-win-update-repair)

## 这是什么，解决什么问题？

这是一个面向 **Windows 商店版 Codex Desktop** 的诊断与本地修复工具，针对这一类故障：

1. Codex 更新后打不开、只在任务管理器里出现后台进程，或没有可用窗口；
2. 更新引入了新的 `cua_node` 运行时版本；
3. `%LOCALAPPDATA%\OpenAI\Codex\runtimes\cua_node` 里只有与当前版本匹配的 `.staging-*` 暂存目录，缺少完整的正式运行时目录。

修复器会从当前安装的 `OpenAI.Codex` AppX 包读取官方运行时文件，把文件复制到新临时目录，逐项比较相对路径、文件大小和 SHA-256；全部匹配后才将目录改名为暂存目录所指示的运行时 ID。随后可通过 Windows 注册的 AppX 入口启动 Codex。

**它不修复所有“Codex 打不开”的原因。**如果问题是登录、网络、GPU、配置或别的组件，本工具不会解决。它也不修改或绕过 Codex 签名包，不改 `WindowsApps` 权限，不清除登录、聊天历史或配置。

## 使用前

- Windows x64，安装了 Microsoft Store/AppX 版 `OpenAI.Codex`。
- 使用运行 Codex 的同一个 Windows 用户账户。
- 修复前先完全退出 Codex。脚本检测到该包的进程仍在运行时会停止并提示，不会替你强制结束进程。
- 如果 Codex 当前有可见窗口，不要运行修复；先保存工作并正常退出。

## 逐步操作

### 1. 下载仓库

在 PowerShell 中运行：

```powershell
git clone https://github.com/ledi0903/codex-win-update-repair.git
Set-Location .\codex-win-update-repair
```

后续命令都从仓库根目录运行。

### 2. 先只读诊断

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\plugins\codex-win-update-repair\scripts\Repair-CodexRuntime.ps1 -AuditOnly
```

按输出判断：

- `runtime=complete`，退出码 `0`：当前运行时完整；这不是本工具针对的损坏状态。可尝试从正常入口启动 Codex。
- `runtime=incomplete stage=...`，退出码 `2`：找到了与当前 AppX 版本相符的暂存目录，可继续修复。
- `matching staging directory not found`，退出码 `3`：没有足够证据推断运行时 ID。不要手工猜 ID；如果 Codex 尚未尝试启动，可尝试正常启动一次，使其生成暂存目录。之后完全退出 Codex，再重新执行本步骤。
- 其他非零退出码：脚本检测到包、文件或状态异常，保留原样并先查看报错，不要删除旧运行时目录。

### 3. 修复并尝试启动

当审计结果为退出码 `2` 时，确认 Codex 已完全退出，再运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\plugins\codex-win-update-repair\scripts\Repair-CodexRuntime.ps1 -Launch
```

脚本只会从当前安装包复制到一个新建的临时目录；验证完成后才移动到目标目录。若目标正式目录已存在但不完整，脚本会保留该目录并停止，不覆盖它。若文件复制或哈希验证失败，脚本会清理自己创建的临时目录并报告错误，不会触碰源安装包。

成功时应看到 `runtime=complete`，以及启动结果 `launch=visible`。如果显示 `launch=not-yet-visible`，代表运行时修复成功，但窗口尚未确认；请等待片刻并检查桌面窗口，不要把它当成已验证启动。

### 4. 安装 Codex 插件（可选）

插件包含一个指导 Codex 执行上述诊断步骤的 Skill。它**需要 Codex 已经启动**，因此桌面端打不开时应直接运行第 2、3 步的独立 PowerShell 脚本。

若当前 Codex CLI 支持插件 Marketplace，可添加本仓库：

```powershell
codex plugin marketplace add ledi0903/codex-win-update-repair --sparse .agents/plugins --sparse plugins
```

然后在 Codex 插件浏览器中安装 `codex-win-update-repair`。CLI 命令和 UI 可能因 Codex 版本而异；仓库中的独立修复脚本不依赖插件安装。

## 隐私与安全

- 不发送网络请求，不收集遥测。
- 不读取凭据、Cookie、聊天内容或认证文件。
- 仅读取当前 AppX 运行时文件及本地运行时目录，以检查版本、文件路径、大小和 SHA-256。
- 不删除旧 `.staging-*` 目录、不覆盖已存在的正式运行时、不更改 WindowsApps 权限。

## 验证开发版本

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-RepairScript.ps1
python -m json.tool .\plugins\codex-win-update-repair\.codex-plugin\plugin.json
python -m json.tool .\.agents\plugins\marketplace.json
```

测试使用合成文件夹，不修改真实 Codex 安装。

## 上游问题

此项目是本地恢复工具，不是 OpenAI 发布的补丁。若未来版本改变暂存目录命名、清单格式或运行时路径，修复器会停止而不是猜测。彻底修复仍需 Codex 更新程序正确处理 Windows AppX 运行时提取与暂存提交。

## English summary

This repository provides a Codex plugin and a standalone PowerShell utility for one specific Windows failure: an AppX update leaves the current `cua_node` runtime incomplete in a matching `.staging-*` directory. The utility audits the package, copies the bundled runtime to a fresh temporary directory, verifies every relative path, size, and SHA-256 hash, then finalizes it and can launch Codex through its registered AppX identity. It does not patch the signed app or fix unrelated startup failures. The standalone script works even when the Codex UI cannot start; the plugin itself does not.

## License

MIT. See `LICENSE`.
