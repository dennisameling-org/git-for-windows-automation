Write-Output "Starting post-deployment script."

# =================================
# TOOL VERSIONS AND OTHER VARIABLES
# =================================
#
# This header is used for both Git for Windows and GitHub Actions Runner
[hashtable]$GithubHeaders = @{
    "Accept"               = "application/vnd.github.v3+json"
    "X-GitHub-Api-Version" = "2022-11-28"
}

# =================================
# Get download and hash information for the latest release of Git for Windows
# =================================
#
# This will return the latest release of Git for Windows download link, hash and the name of the outfile
# Everything will be saved in the object $GitHubGit
#
# url for Github API to get the latest release
[string]$GitHubUrl = "https://api.github.com/repos/git-for-windows/git/releases/latest"
#
# Name of the exe file that should be verified and downloaded
[string]$GithubExeName = "Git-.*-64-bit.exe"

try {
    [System.Object]$GithubRestData = Invoke-RestMethod -Uri $GitHubUrl -Method Get -Headers $GithubHeaders -TimeoutSec 10 | Select-Object -Property assets, body
    [System.Object]$GitHubAsset = $GithubRestData.assets | Where-Object { $_.name -match $GithubExeName }
    if ($GithubRestData.body -match "\b${[Regex]::Escape($GitHubAsset.name)}.*?\|.*?([a-zA-Z0-9]{64})" -eq $True) {
        [System.Object]$GitHubGit = [PSCustomObject]@{
            DownloadUrl = [string]$GitHubAsset.browser_download_url
            Hash        = [string]$Matches[1].ToUpper()
            OutFile     = "./git-for-windows-installer.exe"
        }
    }
    else {
        Write-Error "Could not find hash for $GithubExeName"
        exit 1
    }
}
catch {
    Write-Error @"
   "Message: "$($_.Exception.Message)`n
   "Error Line: "$($_.InvocationInfo.Line)`n
   "Line Number: "$($_.InvocationInfo.ScriptLineNumber)`n
"@
    exit 1
}

# =================================
# Obtain the latest GitHub Actions Runner and other GitHub Actions information
# =================================
#
# Note that the GitHub Actions Runner auto-updates itself by default, but do try to reference a relatively new version here.
#
# This will return the latest release of GitHub Actions Runner download link, hash, Tag, RunnerArch, RunnerLabels and the name of the outfile.
# Everything will be saved in the object $GitHubAction
#
# url for Github API to get the latest release of actions runner
[string]$GitHubActionUrl = "https://api.github.com/repos/actions/runner/releases/latest"

try {
    [System.Object]$GithubActionRestData = Invoke-RestMethod -Uri $GitHubActionUrl -Method Get -Headers $GithubHeaders -TimeoutSec 10 | Select-Object -Property assets, body, tag_name
    if ($GithubActionRestData.body -match "<!-- BEGIN SHA win-arm64 -->(.*)<!-- END SHA win-arm64 -->" -eq $True) {
        [string]$ActionZipName = "actions-runner-win-arm64-" + [string]$($GithubActionRestData.tag_name.Substring(1)) + ".zip"

        [System.Object]$GitHubAction = [PSCustomObject]@{
            Tag          = $GithubActionRestData.tag_name.Substring(1)
            Hash         = $Matches[1].ToUpper()
            RunnerArch   = "arm64"
            RunnerLabels = "self-hosted,Windows,ARM64"
            DownloadUrl  = $GithubActionRestData.assets | where-object { $_.name -match $ActionZipName } | Select-Object -ExpandProperty browser_download_url
            OutFile      = "$($GitHubActionsRunnerPath)\$($ActionZipName)"
        }
    }
    else {
        Write-Error "Error: Could not find hash for Github Actions Runner"
        exit 1
    }
}
catch {
    Write-Error @"
   "Message: "$($_.Exception.Message)`n
   "Error Line: "$($_.InvocationInfo.Line)`n
   "Line Number: "$($_.InvocationInfo.ScriptLineNumber)`n
"@
    exit 1
}

# =================================
# Obtain the latest pwsh binary and other pwsh information
# =================================
#
# This will install pwsh on the machine, because it's not installed by default.
# It contains a bunch of new features compared to "powershell" and is sometimes more stable as well.
#
# url for Github API to get the latest release of pwsh
#
# TODO update this to /releases/latest once 7.5.0 is out, as it adds support for arm64 MSIs
[string]$PwshUrl = "https://api.github.com/repos/PowerShell/PowerShell/releases/tags/v7.5.0-preview.2"

# Name of the MSI file that should be verified and downloaded
[string]$PwshMsiName = "PowerShell-.*-win-arm64.msi"

try {
    [System.Object]$PwshRestData = Invoke-RestMethod -Uri $PwshUrl -Method Get -Headers $GithubHeaders -TimeoutSec 10 | Select-Object -Property assets, body
    [System.Object]$PwshAsset = $PwshRestData.assets | Where-Object { $_.name -match $PwshMsiName }
    if ($PwshRestData.body -match "\b$([Regex]::Escape($PwshAsset.name))\r\n.*?([a-zA-Z0-9]{64})" -eq $True) {
        [System.Object]$GitHubPwsh = [PSCustomObject]@{
            DownloadUrl = [string]$PwshAsset.browser_download_url
            Hash        = [string]$Matches[1].ToUpper()
            OutFile     = "./pwsh-installer.msi"
        }
    }
    else {
        Write-Error "Could not find hash for $PwshMsiName"
        exit 1
    }
}
catch {
    Write-Error @"
   "Message: "$($_.Exception.Message)`n
   "Error Line: "$($_.InvocationInfo.Line)`n
   "Line Number: "$($_.InvocationInfo.ScriptLineNumber)`n
"@
    exit 1
}

# ======================
# WINDOWS DEVELOPER MODE
# ======================

# Needed for symlink support
Write-Output "Enabling Windows Developer Mode..."
Start-Process -Wait "reg" 'add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v "AllowDevelopmentWithoutDevLicense" /d "1"'
Write-Output "Enabled Windows developer mode."

# ======================
# GIT FOR WINDOWS
# ======================

Write-Output "Downloading Git for Windows..."
$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -UseBasicParsing -Uri $GitHubGit.DownloadUrl -OutFile $GitHubGit.OutFile
$ProgressPreference = 'Continue'

if ((Get-FileHash -Path $GitHubGit.OutFile -Algorithm SHA256).Hash.ToUpper() -ne $GitHubGit.Hash) {
    Write-Error "Computed checksum for $($GitHubGit.OutFile) did not match $($GitHubGit.Hash)"
    exit 1
}

Write-Output "Installing Git for Windows..."
@"
[Setup]
Lang=default
Dir=C:\Program Files\Git
Group=Git
NoIcons=0
SetupType=default
Components=gitlfs,windowsterminal
Tasks=
EditorOption=VIM
CustomEditorPath=
DefaultBranchOption= 
PathOption=CmdTools
SSHOption=OpenSSH
TortoiseOption=false
CURLOption=WinSSL
CRLFOption=CRLFAlways
BashTerminalOption=ConHost
GitPullBehaviorOption=FFOnly
UseCredentialManager=Core
PerformanceTweaksFSCache=Enabled
EnableSymlinks=Disabled
EnablePseudoConsoleSupport=Disabled
EnableFSMonitor=Disabled
"@ | Out-File -FilePath "./git-installer-config.inf"

Start-Process -Wait $GitHubGit.OutFile '/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /LOADINF="./git-installer-config.inf"'

Write-Output "Finished installing Git for Windows."
