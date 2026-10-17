# Noise Floor, portable copy: brings in a newer build from the family drive, if one is there.
# "Play Noise Floor.bat" runs this before the game starts. It reads update_from.txt (one folder per line, the first
# one that answers wins), and if that folder's version.txt differs from game\version.txt it copies NoiseFloor.zip
# down, unpacks it, and mirrors its game and godot folders over these (saved games live in %APPDATA%, never here).
# A folder that doesn't answer within a few seconds is skipped; any problem leaves this copy exactly as it was.
# P6: it also copies this PC's play-session logs to logs\<computer name>\ in that folder, so a problem met on
# another PC can be read on the one that makes the game (best effort: a drive you can't write to is skipped).
param([string]$Here)
$ErrorActionPreference = "Stop"

function Send-SessionLogs([string]$src) {
    try {
        $sessions = Join-Path $env:APPDATA "Godot\app_userdata\Noise Floor\sessions"
        if (-not (Test-Path -LiteralPath $sessions)) { return }
        $to = Join-Path (Join-Path $src "logs") $env:COMPUTERNAME
        # /XO: only logs that are new or changed; one quick retry, so a read-only drive can't hold up the game.
        robocopy $sessions $to *.txt /XO /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { Write-Host "Couldn't copy the play logs to the family drive." }
        else { Write-Host "Play logs copied to the family drive." }
    } catch {
        Write-Host "Couldn't copy the play logs ($($_.Exception.Message))."
    }
}

try {
    $local = ""
    $localFile = Join-Path $Here "game\version.txt"
    if (Test-Path -LiteralPath $localFile) { $local = (Get-Content -LiteralPath $localFile -TotalCount 1).Trim() }
    $sources = Get-Content -LiteralPath (Join-Path $Here "update_from.txt") |
        Where-Object { $_.Trim() -ne "" -and -not $_.Trim().StartsWith("#") }
    foreach ($src in $sources) {
        $src = $src.Trim()
        $ver = Join-Path $src "version.txt"
        # An unreachable network path can hang for half a minute: ask in the background, give up after 4 s.
        $job = Start-Job -ScriptBlock { param($p) Test-Path -LiteralPath $p } -ArgumentList $ver
        if (-not (Wait-Job $job -Timeout 4)) { Remove-Job $job -Force; continue }
        $found = Receive-Job $job
        Remove-Job $job -Force
        if (-not $found) { continue }
        Send-SessionLogs $src
        $remote = (Get-Content -LiteralPath $ver -TotalCount 1).Trim()
        if ($remote -eq $local) {
            Write-Host "Noise Floor is up to date."
            return
        }
        Write-Host "Updating Noise Floor to: $remote"
        $tmp = Join-Path $env:TEMP "noise_floor_update"
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
        New-Item -ItemType Directory -Path $tmp | Out-Null
        Copy-Item -LiteralPath (Join-Path $src "NoiseFloor.zip") -Destination (Join-Path $tmp "NoiseFloor.zip")
        Expand-Archive -LiteralPath (Join-Path $tmp "NoiseFloor.zip") -DestinationPath $tmp -Force
        $new = Join-Path $tmp "NoiseFloor"
        if (-not (Test-Path -LiteralPath (Join-Path $new "game\project.godot"))) { throw "the new copy looks incomplete" }
        # version.txt goes last, so a copy that fails halfway (the game still open, say) is tried again next start.
        foreach ($part in @("game", "godot")) {
            robocopy (Join-Path $new $part) (Join-Path $Here $part) /MIR /XF version.txt /NFL /NDL /NJH /NJS /NP | Out-Null
            if ($LASTEXITCODE -ge 8) { throw "copying the $part folder failed" }
        }
        Copy-Item -LiteralPath (Join-Path $new "game\version.txt") -Destination $localFile -Force
        foreach ($f in @("README.txt", "update_from.txt", "update.ps1")) {
            $from = Join-Path $new $f
            if (Test-Path -LiteralPath $from) { Copy-Item -LiteralPath $from -Destination (Join-Path $Here $f) -Force }
        }
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Updated."
        return
    }
} catch {
    Write-Host "Couldn't update ($($_.Exception.Message)); playing the version you have."
}
