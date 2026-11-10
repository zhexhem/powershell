
#Requires -Version 5.1

<#
.SYNOPSIS
    Creates the PowerShell Autocomplete Engine project.

.DESCRIPTION
    Generates directories, modules, completion providers,
    installation scripts and a PowerShell profile.

.PARAMETER Force
    Overwrites existing project files.

.PARAMETER Root
    Destination directory for the project.

.EXAMPLE
    .\setup.ps1

.EXAMPLE
    .\setup.ps1 -Force

.EXAMPLE
    .\setup.ps1 -Root "$HOME\PowerShell"
#>

[CmdletBinding()]
param(
    [string]$Root = $PSScriptRoot,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Join-Path $HOME 'PowerShell'
}

$Root = [System.IO.Path]::GetFullPath($Root)

# ============================================
# PROJECT DIRECTORIES
# ============================================

$directories = @(
    'modules'
    'completions'
    'cache'
    'logs'
    'config'
    'tests'
)

# ============================================
# PROJECT FILES
# ============================================

$files = [ordered]@{

'modules/autocomplete.ps1' = @'
# ============================================
# AUTOCOMPLETE ENGINE
# ============================================

function Register-CustomCompleter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CommandName,

        [Parameter(Mandatory)]
        [string[]]$Values
    )

    $completionValues = @($Values)

    $completer = {
        param(
            $commandName,
            $parameterName,
            $wordToComplete,
            $commandAst,
            $fakeBoundParameters
        )

        foreach ($value in $completionValues) {
            if ($value -like "$wordToComplete*") {
                [System.Management.Automation.CompletionResult]::new(
                    $value,
                    $value,
                    'ParameterValue',
                    $value
                )
            }
        }
    }.GetNewClosure()

    Register-ArgumentCompleter `
        -CommandName $CommandName `
        -ScriptBlock $completer
}

function Initialize-Autocomplete {
    [CmdletBinding()]
    param()

    Register-CustomCompleter -CommandName mytool -Values @(
        'install'
        'uninstall'
        'update'
        'search'
        'list'
        'version'
        'help'
    )

    Register-CustomCompleter -CommandName devtool -Values @(
        'build'
        'clean'
        'run'
        'test'
        'lint'
        'format'
    )

    Write-Verbose 'Autocomplete engine initialized.'
}
'@

'modules/predictions.ps1' = @'
# ============================================
# PSREADLINE PREDICTIONS
# ============================================

if (-not (Get-Module -ListAvailable PSReadLine)) {
    return
}

Import-Module PSReadLine -ErrorAction SilentlyContinue

$parameters = (Get-Command Set-PSReadLineOption).Parameters

Set-PSReadLineOption -EditMode Windows
Set-PSReadLineOption -HistoryNoDuplicates
Set-PSReadLineOption -MaximumHistoryCount 10000
Set-PSReadLineOption -HistorySearchCursorMovesToEnd

Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key Ctrl+r -Function ReverseSearchHistory
Set-PSReadLineKeyHandler -Key Ctrl+Spacebar -Function MenuComplete

if ($parameters.ContainsKey('PredictionSource')) {
    Set-PSReadLineOption `
        -PredictionSource History `
        -ErrorAction SilentlyContinue
}

if ($parameters.ContainsKey('PredictionViewStyle')) {
    Set-PSReadLineOption `
        -PredictionViewStyle ListView `
        -ErrorAction SilentlyContinue
}
'@

'modules/aliases.ps1' = @'
# ============================================
# POWERSHELL ALIASES
# ============================================

Set-Alias ll Get-ChildItem -Option AllScope
Set-Alias la Get-ChildItem -Option AllScope
Set-Alias which Get-Command
Set-Alias grep Select-String
Set-Alias touch New-Item
Set-Alias cls Clear-Host

function Edit-Profile {
    notepad.exe $PROFILE
}

function Reload-Profile {
    . $PROFILE
}

function Update-Modules {
    Update-Module -ErrorAction Continue
}
'@

'modules/functions.ps1' = @'
# ============================================
# UTILITY FUNCTIONS
# ============================================

function Get-CommandInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    Get-Command -Name $Name -All -ErrorAction SilentlyContinue |
        Format-List Name, CommandType, Source, Definition
}

function Find-Command {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Pattern
    )

    Get-Command -Name "*$Pattern*" -ErrorAction SilentlyContinue
}

function Reload-Completion {
    [CmdletBinding()]
    param()

    . (Join-Path $HOME 'PowerShell/Microsoft.PowerShell_profile.ps1')
    Write-Host 'Completion configuration reloaded.'
}

function Get-PythonEnvironments {
    Get-ChildItem -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object {
            Test-Path (Join-Path $_.FullName 'pyvenv.cfg')
        }
}
'@

'completions/git.ps1' = @'
# ============================================
# GIT COMPLETION
# ============================================

Register-ArgumentCompleter -Native -CommandName git -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $commands = @(
        'add', 'branch', 'checkout', 'cherry-pick',
        'clone', 'commit', 'diff', 'fetch', 'init',
        'log', 'merge', 'pull', 'push', 'rebase',
        'remote', 'reset', 'restore', 'show', 'stash',
        'status', 'switch', 'tag', 'worktree'
    )

    $tokens = @(
        $commandAst.CommandElements |
            ForEach-Object { $_.ToString() }
    )

    $previous = if ($tokens.Count -gt 1) {
        $tokens[-2]
    } else {
        ''
    }

    $items = @()

    if ($previous -in @('checkout', 'switch', 'branch')) {
        $items += git branch --format='%(refname:short)' 2>$null
        $items += git branch -r --format='%(refname:short)' 2>$null
    }
    elseif ($tokens.Count -le 2) {
        $items += $commands
    }

    $items |
        Where-Object { $_ -like "$wordToComplete*" } |
        Sort-Object -Unique |
        ForEach-Object {
            [System.Management.Automation.CompletionResult]::new(
                $_, $_, 'ParameterValue', $_
            )
        }
}
'@

'completions/docker.ps1' = @'
# ============================================
# DOCKER COMPLETION
# ============================================

Register-ArgumentCompleter -Native -CommandName docker -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $commands = @(
        'build', 'compose', 'container', 'cp',
        'create', 'exec', 'images', 'image',
        'info', 'inspect', 'kill', 'logs',
        'login', 'logout', 'network', 'pause',
        'ps', 'pull', 'push', 'restart', 'rm',
        'rmi', 'run', 'search', 'start',
        'stats', 'stop', 'system', 'tag',
        'top', 'unpause', 'version', 'volume'
    )

    $tokens = @(
        $commandAst.CommandElements |
            ForEach-Object { $_.ToString() }
    )

    $previous = if ($tokens.Count -gt 1) {
        $tokens[-2]
    } else {
        ''
    }

    $items = @()

    if ($previous -in @(
        'stop', 'start', 'restart', 'rm',
        'kill', 'logs', 'exec'
    )) {
        $items += docker ps -a --format '{{.Names}}' 2>$null
    }
    elseif ($previous -in @('rmi', 'tag', 'image')) {
        $items += docker images --format '{{.Repository}}:{{.Tag}}' 2>$null
    }
    elseif ($tokens.Count -le 2) {
        $items += $commands
    }

    $items |
        Where-Object { $_ -like "$wordToComplete*" } |
        Sort-Object -Unique |
        ForEach-Object {
            [System.Management.Automation.CompletionResult]::new(
                $_, $_, 'ParameterValue', $_
            )
        }
}
'@

'completions/python.ps1' = @'
# ============================================
# PYTHON COMPLETION
# ============================================

Register-ArgumentCompleter -Native -CommandName python, python3, py -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $options = @(
        '-B', '-E', '-I', '-O', '-OO', '-P',
        '-S', '-s', '-u', '-v', '-V', '-W',
        '-b', '-c', '-d', '-i', '-m', '-q',
        '--help', '--version'
    )

    $items = if ($wordToComplete.StartsWith('-')) {
        $options
    } else {
        @('venv', 'pip', 'pytest', 'ruff', 'mypy', 'pylint')
    }

    $items |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object {
            [System.Management.Automation.CompletionResult]::new(
                $_, $_, 'ParameterValue', $_
            )
        }
}
'@

'completions/go.ps1' = @'
# ============================================
# GO COMPLETION
# ============================================

Register-ArgumentCompleter -Native -CommandName go -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $commands = @(
        'bug', 'build', 'clean', 'doc', 'env',
        'fix', 'fmt', 'generate', 'get', 'install',
        'list', 'mod', 'work', 'run', 'test',
        'tool', 'version', 'vet'
    )

    $options = @(
        '-a', '-n', '-p', '-race', '-v', '-x',
        '-cover', '-count', '-json', '-mod',
        '-o', '-tags', '-trimpath'
    )

    $tokens = @(
        $commandAst.CommandElements |
            ForEach-Object { $_.ToString() }
    )

    $items = if ($wordToComplete.StartsWith('-')) {
        $options
    }
    elseif ($tokens.Count -le 2) {
        $commands
    }
    else {
        @()
    }

    $items |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object {
            [System.Management.Automation.CompletionResult]::new(
                $_, $_, 'ParameterValue', $_
            )
        }
}
'@

'completions/custom.ps1' = @'
# ============================================
# CUSTOM COMPLETIONS
# ============================================

Register-CustomCompleter -CommandName cargo -Values @(
    'add', 'build', 'check', 'clean',
    'clippy', 'doc', 'fetch', 'fmt',
    'init', 'install', 'new', 'run',
    'search', 'test', 'update'
)

Register-CustomCompleter -CommandName npm -Values @(
    'audit', 'cache', 'ci', 'install',
    'init', 'link', 'outdated', 'publish',
    'run', 'start', 'test', 'uninstall',
    'update', 'version'
)

Register-CustomCompleter -CommandName pip -Values @(
    'install', 'uninstall', 'list', 'show',
    'freeze', 'check', 'download', 'cache'
)

Register-CustomCompleter -CommandName pytest -Values @(
    '-v', '-vv', '-q', '-x',
    '--collect-only', '--cov',
    '--disable-warnings', '--maxfail'
)

Register-CustomCompleter -CommandName ruff -Values @(
    'check', 'format', 'rule', 'config',
    'linter', 'version'
)
'@

'Microsoft.PowerShell_profile.ps1' = @'
# ============================================
# POWERSHELL AUTOCOMPLETE PROFILE
# ============================================

$ErrorActionPreference = 'Continue'

$ConfigRoot = Join-Path $HOME 'PowerShell'
$ModulePath = Join-Path $ConfigRoot 'modules'
$CompletionPath = Join-Path $ConfigRoot 'completions'

# Load engine first.
$engine = Join-Path $ModulePath 'autocomplete.ps1'

if (Test-Path $engine) {
    . $engine
    Initialize-Autocomplete
}

# Load remaining modules.
foreach ($file in @(
    'predictions.ps1',
    'aliases.ps1',
    'functions.ps1'
)) {
    $path = Join-Path $ModulePath $file

    if (Test-Path $path) {
        try {
            . $path
        }
        catch {
            Write-Warning "Module error: $file - $_"
        }
    }
}

# Load completion providers.
if (Test-Path $CompletionPath) {
    Get-ChildItem $CompletionPath -Filter '*.ps1' -File |
        Sort-Object Name |
        ForEach-Object {
            try {
                . $_.FullName
            }
            catch {
                Write-Warning "Completion error: $($_.Name) - $_"
            }
        }
}

# Optional terminal icons.
if (Get-Module -ListAvailable Terminal-Icons) {
    Import-Module Terminal-Icons -ErrorAction SilentlyContinue
}
'@

'install.ps1' = @'
# ============================================
# AUTOCOMPLETE INSTALLER
# ============================================

[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$Source = $PSScriptRoot
$Destination = Join-Path $HOME 'PowerShell'
$ProfilePath = $PROFILE
$Marker = '# PowerShell Autocomplete Engine'

try {
    New-Item -ItemType Directory -Path $Destination -Force |
        Out-Null

    foreach ($directory in @('modules', 'completions')) {
        $sourcePath = Join-Path $Source $directory
        $targetPath = Join-Path $Destination $directory

        New-Item -ItemType Directory -Path $targetPath -Force |
            Out-Null

        if (Test-Path $sourcePath) {
            Copy-Item "$sourcePath/*" $targetPath -Recurse -Force
        }
    }

    $mainProfile = Join-Path $Source 'Microsoft.PowerShell_profile.ps1'

    Copy-Item $mainProfile $Destination -Force

    if (-not (Get-Module -ListAvailable PSReadLine)) {
        Install-Module PSReadLine -Scope CurrentUser -Force
    }

    $profileDirectory = Split-Path $ProfilePath -Parent

    New-Item -ItemType Directory -Path $profileDirectory -Force |
        Out-Null

    if (-not (Test-Path $ProfilePath)) {
        New-Item -ItemType File -Path $ProfilePath -Force |
            Out-Null
    }

    $content = Get-Content $ProfilePath -Raw

    if ($content -like "*$Marker*") {
        if (-not $Force) {
            Write-Host 'Profile loader already exists.' -ForegroundColor Yellow
            return
        }

        Copy-Item $ProfilePath "$ProfilePath.bak" -Force
    }
    else {
        Copy-Item $ProfilePath "$ProfilePath.bak" -Force
    }

    if ($content -notlike "*$Marker*") {
        Add-Content -Path $ProfilePath -Value @'

# PowerShell Autocomplete Engine
$autocompleteProfile = Join-Path $HOME 'PowerShell/Microsoft.PowerShell_profile.ps1'

if (Test-Path $autocompleteProfile) {
    . $autocompleteProfile
}
'@
    }

    Write-Host 'Autocomplete installed successfully.' -ForegroundColor Green
    Write-Host "Destination: $Destination"
    Write-Host "Profile: $ProfilePath"
}
catch {
    Write-Error "Installation failed: $_"
    exit 1
}
'@

}

# ============================================
# CREATE DIRECTORIES
# ============================================

Write-Host "`nCreating project directories..." -ForegroundColor Cyan

New-Item -ItemType Directory -Path $Root -Force |
    Out-Null

foreach ($directory in $directories) {
    $path = Join-Path $Root $directory

    New-Item -ItemType Directory -Path $path -Force |
        Out-Null

    Write-Host "[DIR]  $directory" -ForegroundColor DarkCyan
}

# ============================================
# CREATE FILES
# ============================================

Write-Host "`nGenerating PowerShell scripts..." -ForegroundColor Cyan

$created = 0
$skipped = 0

foreach ($entry in $files.GetEnumerator()) {
    $relativePath = $entry.Key
    $content = $entry.Value

    $filePath = Join-Path $Root $relativePath
    $parent = Split-Path $filePath -Parent

    New-Item -ItemType Directory -Path $parent -Force |
        Out-Null

    if ((Test-Path $filePath) -and -not $Force) {
        Write-Host "[SKIP] $relativePath" -ForegroundColor Yellow
        $skipped++
        continue
    }

    if ((Test-Path $filePath) -and $Force) {
        Copy-Item $filePath "$filePath.bak" -Force
    }

    Set-Content -LiteralPath $filePath `
        -Value $content `
        -Encoding UTF8

    Write-Host "[FILE] $relativePath" -ForegroundColor Green
    $created++
}

# ============================================
# SUMMARY
# ============================================

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host " POWERSHELL AUTOCOMPLETE PROJECT GENERATED"
Write-Host "============================================" -ForegroundColor Cyan

Write-Host "Project:  $Root"
Write-Host "Created:  $created"
Write-Host "Skipped:  $skipped"
Write-Host "Force:    $Force"

Write-Host "`nNext steps:" -ForegroundColor Yellow

Write-Host "1. cd `"$Root`""
Write-Host "2. .\install.ps1"
Write-Host "3. Restart PowerShell"

Write-Host "`nSetup completed." -ForegroundColor Green
