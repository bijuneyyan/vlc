# ==============================================================================
# Safety Filter (.sft) — Automated One-Click Installer for Windows
# Supports:
#   1. PowerShell one-line install:
#      irm https://raw.githubusercontent.com/bijuneyyan/vlc/main/install.ps1 | iex
#   2. Local execution / double-clicking Install.bat
# ==============================================================================

$ErrorActionPreference = "Stop"

$RepoRawUrl = "https://raw.githubusercontent.com/bijuneyyan/vlc/main"

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "       🎬 VLC Safety Filter (.sft) Installer (Windows)" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan

$AppData = [Environment]::GetFolderPath("ApplicationData")
$VlcDir = Join-Path $AppData "vlc"
$ExtDir = Join-Path $VlcDir "lua\extensions"
$IntfDir = Join-Path $VlcDir "lua\intf"
$VlcrcFile = Join-Path $VlcDir "vlcrc"

# 1. Create target directories
New-Item -ItemType Directory -Force -Path $ExtDir | Out-Null
New-Item -ItemType Directory -Force -Path $IntfDir | Out-Null

# 2. Install sft_filter.lua (GUI Extension)
$ExtTarget = Join-Path $ExtDir "sft_filter.lua"
if (Test-Path "lua\extensions\sft_filter.lua") {
    Copy-Item "lua\extensions\sft_filter.lua" -Destination $ExtTarget -Force
} else {
    Write-Host "⬇️  Downloading sft_filter.lua from GitHub..." -ForegroundColor Yellow
    Invoke-RestMethod "$RepoRawUrl/lua/extensions/sft_filter.lua" -OutFile $ExtTarget
}
Write-Host "✅ Installed GUI Extension: $ExtTarget" -ForegroundColor Green

# 3. Install sft_looper.lua (Background Looper)
$IntfTarget = Join-Path $IntfDir "sft_looper.lua"
if (Test-Path "lua\intf\sft_looper.lua") {
    Copy-Item "lua\intf\sft_looper.lua" -Destination $IntfTarget -Force
} else {
    Write-Host "⬇️  Downloading sft_looper.lua from GitHub..." -ForegroundColor Yellow
    Invoke-RestMethod "$RepoRawUrl/lua/intf/sft_looper.lua" -OutFile $IntfTarget
}
Write-Host "✅ Installed Background Looper: $IntfTarget" -ForegroundColor Green

# 4. Auto-configure VLC Preferences (vlcrc)
Write-Host "⚙️  Auto-configuring VLC preferences..." -ForegroundColor Yellow

if (-not (Test-Path $VlcrcFile)) {
    $InitialConfig = @"
[main]
extraintf=luaintf
lua-intf=sft_looper
"@
    Set-Content -Path $VlcrcFile -Value $InitialConfig -Encoding UTF8
} else {
    $Lines = Get-Content -Path $VlcrcFile

    # Configure extraintf
    $HasExtraIntf = $false
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^extraintf=(.*)$') {
            $HasExtraIntf = $true
            if ($Lines[$i] -notmatch 'luaintf') {
                $Lines[$i] = "$($Lines[$i]):luaintf"
            }
            break
        } elseif ($Lines[$i] -match '^#extraintf=') {
            $HasExtraIntf = $true
            $Lines[$i] = "extraintf=luaintf"
            break
        }
    }
    if (-not $HasExtraIntf) {
        $Lines += "extraintf=luaintf"
    }

    # Configure lua-intf
    $HasLuaIntf = $false
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^lua-intf=(.*)$') {
            $HasLuaIntf = $true
            if ($Lines[$i] -notmatch 'sft_looper') {
                $Lines[$i] = "lua-intf=sft_looper"
            }
            break
        } elseif ($Lines[$i] -match '^#lua-intf=') {
            $HasLuaIntf = $true
            $Lines[$i] = "lua-intf=sft_looper"
            break
        }
    }
    if (-not $HasLuaIntf) {
        $Lines += "lua-intf=sft_looper"
    }

    Set-Content -Path $VlcrcFile -Value $Lines -Encoding UTF8
}

Write-Host "✅ Auto-configured VLC configuration ($VlcrcFile)" -ForegroundColor Green

# 5. Success Message
Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "  🎉 Installation Complete & Ready to Use!" -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "  1. Open (or restart) VLC Media Player."
Write-Host "  2. Play any video with a matching .sft file (e.g. movie.sft next to movie.mp4)."
Write-Host "  3. Open VLC menu -> View -> Safety Filter (.sft) to edit filters."
Write-Host "=======================================================" -ForegroundColor Cyan

# Windows popup alert
try {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show("Safety Filter (.sft) has been installed and configured successfully for VLC!", "VLC Safety Filter", "OK", "Information") | Out-Null
} catch {}
