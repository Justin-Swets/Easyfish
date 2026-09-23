<#
.SYNOPSIS
    Keeps EasyFish history across logins on the World of Warcraft: Forever beta.

.DESCRIPTION
    The Forever beta client writes SavedVariables when you log out but never reads them back, so every login
    starts with empty history. This script copies EasyFish's saved file into the addon folder as
    EasyFish_Saved.lua, which the addon loads as ordinary code.

    It also protects history:
      * Every save is backed up (WTF\...\SavedVariables\EasyFish-sync\backups, last 40 kept).
      * A save that did not grow out of the current history (a session played while history failed to load)
        is kept as an "orphan"; the addon merges it back in on the next login, once.

    Run it before starting the game, or run Install-EasyFishSync.ps1 once to keep it running in the background.

.PARAMETER WowRoot
    The Forever client folder. Default: C:\Program Files (x86)\World of Warcraft\_classic_beta_

.PARAMETER Watch
    Keep running and sync each time the game writes the file.
#>
param(
    [string]$WowRoot = "C:\Program Files (x86)\World of Warcraft\_classic_beta_",
    [switch]$Watch
)

$ErrorActionPreference = "Stop"
$AddonDir = Join-Path $WowRoot "Interface\AddOns\EasyFish"
$Utf8 = New-Object System.Text.UTF8Encoding $false

function Read-Text([string]$Path) { [IO.File]::ReadAllText($Path) }
function Write-Text([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, $Utf8) }
function Get-ShortHash([string]$Path) { (Get-FileHash $Path -Algorithm SHA1).Hash.Substring(0, 12).ToLower() }

# Top-level scalar as the client writes it:  ["name"] = value,   or   ["name"] = "value",
function Get-Field([string]$Text, [string]$Name) {
    $m = [regex]::Match($Text, '\["' + [regex]::Escape($Name) + '"\] = "?([^",\r\n]*)"?,')
    if ($m.Success) { return $m.Groups[1].Value }
    return ""
}

# The addon records every orphan it has merged in ["mergedOrphans"] = { ["id"] = true, ... }
function Test-Merged([string]$MainText, [string]$Id) {
    return $MainText -match ('\["mergedOrphans"\] = \{[^}]*\["' + [regex]::Escape($Id) + '"\] = true')
}

# Files written before lineage existed get one, so the history they start can be followed from then on
function Add-Lineage([string]$Text) {
    if (Get-Field $Text "lineage") { return $Text }
    $id = "{0:x}{1:x4}" -f [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(), (Get-Random -Maximum 65536)
    return ([regex]'EasyFishDB = \{').Replace($Text, "EasyFishDB = {`n[`"lineage`"] = `"$id`",", 1)
}

function Write-Log([string]$SyncDir, [string]$Message) {
    $line = "{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $Message
    Add-Content -Path (Join-Path $SyncDir "sync.log") -Value $line -Encoding UTF8
    Write-Host $line
}

function Sync-Account([string]$SvDir) {
    $cur = Join-Path $SvDir "EasyFish.lua"
    if (-not (Test-Path $cur)) { return $null }

    $sync    = Join-Path $SvDir "EasyFish-sync"
    $orphans = Join-Path $sync "orphans"
    $backups = Join-Path $sync "backups"
    New-Item -ItemType Directory -Force $orphans, $backups | Out-Null
    $mainPath = Join-Path $sync "main.lua"
    $curText  = Read-Text $cur
    $curHash  = Get-ShortHash $cur

    # Back up every distinct save
    if (-not (Get-ChildItem $backups -Filter "*-$curHash.lua")) {
        $stamp = (Get-Item $cur).LastWriteTime.ToString("yyyyMMdd-HHmmss")
        Copy-Item $cur (Join-Path $backups "EasyFish-$stamp-$curHash.lua")
        Get-ChildItem $backups -Filter "EasyFish-*.lua" | Sort-Object Name -Descending |
            Select-Object -Skip 40 | Remove-Item
    }

    # Which save main.lua was last taken from; the same save seen again is not news
    $sourcePath = Join-Path $sync "main.source"
    $lastSource = if (Test-Path $sourcePath) { (Read-Text $sourcePath).Trim() } else { "" }

    if (-not (Test-Path $mainPath)) {
        Write-Text $mainPath (Add-Lineage $curText)
        Write-Text $sourcePath $curHash
        # if this exact save was also set aside as an orphan, it is the main history now
        Remove-Item (Join-Path $orphans "$curHash.lua") -ErrorAction SilentlyContinue
        Write-Log $sync "started history from the current save"
    }
    elseif ($curHash -eq $lastSource) {
        # nothing new since the last sync
    }
    else {
        $mainText = Read-Text $mainPath
        $curLin   = Get-Field $curText "lineage"
        $mainLin  = Get-Field $mainText "lineage"
        $curSaves  = [int]("0" + (Get-Field $curText "saves"))
        $mainSaves = [int]("0" + (Get-Field $mainText "saves"))

        if ($curLin -and $curLin -eq $mainLin) {
            if ($curSaves -ge $mainSaves -and $curText -ne $mainText) {
                Write-Text $mainPath $curText
                Write-Text $sourcePath $curHash
                Write-Log $sync "history updated (save $curSaves)"
            }
        }
        else {
            # Not grown from the current history: a session played while history failed to load. Keep it.
            $id = if ($curLin) { $curLin } else { $curHash }
            $orphanPath = Join-Path $orphans "$id.lua"
            if (-not (Test-Merged $mainText $id)) {
                Write-Text $orphanPath $curText
                Write-Log $sync "kept session $id to merge on next login"
            }
            Write-Text $sourcePath $curHash
        }
    }

    # Orphans the addon has already merged are done with
    $mainText = Read-Text $mainPath
    $mainLin  = Get-Field $mainText "lineage"
    foreach ($f in Get-ChildItem $orphans -Filter "*.lua") {
        if ($f.BaseName -eq $mainLin -or (Test-Merged $mainText $f.BaseName)) {
            Remove-Item $f.FullName
            Write-Log $sync "session $($f.BaseName) is merged; removed"
        }
    }

    return [pscustomobject]@{ Sync = $sync; Main = $mainPath; Orphans = $orphans; Written = (Get-Item $cur).LastWriteTime }
}

function Sync-All {
    $accounts = Join-Path $WowRoot "WTF\Account"
    if (-not (Test-Path $accounts)) { throw "No WTF\Account folder under $WowRoot - is this the Forever client folder?" }
    $results = @()
    foreach ($sv in Get-ChildItem $accounts -Directory | ForEach-Object { Join-Path $_.FullName "SavedVariables" }) {
        if (Test-Path $sv) { $r = Sync-Account $sv; if ($r) { $results += $r } }
    }
    if ($results.Count -eq 0) { Write-Host "No EasyFish saved data yet - log in and out once with the addon enabled."; return }
    if (-not (Test-Path $AddonDir)) { Write-Host "EasyFish is not installed at $AddonDir"; return }

    # The addon folder is shared by every account; use the account played most recently
    $r = $results | Sort-Object Written -Descending | Select-Object -First 1

    $out = New-Object System.Text.StringBuilder
    [void]$out.AppendLine("-- Generated by tools\Sync-EasyFish.ps1 on $(Get-Date -Format 'yyyy-MM-dd HH:mm'). Rewritten on every sync; do not edit.")
    [void]$out.AppendLine(([regex]'EasyFishDB = ').Replace((Read-Text $r.Main), 'EasyFishSnapshot = ', 1))
    [void]$out.AppendLine("EasyFishOrphans = EasyFishOrphans or {}")
    $n = 0
    foreach ($f in Get-ChildItem $r.Orphans -Filter "*.lua") {
        $text = ([regex]'EasyFishDB = ').Replace((Read-Text $f.FullName), "EasyFishOrphans[`"$($f.BaseName)`"] = ", 1)
        [void]$out.AppendLine($text)
        $n++
    }
    Write-Text (Join-Path $AddonDir "EasyFish_Saved.lua") $out.ToString()
    Write-Log $r.Sync ("addon snapshot written ({0} unmerged session{1})" -f $n, $(if ($n -eq 1) { "" } else { "s" }))
}

Sync-All

if ($Watch) {
    $watcher = New-Object IO.FileSystemWatcher (Join-Path $WowRoot "WTF\Account"), "EasyFish.lua"
    $watcher.IncludeSubdirectories = $true
    $watcher.NotifyFilter = [IO.NotifyFilters]'LastWrite, FileName, Size'
    Write-Host "Watching for EasyFish saves. Leave this running while you play."
    while ($true) {
        $change = $watcher.WaitForChanged([IO.WatcherChangeTypes]::All, 60000)
        if ($change.TimedOut) { continue }
        Start-Sleep -Milliseconds 400   # let the client finish writing
        try { Sync-All } catch { Write-Host "sync failed: $_" }
    }
}
