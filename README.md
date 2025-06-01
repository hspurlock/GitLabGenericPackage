# GitLab Generic Package PowerShell Scripts

This document describes two PowerShell scripts: `Upload-GitLabGenericPackage.ps1` for uploading files and `Download-GitLabGenericPackage.ps1` for downloading files from a GitLab project's generic package registry. Both scripts use Basic Authentication with a Personal Access Token (PAT), Deploy Token, or CI Job Token.

## Prerequisites

*   PowerShell Version 5.1 or higher.
    *   The script is designed to be compatible with Windows PowerShell 5.1 and modern PowerShell (6+).
*   A GitLab Personal Access Token (PAT), Deploy Token, or CI Job Token with the necessary scopes (`api` or `read_api` and `write_repository` or `read_repository` for generic packages, though `api` is simplest for PATs).

## PowerShell Execution Policy

By default, PowerShell's execution policy might prevent you from running local scripts. If you encounter an error like "File ... cannot be loaded because running scripts is disabled on this system," you'll need to adjust the execution policy.

To allow scripts to run for the **current PowerShell session only** (recommended for safety and testing), open PowerShell and run:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope Process
```

For a more **persistent change for the current user** (use with caution):

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

After setting the policy, you should be able to run the script.

## Common Prerequisites

*   PowerShell Version 5.1 or higher.
*   A GitLab Personal Access Token (PAT), Deploy Token, or CI Job Token with the necessary scopes (e.g., `api` or `read_api` and `write_repository` / `read_repository`).

## Common PowerShell Execution Policy

By default, PowerShell's execution policy might prevent you from running local scripts. If you encounter an error like "File ... cannot be loaded because running scripts is disabled on this system," you'll need to adjust the execution policy.

To allow scripts to run for the **current PowerShell session only** (recommended for safety and testing), open PowerShell and run:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope Process
```

For a more **persistent change for the current user** (use with caution):

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

After setting the policy, you should be able to run the scripts.

## `Upload-GitLabGenericPackage.ps1`

This script uploads a specified file to a GitLab project's generic package registry.

### Script Parameters

All parameters (except `-DebugMode`) are **mandatory**.

The script accepts the following parameters:

*   `-GitLabUrl` (string, **mandatory**)
    *   Description: The GitLab instance URL (e.g., `"gitlab.example.com"`).
*   `-ProjectIdOrPath` (string, **mandatory**)
    *   Description: The Project ID (e.g., `12345`) or URL-encoded path (e.g., `"mygroup/myproject"`).
*   `-PackageName` (string, **mandatory**)
    *   Description: The name of the generic package.
*   `-PackageVersion` (string, **mandatory**)
    *   Description: The version of the generic package.
*   `-FileToUpload` (string, **mandatory**)
    *   Description: The full path to the local file to upload.
*   `-UserToken` (string, **mandatory**)
    *   Description: The GitLab Token (PAT, Deploy Token, CI Job Token).
*   `-UserName` (string, **mandatory**)
    *   Description: The username for Basic Authentication (e.g., `"oauth2"` for PATs).
*   `-SkipCertificateCheck` (switch, optional)
    *   Description: If present, bypasses SSL certificate validation. If omitted, certificate validation will be performed.
*   `-DebugMode` (switch, optional)
    *   Description: If present, enables verbose debug output to the console.

## How to Run

1.  Open PowerShell.
2.  Navigate to the directory where `Upload-GitLabGenericPackage.ps1` is located.
3.  Ensure your execution policy is set correctly (see above).
4.  Run the script with the required parameters.

### Examples

**1. Uploading `myartifact.zip` to a specific GitLab project:**

```powershell
.\Upload-GitLabGenericPackage.ps1 -GitLabUrl "gitlab.example.com" -ProjectIdOrPath "mygroup/myproject" -PackageName "my-app" -PackageVersion "1.0.5" -FileToUpload ".\build\myartifact.zip" -UserToken "glpat-YourGitLabTokenHere" -UserName "oauth2" -SkipCertificateCheck
```

**2. Uploading `data.bin` with debug output (certificate validation will be performed if `-SkipCertificateCheck` is omitted):**

```powershell
.\Upload-GitLabGenericPackage.ps1 -GitLabUrl "repo.internal.net" -ProjectIdOrPath "12345" -PackageName "dataset" -PackageVersion "2024-q1" -FileToUpload "D:\data\archive\data.bin" -UserToken "glpat-AnotherToken" -UserName "service_account" -DebugMode
```

### Error Handling

The script includes error handling for common issues such as file not found, network errors, and HTTP error responses from GitLab. Verbose error messages will be printed. If `-DebugMode` is enabled, more detailed diagnostic information will be shown.

## `Download-GitLabGenericPackage.ps1`

This script downloads a specified file from a GitLab project's generic package registry.

### Script Parameters

All parameters (except `-DebugMode`) are **mandatory**.

*   `-GitLabUrl` (string, **mandatory**)
    *   Description: The GitLab instance URL (e.g., `"gitlab.example.com"`).
*   `-ProjectIdOrPath` (string, **mandatory**)
    *   Description: The Project ID (e.g., `12345`) or URL-encoded path (e.g., `"mygroup/myproject"`).
*   `-PackageName` (string, **mandatory**)
    *   Description: The name of the generic package.
*   `-PackageVersion` (string, **mandatory**)
    *   Description: The version of the generic package.
*   `-FileNameInPackage` (string, **mandatory**)
    *   Description: The name of the file within the package to download (e.g., `"artifact.zip"`).
*   `-UserToken` (string, **mandatory**)
    *   Description: The GitLab Token (PAT, Deploy Token, CI Job Token).
*   `-UserName` (string, **mandatory**)
    *   Description: The username for Basic Authentication (e.g., `"oauth2"` for PATs).
*   `-OutputFile` (string, **mandatory**)
    *   Description: The local path where the downloaded file should be saved.
*   `-SkipCertificateCheck` (switch, optional)
    *   Description: If present, bypasses SSL certificate validation. If omitted, certificate validation will be performed.
*   `-DebugMode` (switch, optional)
    *   Description: If present, enables verbose debug output to the console.

### How to Run

1.  Open PowerShell.
2.  Navigate to the directory where `Download-GitLabGenericPackage.ps1` is located.
3.  Ensure your execution policy is set correctly.
4.  Run the script with all required parameters.

### Examples

**1. Downloading `myartifact.zip` from a specific GitLab project:**

```powershell
.\Download-GitLabGenericPackage.ps1 -GitLabUrl "gitlab.example.com" -ProjectIdOrPath "mygroup/myproject" -PackageName "my-app" -PackageVersion "1.0.5" -FileNameInPackage "myartifact.zip" -UserToken "glpat-YourGitLabTokenHere" -UserName "oauth2" -OutputFile ".\downloads\myartifact.zip" -SkipCertificateCheck
```

**2. Downloading `config.json` with debug output (certificate validation will be performed if `-SkipCertificateCheck` is omitted):**

```powershell
.\Download-GitLabGenericPackage.ps1 -GitLabUrl "repo.internal.net" -ProjectIdOrPath "12345" -PackageName "app-config" -PackageVersion "v2.1" -FileNameInPackage "config.json" -UserToken "glpat-AnotherToken" -UserName "service_account" -OutputFile "C:\configs\current_config.json" -DebugMode
```

### Error Handling

The script includes error handling for common issues such as:
*   File not found.
*   Network errors during upload.
*   HTTP error responses from GitLab (e.g., 401 Unauthorized, 404 Not Found).

Verbose error messages, including the server's response body (if available), will be printed to the console if an error occurs. If `-DebugMode` is enabled, more detailed diagnostic information will be shown.
