@echo off
setlocal enabledelayedexpansion

REM Parse command-line arguments
set "USE_IPP=false"
set "BUILD_CONFIG=CI"

:parse_args
if "%~1"=="" goto end_parse
if /I "%~1"=="--use-ipp" (
    set "USE_IPP=true"
    shift
    goto parse_args
)
if "%BUILD_CONFIG%"=="CI" (
    set "BUILD_CONFIG=%~1"
    shift
    goto parse_args
)
shift
goto parse_args

:end_parse
echo Starting CI build process...
echo Use IPP: %USE_IPP%
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

:: Fix: Flattened the IPP condition using a goto jump.
:: This completely avoids the fatal parenthesis trap with your inline Python.
if /I NOT "%USE_IPP%"=="true" (
    echo Skipping IPP configuration and project resave because USE_IPP is not true.
    goto skip_ipp
)

:: IPP is installed by the GitHub Actions workflow step before this script runs.
if exist "C:\Program Files (x86)\Intel\oneAPI\ipp\latest" (
    echo Intel IPP installed successfully
) else (
    echo Intel IPP installation not found
    exit /b 1
)
SET "IPP_PATH=C:\Program Files (x86)\Intel\oneAPI\ipp\latest"

:: Set the Global Search Path in Projucer for 'ipp'
echo Configuring Projucer IPP path...

:: Initialize Intel oneAPI environment variables
call "C:\Program Files (x86)\Intel\oneAPI\setvars.bat"

:: 1. Define Intel oneAPI IPP Paths
set "IPP_DIR=C:\Program Files (x86)\Intel\oneAPI\ipp\latest"
set "IPP_INCLUDE=%IPP_DIR%\include"
set "IPP_LIB=%IPP_DIR%\lib\intel64"

:: 2. Append IPP paths to standard MSVC environment variables
set "INCLUDE=%IPP_INCLUDE%;%INCLUDE%"
set "LIB=%IPP_LIB%;%LIB%"
set "PATH=%IPP_DIR%\bin;%PATH%"

"%projucerPath%" --resave "%standalone_projucer_project%"

echo.
echo Forcing Projucer to regenerate Visual Studio Solution files...
"%projucerPath%" --resave "%plugin_projucer_project%"
if !errorlevel! neq 0 (
    echo ❌ Projucer failed to resave project!
    pause
    exit /b !errorlevel!
)

:: Ensure the standalone .jucer file uses the requested VS2026 IPP settings.
if exist "%standalone_projucer_project%" (
    echo Ensuring VS2026 IPP settings in "%standalone_projucer_project%"...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$path = (Resolve-Path '%standalone_projucer_project%').Path; $text = [System.IO.File]::ReadAllText($path); $text = [regex]::Replace($text, '(?m)(<VS2026\b[^>]*?)\s+\b(useIPP|IPPLibrary|IPP1ALibrary)="[^"]*"', '$1'); $text = [regex]::Replace($text, '(?m)(<VS2026\b[^>]*?)(\s*/?>)', '$1 useIPP="Sequential" IPPLibrary="" IPP1ALibrary="Static_Library"$2'); [System.IO.File]::WriteAllText($path, $text)"
) else (
    echo WARNING: "%standalone_projucer_project%" was not found, so IPP settings could not be updated.
)

echo.
echo 🎉 SUCCESS! Your HISE VST project is completely configured with pip-installed IPP.

:skip_ipp

:: Try to find MSBuild dynamically
if defined MSBUILD_PATH (
    set "MSBUILD_EXE=%MSBUILD_PATH%"
) else (
    for /f "usebackq tokens=*" %%i in (`vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath`) do set "MSBUILD_EXE=%%i\MSBuild\Current\Bin\MsBuild.exe"
)
echo Using MSBuild at: %MSBUILD_EXE%

REM ===========================================================
REM Compiling

echo Compiling 64bit VST Plugins
set "Platform=X64"

if !errorlevel! NEQ 0 (
    echo ========================================================================
    echo Error at compiling VST. Aborting...
    cd tools\auto_build
    exit 1
)

echo OK

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