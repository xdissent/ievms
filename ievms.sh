#!/usr/bin/env bash

# Caution is a virtue.
set -o nounset
set -o errtrace
set -o errexit
set -o pipefail

# ## Gobal Variables

# Options passed to each `curl` command.
curl_opts=${CURL_OPTS:-""}

# Reuse XP virtual machines for IE versions that are supported.
reuse_xp=${REUSE_XP:-"yes"}

# Reuse Win7 virtual machines for IE versions that are supported.
reuse_win7=${REUSE_WIN7:-"yes"}

# Timeout interval to wait between checks for various states.
sleep_wait="10"

# Store the original `cwd`.
orig_cwd=`pwd`

# ## Utilities

# Print a message to the console.
log()  { printf "$*\n" ; return $? ;  }

# Print an error message to the console and bail out of the script.
fail() { log "\nERROR: $*\n" ; exit 1 ; }

# ## General Setup

# Create the ievms home folder and `cd` into it. The `INSTALL_PATH` env variable
# is used to determine the full path.
create_home() {
    def_ievms_home="${HOME}/.ievms"
    ievms_home=${INSTALL_PATH:-$def_ievms_home}

    mkdir -p "${ievms_home}"
    cd "${ievms_home}"

    # Move ovas and zips from a very old installation into place.
    mv -f ./ova/IE*/IE*.{ova,zip} "${ievms_home}/" 2>/dev/null || true
}

# Check for a supported host system (Linux/OS X).
check_system() {
    kernel=`uname -s`
    case $kernel in
        Darwin|Linux) ;;
        *) fail "Sorry, $kernel is not supported." ;;
    esac
}

# Ensure VirtualBox is installed and `VBoxManage` is on the `PATH`.
check_virtualbox() {
    log "Checking for VirtualBox"
    hash VBoxManage 2>&- || fail "VirtualBox command line utilities are not installed, please reinstall! (http://virtualbox.org)"
}

# Determine the VirtualBox version details, querying the download page to ensure
# validity.
check_version() {
    version=`VBoxManage -v`
    major_minor_release="${version%%[-_r]*}"
    major_minor="${version%.*}"
    dl_page=`curl ${curl_opts} -L "http://download.virtualbox.org/virtualbox/" 2>/dev/null`

    if [[ "$version" == *"kernel module is not loaded"* ]]; then
        fail "$version"
    fi

    for (( release="${major_minor_release#*.*.}"; release >= 0; release-- ))
    do
        major_minor_release="${major_minor}.${release}"
        if echo $dl_page | grep "${major_minor_release}/" &>/dev/null
        then
            log "Virtualbox version ${major_minor_release} found."
            break
        else
            log "Virtualbox version ${major_minor_release} not found - skipping."
        fi
    done
}

# Check for the VirtualBox Extension Pack and install if not found.
check_ext_pack() {
    log "Checking for Oracle VM VirtualBox Extension Pack"
    if ! VBoxManage list extpacks | grep "Oracle VM VirtualBox Extension Pack"
    then
        check_version
        archive="Oracle_VM_VirtualBox_Extension_Pack-${major_minor_release}.vbox-extpack"
        url="http://download.virtualbox.org/virtualbox/${major_minor_release}/${archive}"

        if [[ ! -f "${archive}" ]]
        then
            log "Downloading Oracle VM VirtualBox Extension Pack from ${url} to ${ievms_home}/${archive}"
            if ! curl ${curl_opts} -L "${url}" -o "${archive}"
            then
                fail "Failed to download ${url} to ${ievms_home}/${archive} using 'curl', error code ($?)"
            fi
        fi

        log "Installing Oracle VM VirtualBox Extension Pack from ${ievms_home}/${archive}"
        if ! VBoxManage extpack install "${archive}"
        then
            fail "Failed to install Oracle VM VirtualBox Extension Pack from ${ievms_home}/${archive}, error code ($?)"
        fi
    fi
}

# Download `unar` from Google Code if required.
download_unar() {
    unar_url="http://theunarchiver.googlecode.com/files/unar1.5.zip"
    unar_archive=`basename "${unar_url}"`

    log "Downloading unar from ${unar_url} to ${ievms_home}/${unar_archive}"
    if [[ ! -f "${unar_archive}" ]] && ! curl ${curl_opts} -L "${unar_url}" -o "${unar_archive}"
    then
        fail "Failed to download ${unar_url} to ${ievms_home}/${unar_archive} using 'curl', error code ($?)"
    fi

    if ! unzip "${unar_archive}"
    then
        fail "Failed to extract ${ievms_home}/${unar_archive} to ${ievms_home}/," \
            "unzip command returned error code $?"
    fi

    hash unar 2>&- || fail "Could not find unar in ${ievms_home}"
}

# Check for the `unar` command, downloading and installing it if not found. Adds
# ievms home folder to the `PATH` if `unar` must be downloaded. 
check_unar() {
    if [ "${kernel}" == "Darwin" ]
    then
        PATH="${PATH}:${ievms_home}"
        hash unar 2>&- || download_unar
    else
        hash unar 2>&- || fail "Linux support requires unar (sudo apt-get install for Ubuntu/Debian)"
    fi
}

# Pause execution until the virtual machine with a given name shuts down.
wait_for_shutdown() {
    x="0" ; until [ "${x}" != "0" ]; do
        log "Waiting for ${1} to shutdown..."
        sleep "${sleep_wait}"
        VBoxManage list runningvms | grep "${1}" >/dev/null && x=$? || x=$?
    done
    sleep "${sleep_wait}" # Extra sleep for good measure.
}

# Pause execution until guest control is available for a virtual
wait_for_guestcontrol() {
    pass=${2:-""}
    x="1" ; until [ "${x}" == "0" ]; do
        log "Waiting for ${1} to be available for guestcontrol..."
        sleep "${sleep_wait}"
        VBoxManage guestcontrol "${1}" cp "/etc/passwd" "/" --username IEUser --password "${pass}" --dryrun && x=$? || x=$?
    done
    sleep "${sleep_wait}" # Extra sleep for good measure.
}

# Find or download the ievms control ISO.
find_iso() {
    iso_url="https://dl.dropbox.com/u/463624/ievms-control.iso"
    dev_iso="${orig_cwd}/ievms-control.iso" # Use local iso if in ievms dev root
    if [[ -f "${dev_iso}" ]]; then iso=$dev_iso; else iso="${ievms_home}/ievms-control.iso"; fi
    log "Downloading ievms ISO from ${iso_url}"
    if [[ ! -f "${iso}" ]] && ! curl ${curl_opts} -L "${iso_url}" -o "${iso}"
    then
        fail "Failed to download ${iso_url} to ${ievms_home}/${iso} using 'curl', error code ($?)"
    fi
}

boot_ievms() {
    find_iso
    log "Attaching ievms.iso"
    VBoxManage storageattach "${1}" --storagectl "IDE Controller" --port 1 --device 0 --type dvddrive --medium "${iso}"

    log "Starting VM ${1}"
    VBoxManage startvm "${1}" # --type headless

    wait_for_shutdown "${1}"

    log "Ejecting ievms.iso"
    VBoxManage modifyvm "${1}" --dvd none
}

boot_auto_ga() {
    boot_ievms "${1}"

    log "Attaching Guest Additions ISO"
    VBoxManage storageattach "${1}" --storagectl "IDE Controller" --port 1 --device 0 --type dvddrive --medium additions

    log "Starting VM ${1}"
    VBoxManage startvm "${1}" # --type headless

    wait_for_shutdown "${1}"

    log "Ejecting Guest Additions"
    VBoxManage modifyvm "${1}" --dvd none
}

install_ie() {
    pass=${4:-""}
    installer=`basename "${3}"`
    installer_host="${ievms_home}/${installer}"
    installer_guest="/Documents and Settings/IEUser/Desktop/Install IE${2}.exe"
    log "Downloading IE${2} installer from ${3}"
    if [[ ! -f "${installer}" ]] && ! curl ${curl_opts} -L "${3}" -o "${installer}"
    then
        fail "Failed to download ${url} to ${ievms_home}/${installer} using 'curl', error code ($?)"
    fi

    log "Starting VM ${1}"
    VBoxManage startvm "${1}" # --type headless

    wait_for_guestcontrol "${1}" "${pass}"

    log "Copying IE${2} installer to Desktop"
    VBoxManage guestcontrol "${1}" cp "${installer_host}" "${installer_guest}" --username IEUser --password "${pass}"

    log "Installing IE${2}" # Always "fails"
    VBoxManage guestcontrol "${1}" exec --image "${installer_guest}" --username IEUser --password "${pass}" --wait-exit -- /passive /norestart || true

    log "Shutting down VM ${1}"
    VBoxManage guestcontrol "${1}" exec --image "shutdown.exe" --username IEUser --password "${pass}" --wait-exit -- -s -f -t 0

    wait_for_shutdown "${1}"
}

# Build an ievms virtual machine given the IE version desired.
build_ievm() {
    unset archive
    unset unit
    case $1 in
        6|7|8)
            os="WinXP"
            if [ "${reuse_xp}" != "yes" ]
            then
                if [ "$1" == "7" ]; then os="Vista"; fi
                if [ "$1" == "8" ]; then os="Win7"; fi
            else
                archive="IE6_WinXP.zip"
                unit="10"
            fi
            ;;
        9) os="Win7" ;;
        10)
            if [ "${reuse_win7}" != "yes" ]
            then
                os="Win8"
            else
                os="Win7"
                archive="IE9_Win7.zip"
            fi
            ;;
        *) fail "Invalid IE version: ${1}" ;;
    esac

    vm="IE${1} - ${os}"
    def_archive="${vm/ - /_}.zip"
    archive=${archive:-$def_archive}
    unit=${unit:-"11"}
    ova=`basename "${archive/_/ - }" .zip`.ova
    url="http://virtualization.modern.ie/vhd/IEKitV1_Final/VirtualBox/OSX/${archive}"
    
    log "Checking for existing OVA at ${ievms_home}/${ova}"
    if [[ ! -f "${ova}" ]]
    then
        log "Downloading OVA ZIP from ${url} to ${ievms_home}/${archive}"
        if [[ ! -f "${archive}" ]] && ! curl ${curl_opts} -L -O "${url}"
        then
            fail "Failed to download ${url} to ${ievms_home}/ using 'curl', error code ($?)"
        fi

        log "Extracting OVA from ${ievms_home}/${archive}"
        if ! unar "${archive}"
        then
            fail "Failed to extract ${archive} to ${ievms_home}/${ova}," \
                "unar command returned error code $?"
        fi
    fi

    log "Checking for existing ${vm} VM"
    if ! VBoxManage showvminfo "${vm}" >/dev/null 2>/dev/null
    then
        disk_path="${ievms_home}/${vm}-disk1.vmdk"
        log "Creating ${vm} VM (disk: ${disk_path})"
        VBoxManage import "${ova}" --vsys 0 --vmname "${vm}" --unit "${unit}" --disk "${disk_path}"

        log "Building ${vm} VM"
        declare -F "build_ievm_ie${1}" && "build_ievm_ie${1}"
        
        log "Creating clean snapshot"
        VBoxManage snapshot "${vm}" take clean --description "The initial VM state"
    fi
}

# Build the IE6 virtual machine.
build_ievm_ie6() {
    boot_ievms "IE6 - WinXP"
}

# Build the IE7 virtual machine, reusing the XP VM if requested (the default).
build_ievm_ie7() {
    if [ "${reuse_xp}" != "yes" ]
    then
        boot_auto_ga "IE7 - Vista"
    else
        boot_ievms "IE7 - WinXP"
        install_ie "IE7 - WinXP" 7 "http://download.microsoft.com/download/3/8/8/38889dc1-848c-4bf2-8335-86c573ad86d9/IE7-WindowsXP-x86-enu.exe"
    fi
}

# Build the IE8 virtual machine, reusing the XP VM if requested (the default).
build_ievm_ie8() {
    if [ "${reuse_xp}" != "yes" ]
    then
        boot_auto_ga "IE8 - Win7"
    else
        boot_ievms "IE8 - WinXP"
        install_ie "IE8 - WinXP" 8 "http://download.microsoft.com/download/C/C/0/CC0BD555-33DD-411E-936B-73AC6F95AE11/IE8-WindowsXP-x86-ENU.exe"
    fi
}

# Build the IE9 virtual machine.
build_ievm_ie9() {
    boot_auto_ga "IE9 - Win7"
}

# Build the IE10 virtual machine, reusing the Win7 VM if requested (the default).
build_ievm_ie10() {
    if [ "${reuse_win7}" != "yes" ]
    then
        boot_auto_ga "IE10 - Win8"
    else
        boot_auto_ga "IE10 - Win7"
        install_ie "IE10 - Win7" 10 "http://download.microsoft.com/download/8/A/C/8AC7C482-BC74-492E-B978-7ED04900CEDE/IE10-Windows6.1-x86-en-us.exe" "Passw0rd!"
    fi
}

# ## Main Entry Point

# Run through all checks to get the host ready for installation.
check_system
create_home
check_virtualbox
check_ext_pack
check_unar

# Install each requested virtual machine sequentially.
all_versions="6 7 8 9 10"
for ver in ${IEVMS_VERSIONS:-$all_versions}
do
    log "Building IE${ver} VM"
    build_ievm $ver
done

# We made it!
log "Done!"
