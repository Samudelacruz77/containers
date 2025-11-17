# get-devices.ps1
# Retrieves and displays flightctl devices
Param(
    [string]$OutputFormat = "",
    [string]$OutputFile = ""
)

$ErrorActionPreference = 'Stop'
$log = 'C:\Windows\Temp\flightctl-get-devices.log'
try { Start-Transcript -Path $log -Append } catch { Write-Host "Could not start transcript: $_" }
Write-Host "[$(Get-Date -Format o)] Starting flightctl get devices"

# Check if flightctl is installed and in PATH
$flightctlPath = (Get-Command flightctl.exe -ErrorAction SilentlyContinue)
if (-not $flightctlPath) {
    Write-Host "[$(Get-Date -Format o)] ERROR: flightctl.exe not found in PATH"
    Write-Host "Please install flightctl first using install-flightctl.ps1"
    try { Stop-Transcript } catch {}
    exit 1
}

Write-Host "[$(Get-Date -Format o)] Found flightctl at: $($flightctlPath.Source)"

# Build the command
$cmdArgs = @('get', 'devices')

if (-not [string]::IsNullOrWhiteSpace($OutputFormat)) {
    $cmdArgs += @('-o', $OutputFormat)
    Write-Host "[$(Get-Date -Format o)] Output format: $OutputFormat"
}

Write-Host "[$(Get-Date -Format o)] Executing: flightctl $($cmdArgs -join ' ')"

# Execute the command
try {
    $output = & flightctl.exe @cmdArgs 2>&1
    $exitCode = $LASTEXITCODE

    Write-Host "[$(Get-Date -Format o)] Command output:"
    $output | ForEach-Object { Write-Host "  $_" }

    if ($exitCode -ne 0) {
        Write-Host "[$(Get-Date -Format o)] ERROR: flightctl get devices failed with exit code $exitCode"
        try { Stop-Transcript } catch {}
        exit $exitCode
    }

    # Save to file if requested
    if (-not [string]::IsNullOrWhiteSpace($OutputFile)) {
        try {
            $output | Out-File -FilePath $OutputFile -Encoding UTF8
            Write-Host "[$(Get-Date -Format o)] Output saved to: $OutputFile"
        } catch {
            Write-Host "[$(Get-Date -Format o)] WARNING: Could not save output to file: $_"
        }
    }

    Write-Host "[$(Get-Date -Format o)] Command completed successfully"
} catch {
    Write-Host "[$(Get-Date -Format o)] ERROR: Exception during command execution: $_"
    try { Stop-Transcript } catch {}
    throw
}

Write-Host "[$(Get-Date -Format o)] Log saved to: $log"
try { Stop-Transcript } catch {}
