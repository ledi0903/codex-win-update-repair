---
name: codex-win-update-repair
description: Diagnose and repair incomplete Windows Codex Desktop runtime extraction after a Microsoft Store update. Use only for local OpenAI.Codex AppX runtime staging failures.
---

# Codex Windows Update Repair

This plugin helps diagnose the Windows AppX runtime-copy failure that can leave Codex Desktop with incomplete `.staging-*` folders after an update.

## Important boundary

The plugin runs only after Codex has launched. If the desktop cannot open, run the bundled PowerShell repair utility directly from a separate PowerShell window. This utility is a local workaround; it does not patch the signed app package or fix the upstream updater.

## Workflow

1. Confirm the target is the locally installed `OpenAI.Codex` AppX package.
2. Inspect the current package version, bundled `cua_node\manifest.json`, and local runtime staging/final directories.
3. Do not stop, reset, reinstall, or delete app state. If a Codex window is open, leave it alone and ask the user to close it before changing runtime files.
4. Run the repair script in audit mode first:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<plugin-root>\scripts\Repair-CodexRuntime.ps1" -AuditOnly
   ```

5. If audit finds a matching incomplete staging directory and no Codex process is running, run:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<plugin-root>\scripts\Repair-CodexRuntime.ps1" -Launch
   ```

6. Verify that the script reports `runtime=complete`, AppX status is `Ok`, and a visible `ChatGPT` window appears when `-Launch` was requested.

If no matching staging directory exists, do not guess a content-addressed runtime ID. Ask the user to attempt one normal launch, close any remaining headless `ChatGPT.exe` processes, then rerun audit. If a copy/hash check fails, preserve the source and partial diagnostic evidence; do not change WindowsApps ACLs or delete unrelated runtime directories.

## Evidence to report

Record package version, runtime archive version, stage ID, file count/verification result, command exit code, and whether AppX launch produced a visible window. Do not include tokens, account state, conversation contents, or unrelated local paths in a public issue report.
