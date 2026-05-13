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

# Source compatibility fixes for current Geode/C++23 Windows builds.
$probeOverlayPath = Join-Path $sourcePath "src/ProbeOverlay.cpp"
if (Test-Path $probeOverlayPath) {
    $probeText = Get-Content -Raw $probeOverlayPath
    $probeText = $probeText.Replace("#include <Geode/ui/CCMenuItemSpriteExtra.hpp>", "#include <Geode/binding/CCMenuItemSpriteExtra.hpp>")
    Set-Content -NoNewline -Path $probeOverlayPath -Value $probeText
    Write-Host "Source compatibility: normalized CCMenuItemSpriteExtra include"
}

$levelDumperPath = Join-Path $sourcePath "src/LevelDumper.cpp"
if (Test-Path $levelDumperPath) {
    $levelText = Get-Content -Raw $levelDumperPath
    $pathStringBlock = @'
std::string pathString(const std::filesystem::path& p) {
#if defined(__cpp_char8_t)
    auto u8 = p.u8string();
    return std::string(reinterpret_cast<const char*>(u8.data()), u8.size());
#else
    return p.u8string();
#endif
}
'@
    $pathStringPattern = 'std::string\s+pathString\s*\(\s*const\s+std::filesystem::path&\s+p\s*\)\s*\{\s*return\s+p\.u8string\(\);\s*\}'
    if ([regex]::IsMatch($levelText, $pathStringPattern)) {
        $levelText = [regex]::Replace($levelText, $pathStringPattern, $pathStringBlock, 1)
        Set-Content -NoNewline -Path $levelDumperPath -Value $levelText
        Write-Host "Source compatibility: made filesystem u8string conversion C++20/23-safe"
    }
}

$modJson = Get-Content -Raw $modJsonPath | ConvertFrom-Json
$modJson.geode = $GeodeVersion
$modJson | ConvertTo-Json -Depth 20 | Set-Content -Path $modJsonPath

Write-Host "Standardized source at $sourcePath"
Write-Host "Geode version: $GeodeVersion"
Write-Host "Windows build definitions: AIGD_GEODE_PROBE_WINDOWS=1 WIN32_LEAN_AND_MEAN NOMINMAX"
Write-Host "Windows socket library: ws2_32 linked using CMake plain signature"
