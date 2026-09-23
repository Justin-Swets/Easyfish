<#
.SYNOPSIS
    Runs Sync-EasyFish.ps1 in the background from Windows logon, so EasyFish history always survives.

.DESCRIPTION
    Copies Sync-EasyFish.ps1 to %LOCALAPPDATA%\EasyFish (addon updates replace the addon folder, so it can't live
    there) and registers a per-user scheduled task "EasyFish Sync" that starts it in watch mode at logon.
    No administrator rights needed. Starts it immediately too.

    Remove it again with:  .\Install-EasyFishSync.ps1 -Uninstall

.PARAMETER WowRoot
    The Forever client folder. Default: C:\Program Files (x86)\World of Warcraft\_classic_beta_
#>
param(
    [string]$WowRoot = "C:\Program Files (x86)\World of Warcraft\_classic_beta_",
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$TaskName = "EasyFish Sync"
$Home_    = Join-Path $env:LOCALAPPDATA "EasyFish"
$Script   = Join-Path $Home_ "Sync-EasyFish.ps1"

if ($Uninstall) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item $Home_ -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "EasyFish Sync removed. Your saved history and backups under WTF are untouched."
    return
}

if (-not (Test-Path (Join-Path $WowRoot "WTF"))) { throw "No WTF folder under $WowRoot - pass -WowRoot with your Forever client folder." }

New-Item -ItemType Directory -Force $Home_ | Out-Null
Copy-Item (Join-Path $PSScriptRoot "Sync-EasyFish.ps1") $Script -Force

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Script`" -WowRoot `"$WowRoot`" -Watch"
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
    -Description "Keeps EasyFish fishing history across logins on the WoW: Forever beta." -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName

Write-Host "EasyFish Sync installed and running. It starts with Windows; nothing else to do."
Write-Host "Log: WTF\Account\<account>\SavedVariables\EasyFish-sync\sync.log"
