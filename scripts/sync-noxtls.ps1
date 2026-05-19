[CmdletBinding()]
param(
    [switch]$SkipPdscUpdate
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$upstreamRoot = Join-Path $repoRoot "third_party/noxtls"
$upstreamLibRoot = Join-Path $upstreamRoot "noxtls-lib"
$upstreamUtilityRoot = Join-Path $upstreamRoot "utility"
$packRoot = Join-Path $repoRoot "NoxTLS/Files"
$includeRoot = Join-Path $packRoot "Include"
$sourceRoot = Join-Path $packRoot "Source"
$thirdPartyRoot = Join-Path $packRoot "ThirdParty/noxtls"
$originalPackRoot = Join-Path $repoRoot "NoxTLS/.project/OriginalPack"
$pdscPaths = @(
    (Join-Path $repoRoot "NoxTLS/Files/Argenox.NoxTLS.pdsc"),
    (Join-Path $repoRoot "NoxTLS/.project/Argenox.NoxTLS.pdsc")
)
$projectFileXmlPath = Join-Path $repoRoot "NoxTLS/.project/projectFile.xml"

function Assert-Exists {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw $Message
    }
}

function Clear-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        return
    }
    Get-ChildItem -LiteralPath $Path -Force | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
    }
}

function Mirror-Directory {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )
    if (Test-Path -LiteralPath $DestinationPath) {
        Get-ChildItem -LiteralPath $DestinationPath -Force | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force
        }
    } else {
        New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    }
    Get-ChildItem -LiteralPath $SourcePath -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $DestinationPath -Recurse -Force
    }
}

function Copy-FileWithRelativePath {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$File,
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )

    $baseFull = [System.IO.Path]::GetFullPath($BasePath)
    $fileFull = [System.IO.Path]::GetFullPath($File.FullName)
    $relativePath = $fileFull.Substring($baseFull.Length) -replace "^[\\/]+", ""
    $destination = Join-Path $DestinationRoot $relativePath
    $destinationDir = Split-Path -Parent $destination

    if (-not (Test-Path -LiteralPath $destinationDir)) {
        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    }

    Copy-Item -LiteralPath $fileFull -Destination $destination -Force
}

function To-PackRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$BasePath
    )

    $baseFull = [System.IO.Path]::GetFullPath($BasePath).TrimEnd("\")
    $fileFull = [System.IO.Path]::GetFullPath($FilePath)
    $relativePath = $fileFull.Substring($baseFull.Length) -replace "^[\\/]+", ""
    return ($relativePath -replace "\\", "/")
}

function Update-PdscFileList {
    param(
        [Parameter(Mandatory = $true)][string]$PdscPath,
        [Parameter(Mandatory = $true)][string[]]$GeneratedLines
    )

    $beginMarker = "<!-- SYNC_NOXTLS_BEGIN -->"
    $endMarker = "<!-- SYNC_NOXTLS_END -->"
    $content = Get-Content -LiteralPath $PdscPath -Raw

    $beginIndex = $content.IndexOf($beginMarker)
    $endIndex = $content.IndexOf($endMarker)

    if ($beginIndex -lt 0 -or $endIndex -lt 0 -or $endIndex -lt $beginIndex) {
        Write-Warning "Skipping PDSC auto-update for $PdscPath because SYNC_NOXTLS markers are missing."
        return $false
    }

    $prefix = $content.Substring(0, $beginIndex + $beginMarker.Length)
    $suffix = $content.Substring($endIndex)
    $insert = ""
    if ($GeneratedLines.Count -gt 0) {
        $insert = "`r`n" + ($GeneratedLines -join "`r`n")
    }

    $newContent = $prefix + $insert + "`r`n                    " + $suffix
    Set-Content -LiteralPath $PdscPath -Value $newContent -NoNewline
    return $true
}

Assert-Exists -Path $upstreamRoot -Message "Missing third_party/noxtls. Add/update the submodule first."
Assert-Exists -Path $upstreamLibRoot -Message "Missing third_party/noxtls/noxtls-lib."
Assert-Exists -Path $upstreamUtilityRoot -Message "Missing third_party/noxtls/utility."

Clear-Directory -Path $includeRoot
Clear-Directory -Path $sourceRoot

$rootHeaders = @(
    "noxtls_common.h",
    "noxtls_config.h",
    "noxtls_check_config.h",
    "noxtls_version.h"
)

foreach ($headerName in $rootHeaders) {
    $headerPath = Join-Path $upstreamRoot $headerName
    Assert-Exists -Path $headerPath -Message "Missing required header: $headerName"
    Copy-Item -LiteralPath $headerPath -Destination (Join-Path $includeRoot $headerName) -Force
}

$libraryHeaders = Get-ChildItem -Path $upstreamLibRoot -Recurse -File -Filter *.h |
    Sort-Object FullName
foreach ($header in $libraryHeaders) {
    Copy-FileWithRelativePath -File $header -BasePath $upstreamLibRoot -DestinationRoot (Join-Path $includeRoot "noxtls-lib")
}

$librarySources = Get-ChildItem -Path $upstreamLibRoot -Recurse -File -Filter *.c |
    Where-Object { $_.Name -notmatch "^test_.*" } |
    Sort-Object FullName
foreach ($sourceFile in $librarySources) {
    Copy-FileWithRelativePath -File $sourceFile -BasePath $upstreamLibRoot -DestinationRoot (Join-Path $sourceRoot "noxtls-lib")
}

$libraryIncludes = Get-ChildItem -Path $upstreamLibRoot -Recurse -File -Filter *.inc |
    Sort-Object FullName
foreach ($includeFile in $libraryIncludes) {
    Copy-FileWithRelativePath -File $includeFile -BasePath $upstreamLibRoot -DestinationRoot (Join-Path $sourceRoot "noxtls-lib")
}

$utilityHeaders = Get-ChildItem -Path $upstreamUtilityRoot -Recurse -File -Filter *.h |
    Sort-Object FullName
foreach ($header in $utilityHeaders) {
    Copy-FileWithRelativePath -File $header -BasePath $upstreamUtilityRoot -DestinationRoot (Join-Path $includeRoot "utility")
}

$utilitySources = Get-ChildItem -Path $upstreamUtilityRoot -Recurse -File -Filter *.c |
    Sort-Object FullName
foreach ($sourceFile in $utilitySources) {
    Copy-FileWithRelativePath -File $sourceFile -BasePath $upstreamUtilityRoot -DestinationRoot (Join-Path $sourceRoot "utility")
}

if (-not (Test-Path -LiteralPath $thirdPartyRoot)) {
    New-Item -ItemType Directory -Path $thirdPartyRoot -Force | Out-Null
}

Copy-Item -LiteralPath (Join-Path $upstreamRoot "LICENSE.md") -Destination (Join-Path $thirdPartyRoot "LICENSE.md") -Force
Copy-Item -LiteralPath (Join-Path $upstreamRoot "COPYING.md") -Destination (Join-Path $thirdPartyRoot "COPYING.md") -Force
Copy-Item -LiteralPath (Join-Path $upstreamRoot "README.md") -Destination (Join-Path $thirdPartyRoot "README.upstream.md") -Force

if (-not $SkipPdscUpdate) {
    $generatedPdscLines = @()

    $includeDirs = Get-ChildItem -Path $includeRoot -Recurse -Directory |
        Sort-Object FullName
    foreach ($dir in $includeDirs) {
        $relativeIncludeDir = To-PackRelativePath -FilePath $dir.FullName -BasePath $packRoot
        $generatedPdscLines += ("                    <file category=""include"" name=""{0}/""/>" -f $relativeIncludeDir)
    }

    $syncedHeaders = Get-ChildItem -Path $includeRoot -Recurse -File -Filter *.h | Sort-Object FullName
    foreach ($syncedHeader in $syncedHeaders) {
        $relativeHeader = To-PackRelativePath -FilePath $syncedHeader.FullName -BasePath $packRoot
        $generatedPdscLines += ("                    <file category=""header"" name=""{0}""/>" -f $relativeHeader)
    }

    $syncedSources = Get-ChildItem -Path $sourceRoot -Recurse -File -Filter *.c | Sort-Object FullName
    foreach ($syncedSource in $syncedSources) {
        $relativeSource = To-PackRelativePath -FilePath $syncedSource.FullName -BasePath $packRoot
        $generatedPdscLines += ("                    <file category=""sourceC"" name=""{0}""/>" -f $relativeSource)
    }

    $updatedProjectPdsc = $false
    foreach ($pdscPath in $pdscPaths) {
        Assert-Exists -Path $pdscPath -Message "Missing PDSC file: $pdscPath"
        $updated = Update-PdscFileList -PdscPath $pdscPath -GeneratedLines $generatedPdscLines
        if ($pdscPath -eq $pdscPaths[1] -and $updated) {
            $updatedProjectPdsc = $true
        }
    }

    # STM32PackCreator reads .project/projectFile.xml as project source.
    # Keep it identical to the .project PDSC so GUI reflects synchronized files/components.
    if ($updatedProjectPdsc) {
        Assert-Exists -Path $pdscPaths[1] -Message "Missing project PDSC: $($pdscPaths[1])"
        Copy-Item -LiteralPath $pdscPaths[1] -Destination $projectFileXmlPath -Force
    } else {
        Write-Warning "Skipping projectFile.xml refresh because .project PDSC was not auto-updated."
    }
}

# STM32PackCreator resolves sources from .project/OriginalPack during generation.
# Mirror the pack staging tree there so all referenced files exist for GUI generation.
Mirror-Directory -SourcePath $packRoot -DestinationPath $originalPackRoot

$headerCount = (Get-ChildItem -Path $includeRoot -Recurse -File -Filter *.h).Count
$sourceCount = (Get-ChildItem -Path $sourceRoot -Recurse -File -Filter *.c).Count
Write-Host ("Synced NoxTLS into pack staging: {0} headers, {1} sources." -f $headerCount, $sourceCount)
