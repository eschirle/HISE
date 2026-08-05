@echo off

REM Parse command-line arguments
setlocal enabledelayedexpansion
set SKIP_TESTS_AND_EXPORT=false
set USE_IPP=false
set BUILD_CONFIG=CI

:parse_args
if "%~1"=="" goto end_parse
if /I "%~1"=="--skip-tests-and-export" (
	set SKIP_TESTS_AND_EXPORT=true
	shift
	goto parse_args
)
if /I "%~1"=="--use-ipp" (
	set USE_IPP=true
	shift
	goto parse_args
)
if /I "%~1:~0,10%"=="--use-ipp=" (
	set USE_IPP=%~1:~10%
	shift
	goto parse_args
)
if "%BUILD_CONFIG%"=="CI" (
	set BUILD_CONFIG=%~1
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

REM This is the local folder where the DMG images are created.
SET nightly_build_folder="D:\Development\Installer\Windows\nightly_builds"

REM This is the project folder for the Standalone app
SET standalone_project="projects\standalone\Builds\VisualStudio2026\HISE Standalone.sln"

SET projucerPath="JUCE\projucer\Projucer.exe"

SET standalone_projucer_project="projects\standalone\HISE Standalone.jucer"

SET plugin_projucer_project="projects\plugin\HISE.jucer"

SET multipagecreator_projucer_project="tools\multipagecreator\multipagecreator.jucer"

SET hise_ci="projects\standalone\Builds\VisualStudio2026\x64\CI\App\HISE.exe"

SET multipagecreator_project="tools\multipagecreator\Builds\VisualStudio2026\multipagecreator.sln"

set multipage_binary="tools\multipagecreator\Builds\VisualStudio2026\x64\Release\App\multipagecreator.exe"

REM This is the project folder of the plugin project
SET plugin_project="projects\plugin\Builds\VisualStudio2026\HISE.sln"

REM This is the path to the ISS Installer compiler
SET installer_command="C:\Program Files (x86)\Inno Setup 6\ISCC.exe"

cd..
cd..

cd tools/SDK

tar -xf sdk.zip

cd ..
cd ..

if /I "%USE_IPP%"=="true" (
    :: 1. Define the path where the GitHub Actions step installed IPP
    SET IPP_PATH="C:\Program Files (x86)\Intel\oneAPI\ipp\latest"

    :: 2. Set the Global Search Path in Projucer for 'ipp'
    echo Configuring Projucer IPP path...
    %projucerPath% --set-global-search-path windows ipp %IPP_PATH%

    %projucerPath% --resave %plugin_projucer_project%

	@echo off
	setlocal enabledelayedexpansion

	echo [1/4] Installing Intel IPP via pip...
	pip install ipp-static ipp-include ipp-devel
	if %ERRORLEVEL% neq 0 (
		echo ❌ Pip installation failed! Exiting.
		pause
		exit /b %ERRORLEVEL%
	)

	echo.
	echo [2/4] Querying exact pip library paths...
	for /f "delims=" %%i in ('python -c "import ipp_include; print(ipp_include.get_include().replace('\\', '\\\\'))"') do set "IPP_INCLUDE=%%i"
	for /f "delims=" %%i in ('python -c "import ipp_static; print(ipp_static.get_lib().replace('\\', '\\\\'))"') do set "IPP_STATIC=%%i"

	echo Found Headers: %IPP_INCLUDE%
	echo Found Libraries: %IPP_STATIC%

	echo.
	echo [3/4] Injecting paths and flags into .jucer XML file...
	:: Inline python to inject configurations into the XML structure securely
	python -c "
	import xml.etree.ElementTree as ET
	import os

	jucer_path = r'%plugin_projucer_project%'
	if not os.path.exists(jucer_path):
		print(f'❌ Error: {jucer_path} not found!')
		exit(1)

	tree = ET.parse(jucer_path)
	root = tree.getroot()

	# Locate the VS Exporter (VS2022, VS2019, etc.)
	for exporter in root.iter('VS2022'): # Change to VS2019 if using older VS
		# Set Paths
		exporter.set('headerPath', r'%IPP_INCLUDE%')
		exporter.set('libraryPath', r'%IPP_STATIC%')
		
		# Inject libraries to link
		libs = 'ippcoremt.lib\nippsmt.lib\nippvfmt.lib\nippimt.lib'
		exporter.set('externalLibraries', libs)
		
		# Inject Preprocessor Define
		existing_defs = exporter.get('extraCompilerFlags', '')
		if 'HISE_USE_IPP=1' not in existing_defs:
			# Also ensure HISE_USE_IPP=1 is in the preprocessor block
			for config in exporter.findall('.//CONFIGURATION'):
				defs = config.get('defines', '')
				if 'HISE_USE_IPP=1' not in defs:
					config.set('defines', (defs + ';HISE_USE_IPP=1').strip(';'))

	tree.write(jucer_path, encoding='utf-8', xml_declaration=True)
	print('✓ Successfully updated .jucer XML file.')
	"
	if %ERRORLEVEL% neq 0 (
		echo ❌ XML processing failed! Exiting.
		pause
		exit /b %ERRORLEVEL%
	)

	echo.
	echo [4/4] Forcing Projucer to regenerate Visual Studio Solution files...
	"%projucerPath%" --resave "%plugin_projucer_project%"
	if %ERRORLEVEL% neq 0 (
		echo ❌ Projucer failed to resave project!
		pause
		exit /b %ERRORLEVEL%
	)

	echo.
	echo 🎉 SUCCESS! Your HISE VST project is completely configured with pip-installed IPP.
) else (
    echo Skipping IPP configuration and project resave because USE_IPP is not true.
)

REM ===========================================================
REM Compiling

echo Compiling 64bit VST Plugins

set Platform=X64

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

"!MSBUILD_EXE!" %standalone_project% /t:Build /p:Configuration=%BUILD_CONFIG%;Platform=x64;PlatformToolset=v143 /v:m
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

	SET hise_ci="projects\standalone\Builds\VisualStudio2017\x64\%BUILD_CONFIG%\App\HISE.exe"

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