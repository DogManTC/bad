param(
    [string]$SourceDir = "work/aigd-geode-probe",
    [string]$GeodeVersion = "5.7.1"
)

$ErrorActionPreference = "Stop"

$sourcePath = Resolve-Path $SourceDir
$cmakePath = Join-Path $sourcePath "CMakeLists.txt"
$modJsonPath = Join-Path $sourcePath "mod.json"

if (!(Test-Path $cmakePath)) {
    throw "CMakeLists.txt not found at $cmakePath"
}
if (!(Test-Path $modJsonPath)) {
    throw "mod.json not found at $modJsonPath"
}

$cmakeText = Get-Content -Raw $cmakePath

$windowsBlock = @'
if (WIN32)
    target_link_libraries(${PROJECT_NAME} ws2_32)
    target_compile_definitions(${PROJECT_NAME} PRIVATE
        AIGD_GEODE_PROBE_WINDOWS=1
        WIN32_LEAN_AND_MEAN
        NOMINMAX
    )
endif()
'@

$winBlockPattern = '(?s)if\s*\(\s*WIN32\s*\).*?endif\s*\(\s*\)'
if ([regex]::IsMatch($cmakeText, $winBlockPattern)) {
    $cmakeText = [regex]::Replace($cmakeText, $winBlockPattern, $windowsBlock, 1)
}
else {
    $cmakeText = $cmakeText.TrimEnd() + "`n`n" + $windowsBlock + "`n"
}

# Geode's CMake helper uses the plain target_link_libraries signature, so avoid
# mixing in the keyword form for ws2_32.
$cmakeText = $cmakeText.Replace("target_link_libraries(`${PROJECT_NAME} PRIVATE ws2_32)", "target_link_libraries(`${PROJECT_NAME} ws2_32)")
$cmakeText = $cmakeText.Replace("target_link_libraries(`$`{PROJECT_NAME`} PRIVATE ws2_32)", "target_link_libraries(`$`{PROJECT_NAME`} ws2_32)")
$cmakeText = $cmakeText.Replace(" PRIVATE ws2_32", " ws2_32")

Set-Content -NoNewline -Path $cmakePath -Value $cmakeText

$modJson = Get-Content -Raw $modJsonPath | ConvertFrom-Json
$modJson.geode = $GeodeVersion
$modJson | ConvertTo-Json -Depth 20 | Set-Content -Path $modJsonPath

Write-Host "Standardized source at $sourcePath"
Write-Host "Geode version: $GeodeVersion"
Write-Host "Windows build definitions: AIGD_GEODE_PROBE_WINDOWS=1 WIN32_LEAN_AND_MEAN NOMINMAX"
Write-Host "Windows socket library: ws2_32 linked using CMake plain signature"
