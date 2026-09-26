# Codex Windows Update Repair

An open-source Codex plugin and standalone PowerShell utility for diagnosing incomplete `cua_node` runtime extraction after a Windows Microsoft Store/AppX update.

## Important limitation

The plugin itself runs only after Codex starts. If Codex cannot open, use the standalone script from PowerShell. This project repairs local runtime files; it does not patch the signed Codex package or fix the upstream updater. A durable application-side fix must come from OpenAI.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7 on Windows x64
- Codex Desktop installed as the `OpenAI.Codex` AppX package
- Run under the same Windows user account that runs Codex
- Close Codex before runtime repair; the script refuses to modify files while Codex processes are active

## Audit first

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\plugins\codex-win-update-repair\scripts\Repair-CodexRuntime.ps1 -AuditOnly
```

Audit prints the installed package/runtime versions and checks whether a complete version-matched runtime or matching staging directory exists. Exit codes: `0` complete; `2` incomplete but matching stage found; `3` no current-version stage found; other nonzero values indicate an observed error.

## Repair and launch

After Codex has attempted to start once and left a matching `.staging-*` runtime directory, fully close Codex, then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\plugins\codex-win-update-repair\scripts\Repair-CodexRuntime.ps1 -Launch
```

The script copies the current package's official runtime into a fresh temporary directory, compares every relative path, byte length, and SHA-256 hash, and only then renames that validated directory to the observed content-addressed runtime ID. It never edits WindowsApps permissions, deletes old runtimes, overwrites an existing final directory, or stops running Codex processes.

If no matching stage exists, the script refuses to guess a runtime ID. Attempt one normal launch, close any headless Codex processes, then rerun audit and repair.

## Codex plugin

The plugin contains a skill that guides Codex through the audit/repair workflow. It cannot solve a failure that prevents the desktop app from reaching plugin execution; the standalone script is the pre-launch recovery path.

## Repository marketplace installation

From a Codex CLI installation that supports plugins:

```powershell
codex plugin marketplace add ledi0903/codex-win-update-repair --sparse .agents/plugins --sparse plugins
```

Then install `codex-win-update-repair` from the plugin browser. Availability of marketplace commands depends on the Codex client version. Repository-based installation is separate from submitting a plugin to the public ChatGPT/Codex directory.

## Verification

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-RepairScript.ps1
python -m json.tool .\plugins\codex-win-update-repair\.codex-plugin\plugin.json
python -m json.tool .\.agents\plugins\marketplace.json
```

## Safety and privacy

No telemetry or network requests are made by the repair utility. It does not read credentials, cookies, conversation data, or authentication files. It reads package/runtime file names and hashes only to verify the copy.

## License

MIT. See `LICENSE`.
