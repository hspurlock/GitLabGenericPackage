#Requires -Version 5.1
<#
.SYNOPSIS
    Uploads a file as a generic package to a GitLab instance.

.DESCRIPTION
    This script uploads a specified file to a GitLab project's generic package registry.
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
    Default: ""

.PARAMETER FileToUpload
    The full path to the local file to upload.
    Default: ""

.PARAMETER UserToken
    The GitLab Token (PAT, Deploy Token, CI Job Token).
    This is a mandatory parameter.

.PARAMETER UserName
    (Optional) The username for Basic Authentication.
    Default: ""

.PARAMETER SkipCertificateCheck
    (Optional) Switch to bypass SSL certificate validation. Recommended for environments with self-signed certificates.
    Default: $true

.PARAMETER DebugMode
    (Optional) Switch to enable verbose debug output.

.EXAMPLE
    PS> .\Upload-GitLabGenericPackage.ps1 -GitLabUrl "gitlab.example.com" -ProjectIdOrPath "mygroup/myproject" -PackageName "my-package" -PackageVersion "1.2.3" -FileToUpload ".\dist\artifact.zip" -UserToken "glpat-YourTokenHere" -UserName "gitlab_user" -SkipCertificateCheck
    (Uploads '.\dist\artifact.zip' to 'my-package/1.2.3' on 'gitlab.example.com' for project 'mygroup/myproject', using 'gitlab_user' and the specified token, skipping certificate checks.)

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
    [string]$FileToUpload,

    [Parameter(Mandatory=$true)]
    [string]$UserToken,

    [Parameter(Mandatory=$true)]
    [string]$UserName,

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

# --- Validate Parameters ---

if (-not (Test-Path -Path $FileToUpload -PathType Leaf)) {
    Write-Log -Level ERROR -Message "File to upload not found or is not a file: '$FileToUpload'"
    exit 1
}

# --- Prepare Variables ---

Write-Log -Level DEBUG -Message "Input Parameters:"
Write-Log -Level DEBUG -Message "  GitLabUrl: $GitLabUrl"
Write-Log -Level DEBUG -Message "  ProjectIdOrPath: $ProjectIdOrPath"
Write-Log -Level DEBUG -Message "  PackageName: $PackageName"
Write-Log -Level DEBUG -Message "  PackageVersion: $PackageVersion"
Write-Log -Level DEBUG -Message "  FileToUpload: $FileToUpload"
Write-Log -Level DEBUG -Message "  UserName: $UserName"
Write-Log -Level DEBUG -Message "  SkipCertificateCheck: $SkipCertificateCheck"
Write-Log -Level DEBUG -Message "  DebugMode: $DebugMode"


$GitLabUrlBase = "https://$GitLabUrl"

# PowerShell's [uri]::EscapeDataString is more aligned with RFC3986 for path segments
# HttpUtility.UrlEncode is more for query string parameters.
$ProjectIdentifierEncoded = [uri]::EscapeDataString($ProjectIdOrPath)
$PackageNameEncoded = [uri]::EscapeDataString($PackageName)
$PackageVersionEncoded = [uri]::EscapeDataString($PackageVersion)
$FileNameForUrl = [uri]::EscapeDataString((Get-Item -Path $FileToUpload).Name)

Write-Log -Level DEBUG -Message "Derived Variables:"
Write-Log -Level DEBUG -Message "  GitLabUrlBase: $GitLabUrlBase"
Write-Log -Level DEBUG -Message "  ProjectIdentifierEncoded: $ProjectIdentifierEncoded"
Write-Log -Level DEBUG -Message "  PackageNameEncoded: $PackageNameEncoded"
Write-Log -Level DEBUG -Message "  PackageVersionEncoded: $PackageVersionEncoded"
Write-Log -Level DEBUG -Message "  FileNameForUrl: $FileNameForUrl"

# --- Construct Upload URL ---
$UploadUrl = "{0}/api/v4/projects/{1}/packages/generic/{2}/{3}/{4}" -f $GitLabUrlBase, $ProjectIdentifierEncoded, $PackageNameEncoded, $PackageVersionEncoded, $FileNameForUrl
Write-Log -Level DEBUG -Message "Upload URL: $UploadUrl"

# --- Prepare Authentication Header ---
Write-Log -Level INFO -Message "Using Basic Authentication with username: $UserName"
$BasicAuthCredentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $UserName, $UserToken)))
$Headers = @{
    "Authorization" = "Basic $BasicAuthCredentials"
}
Write-Log -Level DEBUG -Message "Authorization Header prepared."

# --- Perform Upload ---
Write-Log -Level INFO -Message ("Attempting to upload '{0}' to package '{1}/{2}'..." -f $FileToUpload, $PackageName, $PackageVersion)

$InvokeRestMethodParams = @{
    Uri = $UploadUrl
    Method = 'PUT'
    Headers = $Headers
    InFile = $FileToUpload
    ContentType = 'application/octet-stream' # Standard for binary files
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

    if ($DebugMode -and $SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
        Write-Log -Level DEBUG -Message "Invoke-RestMethod Parameters (after PS 6+ SkipCertificateCheck addition): $($InvokeRestMethodParams | Out-String)"
    }

    $Response = Invoke-RestMethod @InvokeRestMethodParams
    Write-Log -Level INFO -Message "Upload successful!"
    Write-Log -Level DEBUG -Message "Server Response: $($Response | Out-String)"
    Write-Log -Level INFO -Message "Package upload process complete."
    exit 0
} catch [System.Net.WebException] {
    $StatusCode = 0
    if ($_.Exception.Response) {
        $StatusCode = [int]$_.Exception.Response.StatusCode
    }
    Write-Log -Level ERROR -Message ("Upload failed. HTTP Status Code: {0}" -f $StatusCode)
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
    Write-Log -Level ERROR -Message "Package upload process failed."
    exit 1
} catch {
    Write-Log -Level ERROR -Message "An unexpected error occurred during upload:"
    Write-Log -Level ERROR -Message $_.Exception.ToString()
    Write-Log -Level ERROR -Message "Package upload process failed."
    exit 1
} finally {
    if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -lt 6 -and $null -ne $OriginalCertificateCallback) {
        Write-Log -Level DEBUG -Message "Restoring original ServerCertificateValidationCallback."
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $OriginalCertificateCallback
    }
}
