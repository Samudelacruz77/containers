# Requires administrative privileges
param(
    [string]$ZipPath = "$PSScriptRoot\flightctl.zip"
)

function Assert-Admin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "This script must be run as Administrator."
        exit 1
    }
}

function Get-ExistingZipPath {
    param([string[]]$Candidates)
    foreach ($p in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if (Test-Path -LiteralPath $p) { return (Resolve-Path -LiteralPath $p).Path }
    }
    return $null
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Broadcast-EnvironmentChange {
    $signature = @"
using System;
using System.Runtime.InteropServices;
public static class EnvRefresh {
  [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
  public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
}
"@
    Add-Type -TypeDefinition $signature -ErrorAction SilentlyContinue | Out-Null
    $HWND_BROADCAST = [IntPtr]0xffff
    $WM_SETTINGCHANGE = 0x1A
    $SMTO_ABORTIFHUNG = 0x0002
    $result = [UIntPtr]::Zero
    [void][EnvRefresh]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero, "Environment", $SMTO_ABORTIFHUNG, 5000, [ref]$result)
}

Assert-Admin

$candidatePaths = @(
    $ZipPath,
    "C:\Users\vagrant\binary\flightctl.zip",
    "C:\Users\vagrant\flightctl.zip",
    "C:\host_home\flightctl.zip",
    "C:\vagrant\flightctl.zip",
    "$env:USERPROFILE\Downloads\flightctl.zip"
)

$resolvedZip = Get-ExistingZipPath -Candidates $candidatePaths
if (-not $resolvedZip) {
    Write-Error "flightctl.zip not found. Checked: `n$($candidatePaths -join "`n")"
    exit 1
}

$installDir = "C:\flightctl"
Ensure-Directory -Path $installDir

$tempDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("flightctl-install-" + [Guid]::NewGuid())
Ensure-Directory -Path $tempDir

Write-Host "Expanding archive from: $resolvedZip"
Expand-Archive -Path $resolvedZip -DestinationPath $tempDir -Force

$exe = Get-ChildItem -Path $tempDir -Recurse -File -Include "flightctl*.exe" | Select-Object -First 1
if (-not $exe) {
    Write-Error "No flightctl executable found in archive. Looked for 'flightctl*.exe'."
    exit 1
}

$targetExe = Join-Path $installDir "flightctl.exe"
Copy-Item -LiteralPath $exe.FullName -Destination $targetExe -Force

# Ensure install dir is on Machine PATH
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$pathEntries = ($machinePath -split ';') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
if (-not ($pathEntries | ForEach-Object { $_.TrimEnd('\') } | Where-Object { $_ -ieq $installDir.TrimEnd('\') })) {
    $newPath = ($pathEntries + $installDir) -join ';'
    [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
    Broadcast-EnvironmentChange
    Write-Host "Added '$installDir' to system PATH."
} else {
    Write-Host "'$installDir' is already on system PATH."
}

Write-Host "flightctl installed to: $targetExe"
Write-Host "Open a new terminal or logon session to pick up PATH changes if needed."


