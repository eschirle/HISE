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

call ConfigWindows.bat

cd..
cd..

cd tools/SDK

tar -xf sdk.zip

cd ..
cd ..


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

"C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MsBuild.exe" %standalone_project% /t:Build /p:Configuration="%BUILD_CONFIG%";Platform=x64 /v:m

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