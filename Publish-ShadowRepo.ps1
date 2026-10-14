<#
.SYNOPSIS
    Automated Shadow Repository Publisher & Sanitizer.

.DESCRIPTION
    Safely synchronizes your work between your Private Master repository
    and your Public Shadow repository (showcase layer).
    
    Workflow:
    1. Commits and pushes ALL work (including internal proprietary logic) to your Private Master repo.
    2. Builds a clean, sanitized public snapshot excluding 'internal/', '.env', and proprietary blueprints.
    3. Pushes the sanitized showcase directly to your Public Shadow repo.

.EXAMPLE
    .\Publish-ShadowRepo.ps1 -CommitMessage "Refactored UI and updated core heuristics"
#>

param (
    [Parameter(Mandatory = $false)]
    [string]$CommitMessage = "Update public showcase build",

    [Parameter(Mandatory = $false)]
    [string]$PrivateRemote = "origin",

    [Parameter(Mandatory = $false)]
    [string]$ShadowRemote = "public-shadow"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "`n==========================================================" -ForegroundColor Magenta
Write-Host " 🛡️  SHADOW REPOSITORY SYNCHRONIZATION ENGINE" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Magenta

# 1. Verify remotes
$Remotes = git remote
if ($Remotes -notcontains $PrivateRemote) {
    Write-Host "[!] Error: Private remote '$PrivateRemote' not found." -ForegroundColor Red
    exit 1
}
if ($Remotes -notcontains $ShadowRemote) {
    Write-Host "[!] Error: Shadow remote '$ShadowRemote' not found." -ForegroundColor Red
    exit 1
}

# 2. Stage and commit in private master
Write-Host "`n[1/3] Pushing complete work to PRIVATE MASTER repository..." -ForegroundColor DarkGray
git add -A
$Status = git status --porcelain
if ($Status) {
    git commit -m $CommitMessage
} else {
    Write-Host "  -> No uncommitted local changes." -ForegroundColor DarkGray
}

git push $PrivateRemote main
if ($LASTEXITCODE -ne 0) {
    Write-Host "[!] Failed to push to private master. Aborting public sync for safety." -ForegroundColor Red
    exit 1
}
Write-Host "  -> [+] Private Master updated successfully." -ForegroundColor Green

# 3. Synchronize to public shadow repo using an orphan/sanitized shadow branch
Write-Host "`n[2/3] Building sanitized PUBLIC SHADOW branch..." -ForegroundColor DarkGray

$CurrentBranch = (git branch --show-current).Trim()
$ShadowBranch = "public-release"

# Check if shadow branch already exists locally
$BranchExists = git branch --list $ShadowBranch
if ($BranchExists) {
    git branch -D $ShadowBranch | Out-Null
}

# Create a clean branch from main
git checkout -b $ShadowBranch | Out-Null

# Remove internal proprietary directories from the shadow branch
$PrivateFolders = @("internal", "private", ".secrets", "blueprints")
foreach ($folder in $PrivateFolders) {
    if (Test-Path $folder) {
        git rm -r -f --ignore-unmatch $folder | Out-Null
        Write-Host "  -> Excluded proprietary directory: $folder/" -ForegroundColor Yellow
    }
}

# Ensure .gitignore in shadow branch hides internal files
git add -A
git commit -m "$CommitMessage (Sanitized Showcase Build)" --quiet

# 4. Push sanitized branch to Public Shadow remote
Write-Host "`n[3/3] Publishing to PUBLIC SHADOW repository..." -ForegroundColor DarkGray
git push $ShadowRemote ${ShadowBranch}:main --force

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n==========================================================" -ForegroundColor Green
    Write-Host " ✅ SUCCESS: Public Shadow Repo updated safely!" -ForegroundColor Green
    Write-Host "    - Private Master (Full code): https://github.com/wwwamanmishra213-coder/ollama-powershell-assistant-private" -ForegroundColor Cyan
    Write-Host "    - Public Shadow (Showcase):   https://github.com/wwwamanmishra213-coder/ollama-powershell-assistant" -ForegroundColor Cyan
    Write-Host "==========================================================`n" -ForegroundColor Green
} else {
    Write-Host "[!] Failed to push to public shadow remote." -ForegroundColor Red
}

# Switch back to working branch
git checkout $CurrentBranch --quiet
git branch -D $ShadowBranch --quiet | Out-Null
