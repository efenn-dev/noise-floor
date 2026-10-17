# Noise Floor, portable copy: brings in a newer build from the family drive, if one is there.
# "Play Noise Floor.bat" runs this before the game starts. It reads update_from.txt (one folder per line, the first
# one that answers wins), and if that folder's version.txt differs from game\version.txt it copies NoiseFloor.zip
# down, unpacks it, and swaps the new game and godot folders in (saved games live in %APPDATA%, never here).
# A folder that doesn't answer within a few seconds is skipped; any problem leaves this copy as it was.
# P6: it also copies this PC's play-session logs to logs\<computer name>\ in that folder, so a problem met on
# another PC can be read on the one that makes the game (best effort: a drive you can't write to is skipped).
# P7: the son's game ran the new arm models with the old code: an update closed halfway had copied assets\ but
# not src\. Each folder is now copied in full beside the live one (game.new) and swapped in by two renames, so a
# closed window leaves the old version or the new one, never a mix; the unzip is .NET's (seconds, not minutes);
# each step says what it's doing; and a second launcher waits for the first instead of copying over it.
# P9: a line in update_from.txt starting https:// is the family's private folder on the CDN (password in
# family_cdn.txt beside this script), so this PC updates even when the PC with the R: drive is off. Folder lines are
# tried first (fast at home), the web one after. version.txt's second line, "sha256 <hex>", is the zip's
# fingerprint: a download that doesn't match is thrown away.
param([string]$Here)
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# "Basic ..." for the CDN folder, from family_cdn.txt ("user:password"), or $null without one.
function Get-Auth([string]$Here) {
    $f = Join-Path $Here "family_cdn.txt"
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    $pair = (Get-Content -LiteralPath $f -TotalCount 1).Trim()
    return "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
}

function Open-Web([string]$url, $auth, [int]$timeout) {
    $req = [System.Net.HttpWebRequest]::Create($url)
    $req.Timeout = $timeout
    $req.ReadWriteTimeout = [Math]::Max($timeout, 30000)
    if ($auth) { $req.Headers["Authorization"] = $auth }
    return $req.GetResponse()
}

function Get-WebText([string]$url, $auth) {
    $resp = Open-Web $url $auth 8000
    try { return (New-Object System.IO.StreamReader($resp.GetResponseStream())).ReadToEnd() } finally { $resp.Close() }
}

# Downloads `url` to `to`, saying how far it's got every 10 percent.
function Get-WebFile([string]$url, $auth, [string]$to) {
    $resp = Open-Web $url $auth 15000
    try {
        $total = $resp.ContentLength
        $in = $resp.GetResponseStream()
        $out = [System.IO.File]::Create($to)
        try {
            $buf = New-Object byte[] 1048576
            $done = 0
            $shown = 0
            while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
                $out.Write($buf, 0, $n)
                $done += $n
                if ($total -gt 0) {
                    $pct = [int](100 * $done / $total)
                    if ($pct -ge $shown + 10) { Write-Host "      $pct%"; $shown = $pct - ($pct % 10) }
                }
            }
        } finally { $out.Close() }
    } finally { $resp.Close() }
}

# The "sha256 <hex>" line of a version.txt's text, or "" when it has none.
function Get-Fingerprint([string]$text) {
    foreach ($line in ($text -split "`r?`n")) {
        if ($line.Trim().StartsWith("sha256 ")) { return $line.Trim().Substring(7).Trim().ToLower() }
    }
    return ""
}

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

# A swap cut off between its two renames leaves part.old and no part: put the old one back. A copy cut off
# before its swap leaves a half-filled part.new: clear it.
function Restore-Interrupted([string]$Here) {
    foreach ($part in @("game", "godot")) {
        $live = Join-Path $Here $part
        $old = Join-Path $Here "$part.old"
        if (-not (Test-Path -LiteralPath $live) -and (Test-Path -LiteralPath $old)) {
            Rename-Item -LiteralPath $old -NewName $part
            Write-Host "Put back the $part folder from an update that was cut off."
        }
        $staged = Join-Path $Here "$part.new"
        if (Test-Path -LiteralPath $staged) { Remove-Item -LiteralPath $staged -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# The whole new folder goes in beside the live one first, then two renames swap it in.
function Install-Part([string]$from, [string]$Here, [string]$part) {
    $live = Join-Path $Here $part
    $staged = Join-Path $Here "$part.new"
    $old = Join-Path $Here "$part.old"
    foreach ($leftover in @($staged, $old)) {
        if (Test-Path -LiteralPath $leftover) { Remove-Item -LiteralPath $leftover -Recurse -Force }
    }
    try {
        Move-Item -LiteralPath $from -Destination $staged  # instant on the same drive
    } catch {
        robocopy $from $staged /E /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "copying the $part folder failed" }
    }
    if (Test-Path -LiteralPath $live) { Rename-Item -LiteralPath $live -NewName "$part.old" }
    Rename-Item -LiteralPath $staged -NewName $part
    Remove-Item -LiteralPath $old -Recurse -Force -ErrorAction SilentlyContinue
}

# True if the new folder's Godot is the same file as the one already here (it rarely changes; 170 MB to move).
function Same-Godot([string]$new, [string]$Here) {
    $a = Get-ChildItem -LiteralPath $new -Filter *.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $a) { return $true }
    $b = Join-Path (Join-Path $Here "godot") $a.Name
    if (-not (Test-Path -LiteralPath $b)) { return $false }
    return (Get-Item -LiteralPath $b).Length -eq $a.Length
}

$mutex = New-Object System.Threading.Mutex($false, "NoiseFloorUpdate")
$held = $false
try {
    if (-not $mutex.WaitOne(0)) {
        Write-Host "Noise Floor is already updating in another window: waiting for it to finish..."
        [void]$mutex.WaitOne()
    }
    $held = $true
    Restore-Interrupted $Here
    $local = ""
    $localFile = Join-Path $Here "game\version.txt"
    if (Test-Path -LiteralPath $localFile) { $local = (Get-Content -LiteralPath $localFile -TotalCount 1).Trim() }
    $sources = Get-Content -LiteralPath (Join-Path $Here "update_from.txt") |
        Where-Object { $_.Trim() -ne "" -and -not $_.Trim().StartsWith("#") }
    $folders = @($sources | Where-Object { -not $_.Trim().StartsWith("http") })
    $webs = @($sources | Where-Object { $_.Trim().StartsWith("http") })
    $zipFrom = $null
    foreach ($src in $folders) {
        $src = $src.Trim()
        $ver = Join-Path $src "version.txt"
        # An unreachable network path can hang for half a minute: ask in the background, give up after 4 s.
        $job = Start-Job -ScriptBlock { param($p) Test-Path -LiteralPath $p } -ArgumentList $ver
        if (-not (Wait-Job $job -Timeout 4)) { Remove-Job $job -Force; continue }
        $found = Receive-Job $job
        Remove-Job $job -Force
        if (-not $found) { continue }
        Send-SessionLogs $src
        $zipFrom = @{ "kind" = "folder"; "src" = $src; "text" = [System.IO.File]::ReadAllText($ver) }
        break
    }
    if ($null -eq $zipFrom) {
        $auth = Get-Auth $Here
        foreach ($src in $webs) {
            $src = $src.Trim().TrimEnd("/")
            try { $text = Get-WebText "$src/version.txt" $auth } catch { continue }
            $zipFrom = @{ "kind" = "web"; "src" = $src; "text" = $text; "auth" = $auth }
            break
        }
    }
    if ($null -eq $zipFrom) {
        Write-Host "Couldn't reach the family drive or the internet; playing the version you have."
        return
    }
    $remote = ($zipFrom["text"] -split "`r?`n")[0].Trim()
    if ($remote -eq $local) {
        Write-Host "Noise Floor is up to date."
        return
    }
    Write-Host ""
    Write-Host "Updating Noise Floor to: $remote"
    Write-Host "This takes about a minute. Please don't close this window."
    $tmp = Join-Path $env:TEMP "noise_floor_update"
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
    New-Item -ItemType Directory -Path $tmp | Out-Null
    $zip = Join-Path $tmp "NoiseFloor.zip"
    if ($zipFrom["kind"] -eq "folder") {
        Write-Host "  1/3 Copying the new version from the family drive..."
        Copy-Item -LiteralPath (Join-Path $zipFrom["src"] "NoiseFloor.zip") -Destination $zip
    } else {
        Write-Host "  1/3 Downloading the new version..."
        Get-WebFile ($zipFrom["src"] + "/NoiseFloor.zip") $zipFrom["auth"] $zip
    }
    $want = Get-Fingerprint $zipFrom["text"]
    if ($want -ne "" -and (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLower() -ne $want) {
        throw "the new copy didn't arrive whole (its fingerprint doesn't match)"
    }
    Write-Host "  2/3 Unpacking it..."
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $tmp)
    $new = Join-Path $tmp "NoiseFloor"
    if (-not (Test-Path -LiteralPath (Join-Path $new "game\project.godot"))) { throw "the new copy looks incomplete" }
    Write-Host "  3/3 Putting it in place..."
    if (-not (Same-Godot (Join-Path $new "godot") $Here)) { Install-Part (Join-Path $new "godot") $Here "godot" }
    Install-Part (Join-Path $new "game") $Here "game"
    foreach ($f in @("README.txt", "update_from.txt", "update.ps1", "family_cdn.txt")) {
        $from = Join-Path $new $f
        if (Test-Path -LiteralPath $from) { Copy-Item -LiteralPath $from -Destination (Join-Path $Here $f) -Force }
    }
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Updated."
} catch {
    Restore-Interrupted $Here
    Write-Host "Couldn't update ($($_.Exception.Message)); playing the version you have."
} finally {
    if ($held) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
