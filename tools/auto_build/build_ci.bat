@echo off

REM Parse command-line arguments
setlocal enabledelayedexpansion
set SKIP_TESTS_AND_EXPORT=false
set BUILD_CONFIG=CI

if "%1"=="" (
	set BUILD_CONFIG=CI
) else (
	set BUILD_CONFIG=%1
)

:parse_args
if "%2"=="" goto end_parse
if "%2"=="--skip-tests-and-export" (
	set SKIP_TESTS_AND_EXPORT=true
)
shift
goto parse_args

:end_parse
echo Starting CI build process...
echo Skip tests and export: %SKIP_TESTS_AND_EXPORT%
echo Building with configuration: %BUILD_CONFIG%

echo Working dir: %cd%

::call ConfigWindows.bat

cd..
cd..

cd tools/SDK

tar -xf sdk.zip

cd ..
cd ..

:: Setup Windows Config
SET standalone_project="projects\standalone\Builds\VisualStudio2026\HISE Standalone.sln"
SET projucerPath="JUCE\projucer\Projucer.exe"
SET standalone_projucer_project="projects\standalone\HISE Standalone.jucer"


%projucerPath% --resave %standalone_projucer_project%

REM ===========================================================
REM Compiling

echo Compiling 64bit VST Plugins

set Platform=X64

echo Compiling Stereo Version...

if %errorlevel% NEQ 0 (
	echo ========================================================================
	echo Error at compiling. Aborting...
	cd tools\auto_build
	exit 1
)

echo OK

echo Compiling 64bit Standalone App...

:: Try to find MSBuild dynamically
if defined MSBUILD_PATH (
    set MSBUILD_EXE=%MSBUILD_PATH%
) else (
    for /f "usebackq tokens=*" %%i in (`vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath`) do set MSBUILD_EXE=%%i\MSBuild\Current\Bin\MsBuild.exe
)
echo Using MSBuild at: %MSBUILD_EXE%

"!MSBUILD_EXE!" %standalone_project% /t:Build /p:Configuration=%BUILD_CONFIG%;Platform=x64;PlatformToolset=v143;UseIPP=false /v:m
REM "!MSBUILD_EXE!" %standalone_project% /t:Build /p:Configuration=%BUILD_CONFIG%;Platform=x64 /v:m

if %errorlevel% NEQ 0 (
	echo ========================================================================
	echo Error at compiling. Aborting...
	cd tools\auto_build
	exit 1
)

echo OK

if "%SKIP_TESTS_AND_EXPORT%"=="true" (
	echo Skipping unit tests...
) else (
	echo Running Unit Tests...

	SET hise_ci="projects\standalone\Builds\VisualStudio2026\x64\%BUILD_CONFIG%\App\HISE.exe"

	%hise_ci% run_unit_tests

	if %errorlevel% NEQ 0 (
		echo ...
		echo ========================================================================
		echo Error at running unit tests. Aborting...
		cd tools\auto_build
		pause
		exit 1
	)

	echo Exporting Scriptnode DLL

	%hise_ci% set_project_folder "-p:%cd%/extras/demo_project/"
	%hise_ci% compile_networks -c:Debug

	if %errorlevel% NEQ 0 (
		echo ========================================================================
		echo Error at exporting test project. Aborting...
		cd tools\auto_build
		pause
		exit 1)

	call "%cd%/extras/demo_project/DspNetworks/Binaries/batchCompile.bat"

	echo Exporting Demo Project...

	%hise_ci% set_project_folder "-p:%cd%/extras/demo_project/"
	%hise_ci% export_ci "XmlPresetBackups/Demo.xml" -t:instrument -p:VST2 -a:x64 -nolto

	if %errorlevel% NEQ 0 (
		echo ========================================================================
		echo Error at exporting test project. Aborting...
		cd tools\auto_build
		pause
		exit 1)


	call "%cd%/extras/demo_project/Binaries/batchCompile.bat"

	if %errorlevel% NEQ 0 (
		echo ========================================================================
		echo Error at compiling test project. Aborting...
		cd tools\auto_build
		pause
		exit 1)

	echo OK
)

cd tools\auto_build
echo OK