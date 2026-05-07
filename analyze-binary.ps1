param(
    [Parameter(Mandatory=$true)]
    [string]$FilePath
)

if (-not (Test-Path $FilePath)) {
    Write-Host "Error: File not found: $FilePath" -ForegroundColor Red
    exit 1
}

$bytes = [System.IO.File]::ReadAllBytes($FilePath)
$fileName = [System.IO.Path]::GetFileName($FilePath)
$outDir = Join-Path (Split-Path $FilePath) "analysis-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -Path $outDir -ItemType Directory -Force | Out-Null

function Write-Section {
    param([string]$Title)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

# === PE HEADER ===
Write-Section "PE HEADER ANALYSIS"

$e_lfanew = [BitConverter]::ToInt32($bytes, 0x3C)
Write-Host "e_lfanew (PE offset): 0x$($e_lfanew.ToString('X8'))"

$peOffset = $e_lfanew
$sig = [BitConverter]::ToString($bytes[$peOffset..($peOffset+3)])
Write-Host "PE Signature: $sig"

$coffOffset = $peOffset + 4
$machine = [BitConverter]::ToUInt16($bytes, $coffOffset)
$numSections = [BitConverter]::ToUInt16($bytes, $coffOffset + 2)
$timestamp = [BitConverter]::ToUInt32($bytes, $coffOffset + 4)
$characteristics = [BitConverter]::ToUInt16($bytes, $coffOffset + 18)

Write-Host "Machine: 0x$($machine.ToString('X4')) $(if ($machine -eq 0x8664) { '(x64)' } elseif ($machine -eq 0x14c) { '(x86)' } else { '(Unknown)' })"
Write-Host "Sections: $numSections"
Write-Host "Timestamp: $([System.DateTimeOffset]::FromUnixTimeSeconds($timestamp).ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "Characteristics: 0x$($characteristics.ToString('X4'))"

# Optional Header
$optOffset = $coffOffset + 20
$magic = [BitConverter]::ToUInt16($bytes, $optOffset)
$peType = if ($magic -eq 0x20B) { 'PE32+ (64-bit)' } elseif ($magic -eq 0x10B) { 'PE32 (32-bit)' } else { 'Unknown' }
Write-Host "Type: $peType"

$clrRva = if ($magic -eq 0x20B) {
    [BitConverter]::ToUInt32($bytes, $optOffset + 112 + 14 * 8)
} else {
    [BitConverter]::ToUInt32($bytes, $optOffset + 96 + 14 * 8)
}
Write-Host ".NET CLR Header: $(if ($clrRva -ne 0) { 'YES (0x{0:X8})' -f $clrRva } else { 'NO - Native binary' })"

# === SECTIONS ===
Write-Section "SECTIONS ($numSections)"

$sectionOffset = $coffOffset + 20 + [BitConverter]::ToUInt16($bytes, $coffOffset + 16)
$sections = @()
for ($i = 0; $i -lt $numSections; $i++) {
    $base = $sectionOffset + ($i * 40)
    $nameRaw = $bytes[$base..($base+7)]
    $name = [System.Text.Encoding]::ASCII.GetString($nameRaw).Trim([char]0)
    $virtSize = [BitConverter]::ToUInt32($bytes, $base + 8)
    $virtAddr = [BitConverter]::ToUInt32($bytes, $base + 12)
    $rawSize = [BitConverter]::ToUInt32($bytes, $base + 16)
    $rawOffset = [BitConverter]::ToUInt32($bytes, $base + 20)
    $entropy = if ($rawSize -gt 0) {
        $chunk = $bytes[$rawOffset..([Math]::Min($rawOffset + $rawSize - 1, $bytes.Length - 1))]
        $freq = @{}
        foreach ($b in $chunk) { $freq[$b] = ($freq[$b] + 1) }
        [Math]::Round((($freq.Values | ForEach-Object { $p = $_ / $chunk.Length; if ($p -gt 0) { -$p * [Math]::Log($p, 2) } else { 0 } }) | Measure-Object -Sum).Sum, 2)
    } else { 0 }

    $sections += [PSCustomObject]@{ Name=$name; VirtSize=$virtSize; VirtAddr="0x$($virtAddr.ToString('X8'))"; RawSize=$rawSize; Entropy=$entropy }
    Write-Host ("  {0,-10} Virt: {1,-12} Raw: {2,-10} Entropy: {3}" -f $name, "0x$($virtAddr.ToString('X8'))", "$rawSize bytes", $entropy)
}

$sections | ConvertTo-Json | Out-File (Join-Path $outDir "sections.json")
Write-Host "`nSections saved to sections.json"

# Suspicious section names
$suspicious = @('.aspack', '.nsp0', '.nsp1', '.upx0', '.upx1', '.upx2', '.themida', '.vmp0', '.vmp1', '.vmp2', '.adata', 'ASPack', 'PEBundle')
$packed = $sections | Where-Object { $suspicious -contains $_.Name }
if ($packed.Count -gt 0) {
    Write-Host "`nWARNING: Packed/compressed sections detected: $($packed.Name -join ', ')" -ForegroundColor Yellow
    Write-Host "  This binary is packed. Strings and code are hidden." -ForegroundColor Yellow
}

$highEntropy = $sections | Where-Object { $_.Entropy -gt 7.0 }
if ($highEntropy.Count -gt 0) {
    Write-Host "`nWARNING: High entropy sections (>7.0) — likely encrypted/packed: $($highEntropy.Name -join ', ')" -ForegroundColor Yellow
}

# === IMPORTS ===
Write-Section "IMPORTED DLLs"

$dataDirOffset = if ($magic -eq 0x20B) { $optOffset + 112 } else { $optOffset + 96 }
$importRva = [BitConverter]::ToUInt32($bytes, $dataDirOffset + 1 * 8)
$importSize = [BitConverter]::ToUInt32($bytes, $dataDirOffset + 1 * 8 + 4)

if ($importRva -ne 0) {
    $importDlls = @()
    $importsFound = @()
    
    foreach ($s in $sections) {
        $raw = $bytes[0..$bytes.Length]
        $dllPattern = [regex]::Matches(
            [System.Text.Encoding]::ASCII.GetString($raw),
            '[\x20-\x7E]{3,50}\.dll(?=\x00)'
        )
        foreach ($m in $dllPattern) {
            $dllName = $m.Value
            if ($dllName -match '^[a-zA-Z0-9_-]+\.dll$' -and $dllName -notin $importsFound) {
                $importsFound += $dllName
                $importDlls += $dllName
            }
        }
    }
    
    $dangerousApis = @('WriteProcessMemory', 'CreateRemoteThread', 'NtUnmapViewOfSection', 'VirtualAllocEx', 'OpenProcess', 'SetWindowsHookEx', 'GetProcAddress', 'LoadLibraryA', 'GetModuleHandle')
    
    foreach ($dll in $importDlls | Sort-Object) {
        Write-Host "  $dll"
    }
    
    $content = [System.Text.Encoding]::ASCII.GetString($bytes)
    $dangerFound = @()
    foreach ($api in $dangerousApis) {
        if ($content -match [regex]::Escape($api)) {
            $dangerFound += $api
        }
    }
    
    if ($dangerFound.Count -gt 0) {
        Write-Host "`nDANGEROUS API CALLS FOUND:" -ForegroundColor Red
        foreach ($api in $dangerFound) {
            $desc = switch ($api) {
                'WriteProcessMemory'  { 'Inject code into other processes' }
                'CreateRemoteThread'  { 'Execute code in other processes' }
                'NtUnmapViewOfSection'{ 'Process hollowing (malware technique)' }
                'VirtualAllocEx'      { 'Allocate memory in other processes' }
                'OpenProcess'         { 'Access other processes' }
                'SetWindowsHookEx'    { 'Hook keyboard/mouse input' }
                default               { 'Potentially suspicious' }
            }
            Write-Host "  [!] $api - $desc" -ForegroundColor Red
        }
    }
    
    $importDlls | Out-File (Join-Path $outDir "imports.txt")
} else {
    Write-Host "  Import directory not found or binary is packed" -ForegroundColor Yellow
}

# === STRINGS ===
Write-Section "EXTRACTED STRINGS"

$allStrings = [regex]::Matches([System.Text.Encoding]::ASCII.GetString($bytes), '[\x20-\x7E]{6,}')
$uniqueStrings = $allStrings | ForEach-Object { $_.Value } | Select-Object -Unique

$interesting = @()
foreach ($s in $uniqueStrings) {
    if ($s -match '(?i)(roblox|executor|inject|script|exploit|bypass|anti|cheat|detect|kernel|driver|vmware|virtual|sandbox|debug|breakpoint|hook|patch|malloc|memory|process|thread|create|write|read|virtual|alloc|dll|http|https|ip|port|socket|token|auth|keygen|serial|license|crack|payload|shell|exec|cmd|powershell|wmi|registry)') {
        $interesting += $s
    }
}

if ($interesting.Count -gt 0) {
    Write-Host "Found $($interesting.Count) interesting strings:`n" -ForegroundColor Green
    foreach ($s in $interesting | Select-Object -First 50) {
        Write-Host "  $s" -ForegroundColor White
    }
    $interesting | Out-File (Join-Path $outDir "strings-interesting.txt")
    Write-Host "`nSaved $($interesting.Count) strings to strings-interesting.txt"
} else {
    Write-Host "  No interesting strings found — binary is likely packed/encrypted" -ForegroundColor Yellow
    
    # Show some raw strings anyway
    $sample = $uniqueStrings | Select-Object -First 30
    if ($sample.Count -gt 0) {
        Write-Host "`nSample strings (binary may be packed):" -ForegroundColor Yellow
        foreach ($s in $sample) {
            Write-Host "  $s"
        }
    }
}

# === RESOURCE CHECK ===
Write-Section "RESOURCES"

$resourceRva = [BitConverter]::ToUInt32($bytes, $dataDirOffset + 2 * 8)
$resourceSize = [BitConverter]::ToUInt32($bytes, $dataDirOffset + 2 * 8 + 4)
if ($resourceRva -ne 0) {
    Write-Host "Resource Directory: RVA=0x$($resourceRva.ToString('X8')), Size=$resourceSize bytes"
    
    # Check for embedded files
    $peSection = $sections | Where-Object { $resourceRva -ge [Convert]::ToUInt32($_.VirtAddr, 16) -and $resourceRva -lt ([Convert]::ToUInt32($_.VirtAddr, 16) + $_.VirtSize) }
    if ($peSection) {
        $fileOffset = $resourceRva - [Convert]::ToUInt32($peSection.VirtAddr, 16) + ($sections.IndexOf($peSection) * 40 + 20)
        Write-Host "Resources in section: $($peSection.Name)"
    }
} else {
    Write-Host "  No resource directory found"
}

# === SUMMARY ===
Write-Section "SUMMARY"

$fileSizeMB = [Math]::Round($bytes.Length / 1MB, 2)
Write-Host "File size: $fileSizeMB MB"
Write-Host "Architecture: $(if ($machine -eq 0x8664) { 'x64' } elseif ($machine -eq 0x14c) { 'x86' } else { 'Unknown' })"
Write-Host "Is .NET: $(if ($clrRva -ne 0) { 'YES' } else { 'NO (native) - dnSpy cannot decompile this' })"
Write-Host "Packed: $(if ($packed.Count -gt 0 -or $highEntropy.Count -gt 0) { 'YES' } else { 'Likely no' })"
Write-Host "Output directory: $outDir"

if ($clrRva -eq 0) {
    Write-Host "`nThis is a NATIVE binary. You need:" -ForegroundColor Yellow
    Write-Host "  - Ghidra (https://ghidra-sre.org/) for decompilation" -ForegroundColor Yellow
    Write-Host "  - x64dbg for debugging" -ForegroundColor Yellow
    Write-Host "  - PE-bear for PE analysis" -ForegroundColor Yellow
}

Write-Host "`nAnalysis complete." -ForegroundColor Green
