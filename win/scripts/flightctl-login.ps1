# flightctl-login.ps1
# Logs into flightctl service using credentials and endpoint from environment variables
Param(
    [string]$Endpoint = $env:FLIGHTCTL_ENDPOINT,
    [string]$Username = $env:FLIGHTCTL_USERNAME,
    [string]$Password = $env:FLIGHTCTL_PASSWORD,
    [string]$Token = $env:FLIGHTCTL_TOKEN,
    [switch]$UseToken = $false,
    [switch]$Insecure = $false,
    [switch]$NoAuth = $false
)

$ErrorActionPreference = 'Stop'
$log = 'C:\Windows\Temp\flightctl-login.log'
try { Start-Transcript -Path $log -Append } catch { Write-Host "Could not start transcript: $_" }
Write-Host "[$(Get-Date -Format o)] Starting flightctl login process"

# Read environment variables for flags (convert string to boolean)
if ($env:FLIGHTCTL_INSECURE -eq 'true' -or $env:FLIGHTCTL_INSECURE -eq '1') {
    $Insecure = $true
}
if ($env:FLIGHTCTL_NO_AUTH -eq 'true' -or $env:FLIGHTCTL_NO_AUTH -eq '1') {
    $NoAuth = $true
}
if ($env:FLIGHTCTL_USE_TOKEN -eq 'true' -or $env:FLIGHTCTL_USE_TOKEN -eq '1') {
    $UseToken = $true
}

# Validate required parameters
if ([string]::IsNullOrWhiteSpace($Endpoint)) {
    Write-Host "[$(Get-Date -Format o)] ERROR: FLIGHTCTL_ENDPOINT environment variable is not set"
    Write-Host "Usage: Set environment variable FLIGHTCTL_ENDPOINT or pass -Endpoint parameter"
    Write-Host "Example: `$env:FLIGHTCTL_ENDPOINT='https://flightctl.example.com'"
    Write-Host "         .\flightctl-login.ps1"
    try { Stop-Transcript } catch {}
    exit 1
}

Write-Host "[$(Get-Date -Format o)] Endpoint: $Endpoint"

# Check if flightctl is installed and in PATH
$flightctlPath = (Get-Command flightctl.exe -ErrorAction SilentlyContinue)
if (-not $flightctlPath) {
    Write-Host "[$(Get-Date -Format o)] ERROR: flightctl.exe not found in PATH"
    Write-Host "Please install flightctl first using install-flightctl.ps1"
    try { Stop-Transcript } catch {}
    exit 1
}

Write-Host "[$(Get-Date -Format o)] Found flightctl at: $($flightctlPath.Source)"

# Determine authentication method
if ($NoAuth) {
    Write-Host "[$(Get-Date -Format o)] Using no authentication (local deployment mode)"

    $loginArgs = @($Endpoint)
    if ($Insecure) {
        $loginArgs = @('-k') + $loginArgs
        Write-Host "[$(Get-Date -Format o)] Insecure mode enabled (skipping TLS verification)"
    }

    Write-Host "[$(Get-Date -Format o)] Executing: flightctl login $($loginArgs -join ' ')"
    try {
        $output = & flightctl.exe login @loginArgs 2>&1
        $exitCode = $LASTEXITCODE

        Write-Host "[$(Get-Date -Format o)] Command output:"
        $output | ForEach-Object { Write-Host "  $_" }

        if ($exitCode -ne 0) {
            Write-Host "[$(Get-Date -Format o)] ERROR: flightctl login failed with exit code $exitCode"
            try { Stop-Transcript } catch {}
            exit $exitCode
        }

        Write-Host "[$(Get-Date -Format o)] Login successful"
    } catch {
        Write-Host "[$(Get-Date -Format o)] ERROR: Exception during login: $_"
        try { Stop-Transcript } catch {}
        throw
    }
} elseif ($UseToken -or -not [string]::IsNullOrWhiteSpace($Token)) {
    Write-Host "[$(Get-Date -Format o)] Using token-based authentication"

    if ([string]::IsNullOrWhiteSpace($Token)) {
        Write-Host "[$(Get-Date -Format o)] ERROR: FLIGHTCTL_TOKEN environment variable is not set"
        Write-Host "Usage: Set environment variable FLIGHTCTL_TOKEN or pass -Token parameter"
        try { Stop-Transcript } catch {}
        exit 1
    }

    # Token authentication
    $loginArgs = @($Endpoint, "--token=$Token")
    if ($Insecure) {
        $loginArgs = @('-k') + $loginArgs
        Write-Host "[$(Get-Date -Format o)] Insecure mode enabled (skipping TLS verification)"
    }

    Write-Host "[$(Get-Date -Format o)] Executing: flightctl login $(if($Insecure){'-k '})$Endpoint --token=****"
    try {
        $output = & flightctl.exe login @loginArgs 2>&1
        $exitCode = $LASTEXITCODE

        Write-Host "[$(Get-Date -Format o)] Command output:"
        $output | ForEach-Object { Write-Host "  $_" }

        if ($exitCode -ne 0) {
            Write-Host "[$(Get-Date -Format o)] ERROR: flightctl login failed with exit code $exitCode"
            try { Stop-Transcript } catch {}
            exit $exitCode
        }

        Write-Host "[$(Get-Date -Format o)] Login successful"
    } catch {
        Write-Host "[$(Get-Date -Format o)] ERROR: Exception during login: $_"
        try { Stop-Transcript } catch {}
        throw
    }
} else {
    Write-Host "[$(Get-Date -Format o)] Using username/password authentication"

    if ([string]::IsNullOrWhiteSpace($Username)) {
        Write-Host "[$(Get-Date -Format o)] ERROR: FLIGHTCTL_USERNAME environment variable is not set"
        Write-Host "Usage: Set environment variable FLIGHTCTL_USERNAME or pass -Username parameter"
        try { Stop-Transcript } catch {}
        exit 1
    }

    if ([string]::IsNullOrWhiteSpace($Password)) {
        Write-Host "[$(Get-Date -Format o)] ERROR: FLIGHTCTL_PASSWORD environment variable is not set"
        Write-Host "Usage: Set environment variable FLIGHTCTL_PASSWORD or pass -Password parameter"
        try { Stop-Transcript } catch {}
        exit 1
    }

    Write-Host "[$(Get-Date -Format o)] Username: $Username"

    $loginArgs = @($Endpoint, '-u', $Username, '-p', $Password)
    if ($Insecure) {
        $loginArgs = @('-k') + $loginArgs
        Write-Host "[$(Get-Date -Format o)] Insecure mode enabled (skipping TLS verification)"
    }

    Write-Host "[$(Get-Date -Format o)] Executing: flightctl login $(if($Insecure){'-k '})$Endpoint -u $Username -p ****"

    try {
        $output = & flightctl.exe login @loginArgs 2>&1
        $exitCode = $LASTEXITCODE

        Write-Host "[$(Get-Date -Format o)] Command output:"
        $output | ForEach-Object { Write-Host "  $_" }

        if ($exitCode -ne 0) {
            Write-Host "[$(Get-Date -Format o)] ERROR: flightctl login failed with exit code $exitCode"
            try { Stop-Transcript } catch {}
            exit $exitCode
        }

        Write-Host "[$(Get-Date -Format o)] Login successful"
    } catch {
        Write-Host "[$(Get-Date -Format o)] ERROR: Exception during login: $_"
        try { Stop-Transcript } catch {}
        throw
    }
}

# Verify login by checking current context
Write-Host "[$(Get-Date -Format o)] Verifying login status..."
try {
    $contextOutput = & flightctl.exe config current-context 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        Write-Host "[$(Get-Date -Format o)] Current context:"
        $contextOutput | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Host "[$(Get-Date -Format o)] WARNING: Could not verify current context (exit code: $exitCode)"
    }
} catch {
    Write-Host "[$(Get-Date -Format o)] WARNING: Could not verify current context: $_"
}

Write-Host "[$(Get-Date -Format o)] flightctl login completed successfully"
Write-Host "[$(Get-Date -Format o)] Log saved to: $log"
try { Stop-Transcript } catch {}
