@echo off

if "%1%"=="--help" (
echo HISE Build Script Windows
echo ================================================================================
echo build [--help] [--noaax]
echo.
echo This script can be used to build a project using the command line tool of HISE.
echo Options:
echo --help: shows this info
echo --noaax: deactivates AAX export. Use this for projects that can't use AAX format
echo.  
echo Requirements:
echo 1. You need to compile HISE and store the path to HISE.exe as `hise_path`
echo 2. You need to have the HISE SDK set correctly: `HISE set_hise_folder -p:PATH`
echo 3. You need to have the following tools installed: git, InnoSetup
echo.
echo Requirements for building AAX
echo If you want to build the AAX version, you need the Pace wraptool 4 and have
echo two additional batch files, aaxconfig.bat and aaxsign.bat in the project root
echo.
echo ================================================================================

goto :end
)

REM STAGE 1: Configuration ==========================================================

REM set this to 0 to skip the installer
set buildInstaller=1

REM set this to 1 in order to build AAX
set buildAAX=0

REM set this to the plugin architecture
set buildArch=-a:x64

REM set this to the release configuration type (Release, CI, or "Minimal Build")
set RELEASE_MODE=Release

REM Dynamically find the HISE binary based on RELEASE_MODE
setlocal enabledelayedexpansion
set "script_dir=%~dp0"
set "hise_base=!script_dir!HISE\projects\standalone\Builds\VisualStudio2026\x64"
set hise_path=

if "!RELEASE_MODE!"=="Release" (
  if exist "!hise_base!\Release\App\HISE.exe" set "hise_path=!hise_base!\Release\App\HISE.exe"
)
if "!RELEASE_MODE!"=="CI" (
  if exist "!hise_base!\CI\App\HISE.exe" set "hise_path=!hise_base!\CI\App\HISE.exe"
)
if "!RELEASE_MODE!"=="Minimal Build" (
  if exist "!hise_base!\Minimal Build\App\HISE.exe" set "hise_path=!hise_base!\Minimal Build\App\HISE.exe"
)

REM If not found with RELEASE_MODE, search for any available build
if not defined hise_path (
  if exist "!hise_base!\Release\App\HISE.exe" set "hise_path=!hise_base!\Release\App\HISE.exe"
)
if not defined hise_path (
  if exist "!hise_base!\CI\App\HISE.exe" set "hise_path=!hise_base!\CI\App\HISE.exe"
)
if not defined hise_path (
  if exist "!hise_base!\Minimal Build\App\HISE.exe" set "hise_path=!hise_base!\Minimal Build\App\HISE.exe"
)

if not defined hise_path (
  echo ERROR: HISE binary not found in any of the expected locations:
  echo   - !hise_base!\Release\App\HISE.exe
  echo   - !hise_base!\CI\App\HISE.exe
  echo   - !hise_base!\Minimal Build\App\HISE.exe
  echo Please build HISE first in the same directory as this script.
  exit /b 1
)

echo Found HISE binary at: !hise_path!

REM set this to the plugin type (-t:instrument or -t:effect)
set project_type=-t:instrument

REM set this to the architecture -p:VST3 / -p:VST2 / -p:VST23AU
set plugin_format=-p:VST3

REM Parse the project name from project_info.xml
for /f "delims=" %%A in ('findstr "<Name value=" project_info.xml') do (
  for /f "tokens=2 delims=^"" %%B in ("%%A") do (
    set plugin_name=%%B
    goto :name_found
  )
)
if not defined plugin_name set plugin_name=Dyes Tonguewuhh
:name_found

REM Set this to 1 if you want to build the standalone app
set buildStandalone=0

REM Search for XML file in XmlPresetBackups folder, default to Preset.xml
if exist "XmlPresetBackups\Preset.xml" (
  set plugin_project_path=XmlPresetBackups/Preset.xml
) else (
  for /f %%F in ('dir /b XmlPresetBackups\*.xml 2^>nul') do (
    set plugin_project_path=XmlPresetBackups/%%F
    goto :xml_found
  )
  set plugin_project_path=XmlPresetBackups/Preset.xml
)
:xml_found


REM STAGE 2: Building ==========================================================

set installer_command="C:\Program Files (x86)\Inno Setup 6\ISCC.exe"

if "%1%"=="--noaax" set buildAAX=0

:VariableCheck
echo Checking Environment variables
REM  ====================================================================================

if %buildAAX%==1 (
  echo Building AAX plugins is enabled.
  echo Checking AAX Configuration before compiling
  call aaxconfig.bat
) 

if not defined hise_path (
  set hise_path="C:\HISE\projects\standalone\Builds\VisualStudio2026\x64\Release\App\HISE.exe"
)

REM Don't check the installer if not required...
if "%buildInstaller%"==0 (
  goto :BuildProject
)

if not defined installer_command (
   echo ERROR: The path to the Innosetup tool is not set: `installer_command`
   exit /b 1
)

:BuildProject
echo Building Binaries...
REM  ====================================================================================

echo Setting project folder
!hise_path! set_project_folder "-p:%~dp0"

!hise_path! clean --all

if %buildAAX%==1 (
  echo Exporting %plugin_name% AAX Plugins
  !hise_path! clean 
  !hise_path! export_ci %plugin_project_path% %project_type% -p:AAX %buildArch%
  call Binaries/batchCompile.bat
)

if %buildStandalone%==1 (
  echo Exporting %plugin_name% Standalone
  !hise_path! clean 
  !hise_path! export_ci %plugin_project_path% -t:standalone %buildArch%
  call Binaries/batchCompile.bat
)

echo Exporting %plugin_name% VST Plugin
!hise_path! clean
!hise_path! export_ci %plugin_project_path% %project_type% %plugin_format% %buildArch%
call Binaries/batchCompile.bat

:CopyFiles
echo Copying files
REM  ====================================================================================

:SignAAX
echo Signing AAX plugins
REM  ====================================================================================

if %buildAAX%==1 (
  call aaxsign.bat
)

:BuildInstaller
echo Building installer
REM  ====================================================================================

if %buildInstaller%==0 (
   echo Skipping Installer
   goto :EOF
)


:end
