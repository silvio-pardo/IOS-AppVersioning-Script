#!/bin/bash
# by silvio-pardo
plistBuddy="/usr/libexec/PlistBuddy"
echo "GitFlow versioning XcodeProject using git repo."
echo "Pattern: Major.Minor.Patch.Build.BranchTag"
echo "For more info start the script with -h or --help"
# Parse input variables and update settings.
for i in "$@"; do
case $i in
    -h|--help)
    echo "usage: sh version-update.sh [options...]\n"
    echo "    --build=<number>          Apply the given value to the build number (CFBundleVersion) for the project."
    echo "-i, --ignore-changes          Ignore git status when iterating build number (doesn't apply to manual values or --reflect-commits)."
    echo "-p, --plist=<path>            Use the specified plist file as the source of truth for version details."
    echo "    --reflect-commits         Reflect the number of commits in the current branch when preparing build numbers."
    echo "    --version=<number>        Apply the given value to the marketing version (CFBundleShortVersionString) for the project."
    echo "-x, --xcodeproj=<path>        Use the specified Xcode project file to gather plist names."
    exit 1
    ;;
    --reflect-commits)
    reflect_commits=true
    shift
    ;;
    -x=*|--xcodeproj=*)
    xcodeproj="${i#*=}"
    shift
    ;;
    -p=*|--plist=*)
    plist="${i#*=}"
    shift
    ;;
    --build=*)
    specified_build="${i#*=}"
    shift
    ;;
    --version=*)
    specified_version="${i#*=}"
    shift
    ;;
    -i|--ignore-changes)
    ignore_git_status=true
    shift
    ;;
    *)
    ;;
esac
done

# Locate the xcodeproj.
if [[ -z ${xcodeproj} ]]; then
    xcodeproj=$(find . -depth 1 -name "*.xcodeproj" | sed -e 's/^\.\///g')
fi

# Check that the xcodeproj file we've located is valid, and warn if it isn't.
# use the "--xcodeproj" variable to provide an accurate location.
if [[ ! -f "${xcodeproj}/project.pbxproj" ]]; then
    echo "${BASH_SOURCE}:${LINENO}: error: Could not locate the xcodeproj file \"${xcodeproj}\"."
    exit 1
else
    echo "Xcode Project: \"${xcodeproj}\""
fi

# Find unique references to Info.plist files in the project
projectFile="${xcodeproj}/project.pbxproj"
plists=$(grep "^\s*INFOPLIST_FILE.*$" "${projectFile}" | sed -Ee 's/^[[:space:]]+INFOPLIST_FILE[[:space:]*=[[:space:]]*["]?([^"]+)["]?;$/\1/g' | sort | uniq)

# Attempt to guess the plist based on the list we have.
# If we've specified a plist above, we'll simply use that instead.
if [[ -z ${plist} ]]; then
    read -r plist <<< "${plists}"
fi

# Check that the plist file we've located is valid, and warn if it isn't.
# This could also indicate an issue with the code used to match plist files in the xcodeproj file.
# If you're encountering this and the file exists, ensure that ${plists} contains _ONLY_ filenames.
if [[ ! -f ${plist} ]]; then
    echo "${BASH_SOURCE}:${LINENO}: error: Could not locate the plist file \"${plist}\"."
    exit 1
else
    echo "Source Info.plist: \"${plist}\""
fi

# Update all of the Info.plist files we discovered
while read -r thisPlist; do
    # Check if in file exist the variable
    if [[ "$("${plistBuddy}" -c "Print CFBundleVersion" "${thisPlist}")" == "" ]]; then
        echo "${BASH_SOURCE}:${LINENO}: error: Could not locate the variable 'CFBundleVersion' in plist file \"${thisPlist}\"."
        echo "check if the file contains all env variables used by the script"
        exit 1
    fi
    if [[ "$("${plistBuddy}" -c "Print BundleVersionMajor" "${thisPlist}")" == "" ]]; then
        echo "${BASH_SOURCE}:${LINENO}: error: Could not locate the variable 'BundleVersionMajor' in plist file \"${thisPlist}\"."
        echo "check if the file contains all env variables used by the script"
        exit 1
    fi
    # Find out the current version
    thisBundleVersion=$("${plistBuddy}" -c "Print CFBundleVersion" "${thisPlist}")
    thisBundleShortVersionString=$("${plistBuddy}" -c "Print CFBundleShortVersionString" "${thisPlist}")
    # index versioning from selected info.plist
    thisBundleVersionMajor=$("${plistBuddy}" -c "Print BundleVersionMajor" "${thisPlist}")
    thisBundleVersionMinor=$("${plistBuddy}" -c "Print BundleVersionMinor" "${thisPlist}")
    thisBundleVersionPatch=$("${plistBuddy}" -c "Print BundleVersionPatch" "${thisPlist}")
    thisBundleVersionBuild=$("${plistBuddy}" -c "Print BundleVersionBuild" "${thisPlist}")
    # setting variable equal for prevent uncorrect override
    mainBundleVersion=${thisBundleVersion}
    mainBundleShortVersionString=${thisBundleShortVersionString}
    mainBundleVersionMajor=${thisBundleVersionMajor}
    mainBundleVersionMinor=${thisBundleVersionMinor}
    mainBundleVersionPatch=${thisBundleVersionPatch}
    mainBundleVersionBuild=${thisBundleVersionBuild}
    # start checking versioning value for changes
    if [[ ! -z ${specified_build} ]]; then
        # the user specified a base build version (via "--build"), override from info.plist
        mainBundleVersion=${specified_build}
        echo "Applying specified build version (${specified_build})..."
    elif
        # the user specified a marketing version (via "--version")
        [[ ! -z ${specified_version} ]]; then
        mainBundleShortVersionString=${specified_version}
        echo "Applying specified marketing version (${specified_version})..."
    else
        # Create the next value for bundle from non specified value
        git=$(sh /etc/profile; which git)
        branchName=$("${git}" rev-parse --abbrev-ref HEAD)
        if [[ -z ${enable_for_branch} ]] || [[ ",${enable_for_branch}," == *",${branchName},"* ]]; then
            if [[ ! -z ${reflect_commits} ]] && [[ ${reflect_commits} ]]; then
                #add in counter version build
                if [[ ! -z ${ignore_git_status} ]] && [[ ${ignore_git_status} ]]; then
                    echo "Iterating build number (not from git)..."
                    mainBundleVersionBuild=$((${thisBundleVersionBuild} + 1))
                else
                    mainBundleVersionBuild=$("${git}" rev-list --count HEAD)
                fi
                #git flow versioning
                mainBundleTag=""
                if [[ ${branchName} =~ "main" ]]; then
                    mainBundleVersionMajor=$((${thisBundleVersionMajor} + 1))
                fi
                if [[ ${branchName} =~ "develop" ]]; then
                    mainBundleTag="-${branchName}"
                fi
                if [[ ${branchName} =~ "feature" ]]; then
                    mainBundleVersionMinor=$((${thisBundleVersionMinor} + 1))
                    mainBundleTag="-${branchName}"
                fi
                if [[ ${branchName} =~ "hotfix" ]]; then
                    mainBundleVersionPatch=$((${thisBundleVersionPatch} + 1))
                    mainBundleTag="-${branchName}"
                fi
                if [[ ${branchName} =~ "quality" ]]; then
                    mainBundleTag="-${branchName}"
                fi
                # Create the Bundle and Marketing version
                mainBundleVersion="${mainBundleVersionMajor}.${mainBundleVersionMinor}.${mainBundleVersionPatch}.${mainBundleVersionBuild}${mainBundleTag}"
                mainBundleShortVersionString="${mainBundleVersionMajor}.${mainBundleVersionMinor}.${mainBundleVersionPatch}"
                if [[ ${currentBundleVersion} != ${mainBundleVersion} ]]; then
                    echo "Branch \"${branchName}\" has ${mainBundleVersion} commit(s). Updating build number..."
                else
                    echo "Branch \"${branchName}\" has ${mainBundleVersion} commit(s). Version is stable."
                fi
            else
                status=$("${git}" status --porcelain)
                if [[ ${#status} == 0 ]]; then
                    echo "Repository does not have any changes. Version is stable."
                elif [[ ${status} == *"M ${plist}"* ]] || [[ ${status} == *"M \"${plist}\""* ]]; then
                    echo "The source Info.plist has been modified. Version is assumed to be stable. Use --ignore-changes to override."
                else
                    echo "Repository is dirty!"
                fi
            fi
        else
            echo "Version number updates are disabled for the current git branch (${branchName})."
        fi
    fi
    # Update the CFBundleVersion if needed
    if [[ ${thisBundleVersion} != ${mainBundleVersion} ]]; then
        echo "Updating \"${thisPlist}\" with build ${mainBundleVersion}..."
        "${plistBuddy}" -c "Set :CFBundleVersion ${mainBundleVersion}" "${thisPlist}"
    fi
    # Update the CFBundleShortVersionString if needed
    if [[ ${thisBundleShortVersionString} != ${mainBundleShortVersionString} ]]; then
        echo "Updating \"${thisPlist}\" with marketing version ${mainBundleShortVersionString}..."
        "${plistBuddy}" -c "Set :CFBundleShortVersionString ${mainBundleShortVersionString}" "${thisPlist}"
    fi
    # Update the BundleVersionMajor if needed
    if [[ ${thisBundleVersionMajor} != ${mainBundleVersionMajor} ]]; then
        echo "Updating \"${thisPlist}\" with bundle version major..."
        "${plistBuddy}" -c "Set :BundleVersionMajor ${mainBundleVersionMajor}" "${thisPlist}"
    fi
    # Update the BundleVersionMinor if needed
    if [[ ${thisBundleVersionMinor} != ${mainBundleVersionMinor} ]]; then
        echo "Updating \"${thisPlist}\" with bundle version minor..."
        "${plistBuddy}" -c "Set :BundleVersionMinor ${mainBundleVersionMinor}" "${thisPlist}"
    fi
    # Update the BundleVersionPatch if needed
    if [[ ${thisBundleVersionPatch} != ${mainBundleVersionPatch} ]]; then
        echo "Updating \"${thisPlist}\" with bundle version patch..."
        "${plistBuddy}" -c "Set :BundleVersionPatch ${mainBundleVersionPatch}" "${thisPlist}"
    fi
    # Update the BundleVersionBuild if needed
    if [[ ${thisBundleVersionBuild} != ${mainBundleVersionBuild} ]]; then
        echo "Updating \"${thisPlist}\" with bundle version build..."
        "${plistBuddy}" -c "Set :BundleVersionBuild ${mainBundleVersionBuild}" "${thisPlist}"
    fi
done <<< "${plists}"
