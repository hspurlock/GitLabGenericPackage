#Requires -Version 5.1
<#
.SYNOPSIS
    Downloads a file from a generic package in a GitLab instance.

.DESCRIPTION
    This script downloads a specified file from a GitLab project's generic package registry.
    It uses Basic Authentication with a Personal Access Token (PAT), Deploy Token, or CI Job Token.

.PARAMETER GitLabUrl
    The GitLab instance URL (e.g., "gitlab.com").
    Default: ""

.PARAMETER ProjectIdOrPath
    The Project ID (e.g., 12345) or URL-encoded path (e.g., "mygroup/myproject").
    Default: ""

.PARAMETER PackageName
    The name of the generic package.
    Default: ""

.PARAMETER PackageVersion
    The version of the generic package.
    Default: "1..0"

.PARAMETER FileNameInPackage
    The name of the file within the package to download (e.g., "artifact.zip").
    Default: ""

.PARAMETER UserToken
    The GitLab Token (PAT, Deploy Token, CI Job Token).
    This is a mandatory parameter.

.PARAMETER UserName
    (Optional) The username for Basic Authentication.
    Default: ""

.PARAMETER OutputFile
    (Optional) The local path where the downloaded file should be saved. 
    If not specified, defaults to the FileNameInPackage in the current directory.

.PARAMETER SkipCertificateCheck
    (Optional) Switch to bypass SSL certificate validation. Recommended for environments with self-signed certificates.
    Default: $true

.PARAMETER DebugMode
    (Optional) Switch to enable verbose debug output.

.EXAMPLE
    PS> .\Download-GitLabGenericPackage.ps1 -GitLabUrl "gitlab.example.com" -ProjectIdOrPath "mygroup/myproject" -PackageName "my-package" -PackageVersion "1.2.3" -FileNameInPackage "artifact.zip" -UserToken "glpat-YourTokenHere" -UserName "gitlab_user" -OutputFile ".\downloaded_artifact.zip" -SkipCertificateCheck
    (Downloads 'artifact.zip' from 'my-package/1.2.3' on 'gitlab.example.com' for project 'mygroup/myproject', saving it as 'downloaded_artifact.zip', using 'gitlab_user' and the specified token, skipping certificate checks.)

#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$GitLabUrl,

    [Parameter(Mandatory=$true)]
    [string]$ProjectIdOrPath,

    [Parameter(Mandatory=$true)]
    [string]$PackageName,

    [Parameter(Mandatory=$true)]
    [string]$PackageVersion,

    [Parameter(Mandatory=$true)]
    [string]$FileNameInPackage,

    [Parameter(Mandatory=$true)]
    [string]$UserToken,

    [Parameter(Mandatory=$true)]
    [string]$UserName,

    [Parameter(Mandatory=$true)]
    [string]$OutputFile,

    [Parameter(Mandatory=$false)]
    [switch]$SkipCertificateCheck,

    [Parameter(Mandatory=$false)]
    [switch]$DebugMode
)

# --- Script Body ---

# Set error action preference to stop on first error for critical parts
$ErrorActionPreference = 'Stop'

# --- Helper Functions ---

function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [Parameter(Mandatory=$false)]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )

    if ($Level -eq 'DEBUG' -and !$DebugMode) {
        return
    }

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host ("[{0}] [{1}] {2}" -f $Timestamp, $Level, $Message)
}

# --- Force TLS 1.2 for secure connections ---
try {
    Write-Log -Level DEBUG -Message "Attempting to set SecurityProtocol to Tls12."
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    Write-Log -Level DEBUG -Message ("Current SecurityProtocol: {0}" -f [System.Net.ServicePointManager]::SecurityProtocol.ToString())
} catch {
    Write-Log -Level WARN -Message ("Failed to explicitly set SecurityProtocol to Tls12. Error: {0}" -f $_.Exception.Message)
    Write-Log -Level WARN -Message "The script will proceed with system default security protocols. This might lead to connection issues if the server requires TLS 1.2+ and the system default is older."
}

# --- Validate Parameters & Set Defaults ---

# OutputFile is now mandatory, default assignment logic removed.
# Ensure the output directory exists
try {
    $OutputDirectory = Split-Path -Path $OutputFile -Parent
    if ($OutputDirectory -and (-not (Test-Path -Path $OutputDirectory -PathType Container))) {
        Write-Log -Level INFO -Message "Creating output directory: $OutputDirectory"
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }
} catch {
    Write-Log -Level ERROR -Message "Failed to create output directory for '$OutputFile'. Error: $($_.Exception.Message)"
    exit 1
}

# --- Prepare Variables ---

Write-Log -Level DEBUG -Message "Input Parameters:"
Write-Log -Level DEBUG -Message "  GitLabUrl: $GitLabUrl"
Write-Log -Level DEBUG -Message "  ProjectIdOrPath: $ProjectIdOrPath"
Write-Log -Level DEBUG -Message "  PackageName: $PackageName"
Write-Log -Level DEBUG -Message "  PackageVersion: $PackageVersion"
Write-Log -Level DEBUG -Message "  FileNameInPackage: $FileNameInPackage"
Write-Log -Level DEBUG -Message "  UserName: $UserName"
Write-Log -Level DEBUG -Message "  OutputFile: $OutputFile"
Write-Log -Level DEBUG -Message "  SkipCertificateCheck: $SkipCertificateCheck"
Write-Log -Level DEBUG -Message "  DebugMode: $DebugMode"

$GitLabUrlBase = "https://$GitLabUrl"
$ProjectIdentifierEncoded = [uri]::EscapeDataString($ProjectIdOrPath)
$PackageNameEncoded = [uri]::EscapeDataString($PackageName)
$PackageVersionEncoded = [uri]::EscapeDataString($PackageVersion)
$FileNameInPackageEncoded = [uri]::EscapeDataString($FileNameInPackage)

Write-Log -Level DEBUG -Message "Derived Variables:"
Write-Log -Level DEBUG -Message "  GitLabUrlBase: $GitLabUrlBase"
Write-Log -Level DEBUG -Message "  ProjectIdentifierEncoded: $ProjectIdentifierEncoded"
Write-Log -Level DEBUG -Message "  PackageNameEncoded: $PackageNameEncoded"
Write-Log -Level DEBUG -Message "  PackageVersionEncoded: $PackageVersionEncoded"
Write-Log -Level DEBUG -Message "  FileNameInPackageEncoded: $FileNameInPackageEncoded"

# --- Construct Download URL ---
$DownloadUrl = "{0}/api/v4/projects/{1}/packages/generic/{2}/{3}/{4}" -f $GitLabUrlBase, $ProjectIdentifierEncoded, $PackageNameEncoded, $PackageVersionEncoded, $FileNameInPackageEncoded
Write-Log -Level DEBUG -Message "Download URL: $DownloadUrl"

# --- Prepare Authentication Header ---
Write-Log -Level INFO -Message "Using Basic Authentication with username: $UserName"
$BasicAuthCredentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $UserName, $UserToken)))
$Headers = @{
    "Authorization" = "Basic $BasicAuthCredentials"
}
Write-Log -Level DEBUG -Message "Authorization Header prepared."

# --- Perform Download ---
Write-Log -Level INFO -Message ("Attempting to download '{0}' from package '{1}/{2}' to '{3}'..." -f $FileNameInPackage, $PackageName, $PackageVersion, $OutputFile)

$InvokeRestMethodParams = @{
    Uri = $DownloadUrl
    Method = 'GET' # Explicitly GET, though it's default for Invoke-RestMethod
    Headers = $Headers
    OutFile = $OutputFile
}

if ($DebugMode) {
    Write-Log -Level DEBUG -Message "Invoke-RestMethod Parameters (before PS version specific adjustments): $($InvokeRestMethodParams | Out-String)"
}

$OriginalCertificateCallback = $null

try {
    if ($SkipCertificateCheck) {
        Write-Log -Level WARN -Message "SSL certificate validation is being skipped."
        if ($PSVersionTable.PSVersion.Major -lt 6) {
            Write-Log -Level DEBUG -Message "Applying ServerCertificateValidationCallback for PowerShell version < 6."
            $OriginalCertificateCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        } else {
            Write-Log -Level DEBUG -Message "Adding -SkipCertificateCheck parameter for PowerShell version >= 6."
            $InvokeRestMethodParams.SkipCertificateCheck = $true
        }
    }

    if ($PSVersionTable.PSVersion.Major -lt 6) {
        # --- PowerShell 5.1: Use System.Net.WebClient ---
        Write-Log -Level DEBUG -Message "Using System.Net.WebClient for download (PowerShell 5.1)."
        $WebClient = New-Object System.Net.WebClient
        try {
            # Add headers to WebClient (Headers are already prepared in $Headers variable)
            foreach ($HeaderKey in $Headers.Keys) {
                $WebClient.Headers.Add($HeaderKey, $Headers[$HeaderKey])
            }
            if ($DebugMode) {
                Write-Log -Level DEBUG -Message "WebClient Headers: $($WebClient.Headers | Out-String)"
                Write-Log -Level DEBUG -Message "WebClient Download URL: $DownloadUrl"
                Write-Log -Level DEBUG -Message "WebClient OutputFile: $OutputFile"
            }

            $WebClient.DownloadFile($DownloadUrl, $OutputFile) # Synchronous download
            Write-Log -Level INFO -Message "Download successful using WebClient! File saved to '$OutputFile'."
        } catch [System.Net.WebException] {
            # WebClient specific error logging
            $WebClientStatusCode = 0
            if ($_.Exception.Response) { $WebClientStatusCode = [int]$_.Exception.Response.StatusCode }
            Write-Log -Level ERROR -Message ("WebClient Download failed. HTTP Status Code: {0}" -f $WebClientStatusCode)
            Write-Log -Level ERROR -Message ("WebClient Error Message: {0}" -f $_.Exception.Message)
            if ($_.Exception.Response) {
                try {
                    $WebClientErrorStream = $_.Exception.Response.GetResponseStream()
                    $WebClientStreamReader = New-Object System.IO.StreamReader($WebClientErrorStream)
                    $WebClientErrorBody = $WebClientStreamReader.ReadToEnd()
                    $WebClientStreamReader.Close()
                    $WebClientErrorStream.Close()
                    Write-Log -Level ERROR -Message ("Server Error Response Body (WebClient): {0}" -f $WebClientErrorBody)
                } catch {
                    Write-Log -Level WARN -Message "Could not read server error response body for WebClient."
                }
            }
            throw # Re-throw to be caught by the outer catch for common cleanup and exit 1
        } finally {
            if ($WebClient) { $WebClient.Dispose() }
        }
    } else {
        # --- PowerShell 6+: Use Invoke-RestMethod ---
        Write-Log -Level DEBUG -Message "Using Invoke-RestMethod for download (PowerShell 6+)."
        # Note: $InvokeRestMethodParams.SkipCertificateCheck is set earlier (lines 194-196) if $SkipCertificateCheck is true.
        if ($DebugMode) { # General debug for PS6+ Invoke-RestMethod call
             Write-Log -Level DEBUG -Message "Invoke-RestMethod Parameters (PS 6+): $($InvokeRestMethodParams | Out-String)"
        }
        Invoke-RestMethod @InvokeRestMethodParams
        Write-Log -Level INFO -Message "Download successful using Invoke-RestMethod! File saved to '$OutputFile'."
    }

    # Common success path for both methods
    Write-Log -Level INFO -Message "Package download process complete."
    exit 0
} catch [System.Net.WebException] {
    $StatusCode = 0
    if ($_.Exception.Response) {
        $StatusCode = [int]$_.Exception.Response.StatusCode
    }
    Write-Log -Level ERROR -Message ("Download failed. HTTP Status Code: {0}" -f $StatusCode)
    Write-Log -Level ERROR -Message ("Error Message: {0}" -f $_.Exception.Message)
    if ($_.Exception.Response) {
        try {
            $ErrorStream = $_.Exception.Response.GetResponseStream()
            $StreamReader = New-Object System.IO.StreamReader($ErrorStream)
            $ErrorBody = $StreamReader.ReadToEnd()
            $StreamReader.Close()
            $ErrorStream.Close()
            Write-Log -Level ERROR -Message ("Server Error Response Body: {0}" -f $ErrorBody)
        } catch {
            Write-Log -Level WARN -Message "Could not read server error response body."
        }
    }
    # If download failed, the OutFile might be empty or contain partial/error data. Consider removing it.
    if (Test-Path -Path $OutputFile -PathType Leaf) {
        Write-Log -Level WARN -Message "Removing potentially incomplete/error file: $OutputFile"
        Remove-Item -Path $OutputFile -Force -ErrorAction SilentlyContinue
    }
    Write-Log -Level ERROR -Message "Package download process failed."
    exit 1
} catch {
    Write-Log -Level ERROR -Message "An unexpected error occurred during download:"
    Write-Log -Level ERROR -Message $_.Exception.ToString()
    if (Test-Path -Path $OutputFile -PathType Leaf) {
        Write-Log -Level WARN -Message "Removing potentially incomplete/error file due to unexpected error: $OutputFile"
        Remove-Item -Path $OutputFile -Force -ErrorAction SilentlyContinue
    }
    Write-Log -Level ERROR -Message "Package download process failed."
    exit 1
} finally {
    if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -lt 6 -and $null -ne $OriginalCertificateCallback) {
        Write-Log -Level DEBUG -Message "Restoring original ServerCertificateValidationCallback."
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $OriginalCertificateCallback
    }
}
