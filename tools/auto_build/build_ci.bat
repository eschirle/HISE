@echo off
setlocal enabledelayedexpansion

REM Parse command-line arguments
set "SKIP_TESTS_AND_EXPORT=false"
set "USE_IPP=false"
set "BUILD_CONFIG=CI"

:parse_args
if "%~1"=="" goto end_parse
if /I "%~1"=="--skip-tests-and-export" (
    set "SKIP_TESTS_AND_EXPORT=true"
    shift
    goto parse_args
)
if /I "%~1"=="--use-ipp" (
    set "USE_IPP=true"
    shift
    goto parse_args
)
if /I "%~1:~0,10%"=="--use-ipp=" (
    set "USE_IPP=%~1:~10%"
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
echo Skip tests and export: %SKIP_TESTS_AND_EXPORT%
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
"%projucerPath%" --set-global-search-path windows ipp "%IPP_PATH%"

"%projucerPath%" --resave "%standalone_projucer_project%"

echo.
echo Forcing Projucer to regenerate Visual Studio Solution files...
"%projucerPath%" --resave "%plugin_projucer_project%"
if !errorlevel! neq 0 (
    echo ❌ Projucer failed to resave project!
    pause
    exit /b !errorlevel!
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

"!MSBUILD_EXE!" "%standalone_project%" /t:Build /p:"Configuration=%BUILD_CONFIG%;Platform=x64;PreferredToolArchitecture=x64;PlatformToolset=v143" /v:m

if !errorlevel! NEQ 0 (
    echo ========================================================================
    echo Error at compiling standalone. Aborting...
    cd tools\auto_build
    exit 1
)

echo OK

:: Fix: Flattened tests block using goto to avoid parse-time evaluation issues
if /I "%SKIP_TESTS_AND_EXPORT%"=="true" (
    echo Skipping unit tests...
    goto skip_tests_and_export
)

echo Running Unit Tests...

set "hise_ci_test=projects\standalone\Builds\VisualStudio2017\x64\%BUILD_CONFIG%\App\HISE.exe"

"%hise_ci_test%" run_unit_tests

if !errorlevel! NEQ 0 (
    echo ...
    echo ========================================================================
    echo Error at running unit tests. Aborting...
    cd tools\auto_build
    pause
    exit 1
)

echo Exporting Scriptnode DLL

"%hise_ci_test%" set_project_folder "-p:%cd%/extras/demo_project/"
"%hise_ci_test%" compile_networks -c:Debug

if !errorlevel! NEQ 0 (
    echo ========================================================================
    echo Error at exporting test project. Aborting...
    cd tools\auto_build
    pause
    exit 1
)

call "%cd%/extras/demo_project/DspNetworks/Binaries/batchCompile.bat"

echo Exporting Demo Project...

"%hise_ci_test%" set_project_folder "-p:%cd%/extras/demo_project/"
"%hise_ci_test%" export_ci "XmlPresetBackups/Demo.xml" -t:instrument -p:VST2 -a:x64 -nolto

if !errorlevel! NEQ 0 (
    echo ========================================================================
    echo Error at exporting test project. Aborting...
    cd tools\auto_build
    pause
    exit 1
)

call "%cd%/extras/demo_project/Binaries/batchCompile.bat"

if !errorlevel! NEQ 0 (
    echo ========================================================================
    echo Error at compiling test project. Aborting...
    cd tools\auto_build
    pause
    exit 1
)

echo OK

:skip_tests_and_export

cd tools\auto_build
echo OK