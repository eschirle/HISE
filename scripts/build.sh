#!/bin/bash

# STAGE 1: Configuration ==========================================================================
# Change these values for your project

# Parse the project name from project_info.xml
project_name=$(grep '<Name value=' project_info.xml | sed 's/.*<Name value="\([^"]*\)".*/\1/' | head -1)
if [ -z "$project_name" ]; then
	project_name="${PROJECT_NAME}"  # Default fallback
fi

# Search for XML file in XmlPresetBackups folder, default to Preset.xml
if [ -f "XmlPresetBackups/Preset.xml" ]; then
	xml_name="Preset.xml"
else
	# Find the first XML file in XmlPresetBackups folder
	xml_file=$(find XmlPresetBackups -maxdepth 1 -name "*.xml" -type f | head -1)
	if [ -n "$xml_file" ]; then
		xml_name=$(basename "$xml_file")
	else
		xml_name="Preset.xml"  # Default fallback
	fi
fi


# This is the folder of the HISE source code
hisepath="./HISE"

# Set the plugin formats you want to compile
plugin_formats=VST3

# Set the plugin type (instrument or effect)
plugin_type=instrument

# STAGE 2: Setup ===================================================================================

# create path variables
project_folder="$PWD"
# hise_binary="$hisepath/projects/standalone/Builds/MacOSX/build/Release/HISE.app/Contents/MacOS/HISE"
mp_binary="$hisepath/tools/multipagecreator/Builds/MacOSX/build/Release/multipagecreator.app/Contents/MacOS/multipagecreator"
au_project=$project_folder/Binaries/Builds/MacOSX/build/Release/$project_name.component
vst3_project=$project_folder/Binaries/Builds/MacOSX/build/Release/$project_name.vst3
installer_binary="$project_folder/Installer/$project_name Installer.app"

# Check if the HISE binary exists in Release, CI, or Minimal Build folders
hise_found=false
possible_folders=("Release" "CI" "Minimal Build")

for folder in "${possible_folders[@]}"; do
	candidate_binary="$hisepath/projects/standalone/Builds/MacOSX/build/$folder/HISE.app/Contents/MacOS/HISE"
	if [ -f "$candidate_binary" ]; then
		hise_binary="$candidate_binary"
		echo "Found HISE binary at $hise_binary"
		hise_found=true
		break
	fi
done

if [ "$hise_found" = false ]; then
	echo "HISE binary not found in any of the expected locations:"
	for folder in "${possible_folders[@]}"; do
		echo "  - $hisepath/projects/standalone/Builds/MacOSX/build/$folder/HISE.app/Contents/MacOS/HISE"
	done
	echo "Please build HISE first."
	exit 1
fi



# CODESIGNING PREPARATION
# Fetch the codesigning IDs from the local keychain

# echo Write team development ID
# echo Fetching Apple Code Signing ID
# echo If this fails, you need to add your certificate as $USER keychain password with the ID dev_certificate_id
# APPLE_CERTIFICATE_ID=$(security find-generic-password -a "$USER" -s "dev_certificate_id" -w)
# echo The certificate was found: $APPLE_CERTIFICATE_ID
# echo Fetching Apple Installer Code Signing ID
# echo If this fails, you need to add your installer certificate as $USER keychain password with the ID dev_installer_id
# APPLE_CERTIFICATE_ID_INSTALLER=$(security find-generic-password -a "$USER" -s "dev_installer_id" -w)
# echo The installer certificate was found: $APPLE_CERTIFICATE_ID_INSTALLER

# regex the actual team ID
# [[ $APPLE_CERTIFICATE_ID_INSTALLER =~ .*\((.*)\) ]] && team_id=${BASH_REMATCH[1]}

# echo The team ID is: $team_id

# echo Fetching App specific password for notarizing
# echo If this fails, you need to create an app specific password in iCloud and add it as $USER keychain password with the ID notarize_app_password

# notarize_app_password=$(security find-generic-password -a "$USER" -s "notarize_app_password" -w)

# echo $notarize_app_password

# STAGE 3: Build the plugin =================================================================

chmod +x "$hisepath/tools/Projucer/Projucer.app/Contents/MacOS/Projucer"

$hise_binary set_project_folder -p:"$project_folder"

$hise_binary export_ci "XmlPresetBackups/$xml_name" -t:$plugin_type -a:x64 -p:$plugin_formats

"$project_folder/Binaries/batchCompileOSX"

if [ $? != 0 ];
then
	echo "========================================================================"
	echo "Error at project export. Aborting..."
    exit 1
fi

echo "OK"

# Find the Installer json files - they are not where expected

ls -la

echo "Checking for Binaries output"

cd Binaries/Builds/MacOSX
ls -la

# Code for exporting / building an installer
"$mp_binary" --export:"$project_folder/Installer/installer.json" --hisepath:"$hisepath" --teamid:$team_id
chmod +x "$project_folder/Installer/Binaries/batchCompileOSX"
"$project_folder/Installer/Binaries/batchCompileOSX"

# STAGE 4: Codesigning =============================================================================

# echo "Code signing"

# echo "Signing VST & AU"
# codesign --deep --force --options runtime -s "$APPLE_CERTIFICATE_ID" "$au_project" --timestamp
# codesign -dv --verbose=4 "$au_project"
# codesign --deep --force --options runtime -s "$APPLE_CERTIFICATE_ID" "$vst3_project" --timestamp
# codesign -dv --verbose=4 "$vst3_project"

# echo "Signing Installer"

# codesign --deep --force --options runtime -s "$APPLE_CERTIFICATE_ID" "$installer_binary" --timestamp
# codesign -dv --verbose=4 "$installer_binary"

# DONE. Open DMG Canvas and build & notarize the image in there...