#Requires -Version 5.1
<#
.SYNOPSIS
    Backup of the universia_prod database (PostgreSQL + filestore) with rotation and optional off-site copy.
.NOTES
    Ruta : <project>\scripts\backup_prod.ps1
    Usage: powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\backup_prod.ps1
    Config: reads <project>\.env (ODOO_DB_NAME, POSTGRES_USER, BACKUP_DIR, BACKUP_KEEP_DAYS, BACKUP_COPY_DIR).
    Output: <BACKUP_DIR>\universia_prod_AAAAMMDD_HHMMSS.zip (db.dump + filestore) and <BACKUP_DIR>\backup.log
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectDir = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $ProjectDir '.env'

function Read-DotEnv {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw ".env file not found: $Path" }
    $map = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
            $map[$Matches[1]] = $Matches[2].Trim('"').Trim("'")
        }
    }
    return $map
}

$cfg = Read-DotEnv -Path $EnvFile
foreach ($key in 'ODOO_DB_NAME', 'POSTGRES_USER', 'BACKUP_DIR') {
    if (-not $cfg.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($cfg[$key])) {
        throw "Missing variable $key in .env"
    }
}

$DbName = $cfg['ODOO_DB_NAME']
$PgUser = $cfg['POSTGRES_USER']
$BackupDir = $cfg['BACKUP_DIR']
$KeepDays = 14
if ($cfg.ContainsKey('BACKUP_KEEP_DAYS') -and $cfg['BACKUP_KEEP_DAYS'] -match '^\d+$') {
    $KeepDays = [int]$cfg['BACKUP_KEEP_DAYS']
}
$CopyDir = ''
if ($cfg.ContainsKey('BACKUP_COPY_DIR')) { $CopyDir = $cfg['BACKUP_COPY_DIR'] }

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
$LogFile = Join-Path $BackupDir 'backup.log'

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Level = 'INFO'
    )
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Invoke-Docker {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & docker @Arguments 2>&1
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }
    if ($code -ne 0) {
        throw ("docker {0} failed (code {1}): {2}" -f ($Arguments -join ' '), $code, (($output | Out-String).Trim()))
    }
}

function Remove-OldBackups {
    param(
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][int]$Days
    )
    $limit = (Get-Date).AddDays(-$Days)
    Get-ChildItem -LiteralPath $Folder -Filter 'universia_prod_*.zip' -File |
        Where-Object { $_.LastWriteTime -lt $limit } |
        ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force
            Write-Log "Rotation: deleted $($_.Name)"
        }
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$work = Join-Path $BackupDir "universia_prod_$stamp"
$zip = "$work.zip"
$exitCode = 0

Push-Location $ProjectDir
try {
    Write-Log "Starting backup of '$DbName'"
    New-Item -ItemType Directory -Force -Path $work | Out-Null

    # 1) PostgreSQL dump inside the container, verification and copy to host
    Invoke-Docker -Arguments @('compose', 'exec', '-T', 'db', 'pg_dump', '-U', $PgUser, '-Fc', '-f', '/tmp/db.dump', $DbName)
    Invoke-Docker -Arguments @('compose', 'exec', '-T', 'db', 'pg_restore', '-l', '/tmp/db.dump')
    Invoke-Docker -Arguments @('compose', 'cp', 'db:/tmp/db.dump', (Join-Path $work 'db.dump'))
    Invoke-Docker -Arguments @('compose', 'exec', '-T', 'db', 'rm', '-f', '/tmp/db.dump')
    Write-Log 'Database dump verified and copied'

    # 2) Filestore (attachments). If it does not exist yet, warn but do not abort.
    try {
        Invoke-Docker -Arguments @('compose', 'cp', "odoo:/var/lib/odoo/filestore/$DbName", (Join-Path $work 'filestore'))
        Write-Log 'Filestore copied'
    }
    catch {
        Write-Log "Could not copy filestore: $($_.Exception.Message)" 'WARN'
    }

    # 3) Compression
    Compress-Archive -Path (Join-Path $work '*') -DestinationPath $zip -CompressionLevel Optimal -Force
    Remove-Item -LiteralPath $work -Recurse -Force
    $sizeMb = [math]::Round((Get-Item -LiteralPath $zip).Length / 1MB, 1)
    Write-Log "Backup created: $zip ($sizeMb MB)"

    # 4) Optional off-site copy
    if (-not [string]::IsNullOrWhiteSpace($CopyDir)) {
        New-Item -ItemType Directory -Force -Path $CopyDir | Out-Null
        Copy-Item -LiteralPath $zip -Destination $CopyDir -Force
        Write-Log "Off-site copy at: $CopyDir"
        Remove-OldBackups -Folder $CopyDir -Days $KeepDays
    }

    # 5) Local rotation
    Remove-OldBackups -Folder $BackupDir -Days $KeepDays
    Write-Log 'Backup finished successfully'
}
catch {
    Write-Log $_.Exception.Message 'ERROR'
    if (Test-Path -LiteralPath $work) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
    $exitCode = 1
}
finally {
    Pop-Location
}

exit $exitCode
