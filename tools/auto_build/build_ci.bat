@echo off
setlocal enabledelayedexpansion

REM Parse command-line arguments
set "BUILD_CONFIG=CI"

:parse_args

if "%BUILD_CONFIG%"=="CI" (
    set "BUILD_CONFIG=%~1"
    shift
    goto parse_args
)
shift
goto parse_args

:end_parse
echo Starting CI build process...
echo Building with configuration: %BUILD_CONFIG%

echo Working dir: %cd%

REM Fix: Quotes placed around the variable name and value to prevent space truncation
set "nightly_build_folder=D:\Development\Installer\Windows\nightly_builds"
set "standalone_project=projects\standalone\Builds\VisualStudio2026\HISE Standalone.sln"
set "projucerPath=JUCE\projucer\Projucer.exe"
set "standalone_projucer_project=projects\standalone\HISE Standalone.jucer"
set "plugin_projucer_project=projects\plugin\HISE.jucer"
set "multipagecreator_projucer_project=tools\multipagecreator\multipagecreator.jucer"
set "hise_ci=projects\standalone\Builds\VisualStudio2026\x64\CI\App\HISE.exe"
set "multipagecreator_project=tools\multipagecreator\Builds\VisualStudio2026\multipagecreator.sln"
set "multipage_binary=tools\multipagecreator\Builds\VisualStudio2026\x64\Release\App\multipagecreator.exe"
set "plugin_project=projects\plugin\Builds\VisualStudio2026\HISE.sln"
set "installer_command=C:\Program Files (x86)\Inno Setup 6\ISCC.exe"

cd..
cd..

cd tools/SDK
tar -xf sdk.zip
cd ..
cd ..

"%projucerPath%" --resave "%standalone_projucer_project%"


:: Ensure the standalone .jucer file uses the requested VS2026 IPP settings.
if exist "%standalone_projucer_project%" (
    echo Ensuring VS2026 IPP settings in "%standalone_projucer_project%"...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$dq = [char]34; $path = (Resolve-Path '%standalone_projucer_project%').Path; $text = [System.IO.File]::ReadAllText($path); $text = [regex]::Replace($text, '(?m)(<VS2026\b[^>]*?)\s+\b(useIPP|IPPLibrary|IPP1ALibrary)=' + $dq + '[^' + $dq + ']*' + $dq, '$1'); $text = [regex]::Replace($text, '(?m)(<VS2026\b[^>]*?)(\s*/?>)', ('$1 useIPP=' + $dq + 'Sequential' + $dq + ' IPPLibrary=' + $dq + $dq + ' IPP1ALibrary=' + $dq + 'Static_Library' + $dq + '$2')); [System.IO.File]::WriteAllText($path, $text)"
) else (
    echo WARNING: "%standalone_projucer_project%" was not found, so IPP settings could not be updated.
)

:: Try to find MSBuild dynamically
if defined MSBUILD_PATH (
    set "MSBUILD_EXE=%MSBUILD_PATH%"
) else (
    for /f "usebackq tokens=*" %%i in (`vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath`) do set "MSBUILD_EXE=%%i\MSBuild\Current\Bin\MsBuild.exe"
)
echo Using MSBuild at: %MSBUILD_EXE%

echo Compiling 64bit Standalone App...

"!MSBUILD_EXE!" "%standalone_project%" /t:Build /m:2 /p:Configuration=%BUILD_CONFIG%;Platform=x64;PreferredToolArchitecture=x64;PlatformToolset=v143;CL_MPCount=2 /v:m

if !errorlevel! NEQ 0 (
    echo ========================================================================
    echo Error at compiling standalone. Aborting...
    cd tools\auto_build
    exit 1
)

echo OK

cd tools\auto_build
echo OK