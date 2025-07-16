# PowerShell: "iwr -useb https://raw.githubusercontent.com/sky22333/shell/main/dev/cf-setup.ps1 | iex"
# Path: "C:\ProgramData\cloudflared\"

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

function Write-ColorMessage {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet('Black','DarkBlue','DarkGreen','DarkCyan','DarkRed','DarkMagenta','DarkYellow','Gray','DarkGray','Blue','Green','Cyan','Red','Magenta','Yellow','White')]
        [string]$Color = 'White'
    )
    
    try {
        $originalColor = $null
        if ($Host.UI -and $Host.UI.RawUI -and $Host.UI.RawUI.ForegroundColor) {
            $originalColor = $Host.UI.RawUI.ForegroundColor
            $Host.UI.RawUI.ForegroundColor = $Color
        }
        
        Write-Host $Message
        
        if ($originalColor -ne $null) {
            $Host.UI.RawUI.ForegroundColor = $originalColor
        }
    } catch {

        try {
            Write-Host $Message -ForegroundColor $Color
        } catch {
            Write-Host $Message
        }
    }
}

function Download-File {
    param (
        [string]$Url,
        [string]$OutputPath
    )
    
    try {

        if ($PSVersionTable.PSVersion.Major -ge 3) {

            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
            $webClient.DownloadFile($Url, $OutputPath)
            $webClient.Dispose()
        } else {

            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($Url, $OutputPath)
            $webClient.Dispose()
        }
        return $true
    } catch {
        Write-ColorMessage "Download failed: $($_.Exception.Message)" Red
        return $false
    }
}

function Test-AdminRights {
    try {
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

Write-Host "====== CloudFlared Tunnel Setup Tool ======" -ForegroundColor Cyan
Write-Host "Initializing..." -ForegroundColor Yellow

$cloudflaredUrl = "https://github.com/cloudflare/cloudflared/releases/download/2025.6.1/cloudflared-windows-amd64.exe"
$installDir = "$env:ProgramData\cloudflared"
$cloudflaredBin = Join-Path $installDir "cloudflared.exe"
$logPath = Join-Path $installDir "cloudflared.log"
$serviceName = "CloudflaredTunnel"

$psVersion = $PSVersionTable.PSVersion.Major
Write-Host "Detected PowerShell version: $psVersion" -ForegroundColor Green

try {
    if (-not (Test-Path $installDir)) {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        Write-ColorMessage "Created installation directory: $installDir" Green
    }
} catch {
    Write-ColorMessage "Cannot create installation directory, may need administrator privileges" Red
    Write-ColorMessage "Error: $($_.Exception.Message)" Red
    exit 1
}

Write-ColorMessage "`nChecking cloudflared..." Yellow
if (Test-Path $cloudflaredBin) {
    Write-ColorMessage "cloudflared.exe already exists: $cloudflaredBin" Green
    
    try {
        $fileInfo = Get-Item $cloudflaredBin
        $fileSize = [math]::Round($fileInfo.Length / 1MB, 2)
        Write-ColorMessage "File size: ${fileSize} MB" Cyan
    } catch {
    }
} else {
    Write-ColorMessage "Starting download of cloudflared..." Cyan
    Write-ColorMessage "Download URL: $cloudflaredUrl" Gray
    Write-ColorMessage "Save location: $cloudflaredBin" Gray
    
    $downloadSuccess = Download-File -Url $cloudflaredUrl -OutputPath $cloudflaredBin
    
    if ($downloadSuccess) {
        Write-ColorMessage "Download complete!" Green
        try {
            $fileInfo = Get-Item $cloudflaredBin
            $fileSize = [math]::Round($fileInfo.Length / 1MB, 2)
            Write-ColorMessage "File size: ${fileSize} MB" Cyan
        } catch {
        }
    } else {
        Write-ColorMessage "Download failed, please check your network connection or download manually" Red
        Write-ColorMessage "Manual download URL: $cloudflaredUrl" Yellow
        exit 1
    }
}

Write-ColorMessage "`nChecking existing services..." Yellow
try {
    $serviceExists = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($serviceExists) {
        Write-ColorMessage "Detected existing cloudflared service: $serviceName" Yellow
        Write-ColorMessage "Service status: $($serviceExists.Status)" Cyan
        
        do {
            $uninstall = Read-Host "Do you want to uninstall the old service? (y/n)"
        } while ($uninstall -notin @('y','Y','n','N','yes','no'))
        
        if ($uninstall -in @('y','Y','yes')) {
            Write-ColorMessage "Uninstalling old service..." Cyan
            try {
                Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                
                $scResult = & "$env:SystemRoot\System32\sc.exe" delete $serviceName
                
                if (Test-Path $logPath) {
                    Remove-Item -Path $logPath -Force -ErrorAction SilentlyContinue
                }
                
                Write-ColorMessage "Service uninstallation complete" Green
            } catch {
                Write-ColorMessage "Error uninstalling service: $($_.Exception.Message)" Red
            }
        } else {
            Write-ColorMessage "Keeping existing service, only updating run address" Yellow
        }
    }
} catch {
    Write-ColorMessage "Error checking service: $($_.Exception.Message)" Red
}

Write-ColorMessage "`nPlease select run mode:" Yellow
Write-Host "1) Temporary run (foreground with trycloudflare domain display)"
Write-Host "2) Background run (register as system service)"

do {
    $mode = Read-Host "Please enter 1 or 2 ?"
} while ($mode -notin @('1','2'))

do {
    $localAddr = Read-Host "Please enter local service address (e.g.: 127.0.0.1:8080)"
} while ([string]::IsNullOrWhiteSpace($localAddr))

if ($mode -eq "1") {
    Write-ColorMessage "`nRunning cloudflared in temporary mode..." Cyan
    Write-ColorMessage "Starting cloudflared process..." Yellow
    Write-ColorMessage "Local service address: $localAddr" Green
    
    try {
        Write-ColorMessage "Running cloudflared directly with output to console..." Yellow
        Write-ColorMessage "Press Ctrl+C to stop the tunnel" Yellow
        
        & $cloudflaredBin tunnel --url $localAddr
        
    } catch {
        Write-ColorMessage "Error starting process: $($_.Exception.Message)" Red
    }
    
} elseif ($mode -eq "2") {

    Write-ColorMessage "`nRegistering as system service and running in background..." Cyan
    
    if (-not (Test-AdminRights)) {
        Write-ColorMessage "Warning: Administrator privileges may be required to create system services" Yellow
        Write-ColorMessage "If this fails, please run this script as administrator" Yellow
    }
    
    try {

        $serviceCommand = "`"$cloudflaredBin`" tunnel --url $localAddr --logfile `"$logPath`""
        
        $scResult = & "$env:SystemRoot\System32\sc.exe" create $serviceName binPath= $serviceCommand start= auto
        
        if ($LASTEXITCODE -eq 0) {
            Write-ColorMessage "Service created successfully" Green
        } else {
            Write-ColorMessage "Service creation may have failed, exit code: $LASTEXITCODE" Yellow
        }
        
        Start-Sleep -Seconds 2
        
        Write-ColorMessage "Starting service..." Yellow
        Start-Service -Name $serviceName -ErrorAction Stop
        Write-ColorMessage "Service started successfully, waiting for log output..." Green
        
        $domain = $null
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Seconds 1
            
            if (Test-Path $logPath) {
                try {
                    $logContent = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
                    if ($logContent -and $logContent -match 'https://[a-zA-Z0-9-]+\.trycloudflare\.com') {
                        $domain = $matches[0]
                        Write-ColorMessage "`n=== Service Running Successfully ===" Green
                        Write-ColorMessage "Public access URL: $domain" Green
                        Write-ColorMessage "Local service address: $localAddr" Cyan
                        Write-ColorMessage "Log file location: $logPath" Gray
                        break
                    }
                } catch {

                }
            }
            
            if ($i % 3 -eq 0) {
                Write-Host "." -NoNewline
            }
        }
        
        Write-Host ""
        
        if (-not $domain) {
            Write-ColorMessage "No access domain detected, please check the log manually: $logPath" Yellow
            Write-ColorMessage "The service may need more time to establish connection" Cyan
            
            try {
                $serviceStatus = Get-Service -Name $serviceName
                Write-ColorMessage "Service status: $($serviceStatus.Status)" Cyan
            } catch {
                Write-ColorMessage "Unable to get service status" Red
            }
        }
        
        Write-ColorMessage "`nService management commands:" Yellow
        Write-ColorMessage "Stop service: Stop-Service -Name $serviceName" Gray
        Write-ColorMessage "Start service: Start-Service -Name $serviceName" Gray
        Write-ColorMessage "Delete service: sc.exe delete $serviceName" Gray
        
    } catch {
        Write-ColorMessage "Failed to create or start service" Red
        Write-ColorMessage "Error: $($_.Exception.Message)" Red
        Write-ColorMessage "Please make sure you have administrator privileges" Yellow
        
        try {
            & "$env:SystemRoot\System32\sc.exe" delete $serviceName 2>$null
        } catch {
        }
    }
    
} else {
    Write-ColorMessage "Invalid option, please enter 1 or 2" Red
    exit 1
}

Write-ColorMessage "`nScript execution complete" Green
