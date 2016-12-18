#!/usr/bin/env bash

# Caution is a virtue.
set -o nounset
set -o errtrace
set -o errexit
set -o pipefail

# ## Global Variables

# The ievms version.
ievms_version="0.3.1"

# Options passed to each `curl` command.
curl_opts=${CURL_OPTS:-""}

# Reuse XP virtual machines for IE versions that are supported.
reuse_xp=${REUSE_XP:-"yes"}

# Reuse Win7 virtual machines for IE versions that are supported.
reuse_win7=${REUSE_WIN7:-"yes"}

# Timeout interval to wait between checks for various states.
sleep_wait="5"

# Store the original `cwd`.
orig_cwd=`pwd`

# The VM user to use for guest control.
guest_user="IEUser"

# The VM user password to use for guest control.
guest_pass="Passw0rd!"

# ## Utilities

# Print a message to the console.
log()  { printf '%s\n' "$*" ; return $? ; }

# Print an error message to the console and bail out of the script.
fail() { log "\nERROR: $*\n" ; exit 1 ; }

check_md5() {
    local md5

    case $kernel in
        Darwin) md5=`md5 "${1}" | rev | cut -c-32 | rev` ;;
        Linux) md5=`md5sum "${1}" | cut -c-32` ;;
    esac

    if [ "${md5}" != "${2}" ]
    then
        log "MD5 check failed for ${1} (wanted ${2}, got ${md5})"
        return 1
    fi

    log "MD5 check succeeded for ${1}"
}

# Download a URL to a local file. Accepts a name, URL and file.
download() { # name url path md5
    local attempt=${5:-"0"}
    local max=${6:-"3"}

    let attempt+=1

    if [[ -f "${3}" ]]
    then
        log "Found ${1} at ${3} - skipping download"
        check_md5 "${3}" "${4}" && return 0
        log "Check failed - redownloading ${1}"
        rm -f "${3}"
    fi

    log "Downloading ${1} from ${2} to ${3} (attempt ${attempt} of ${max})"
    curl ${curl_opts} -L "${2}" -o "${3}" || fail "Failed to download ${2} to ${ievms_home}/${3} using 'curl', error code ($?)"
    check_md5 "${3}" "${4}" && return 0

    if [ "${attempt}" == "${max}" ]
    then
        echo "Failed to download ${2} to ${ievms_home}/${3} (attempt ${attempt} of ${max})"
        return 1
    fi

    log "Redownloading ${1}"
    download "${1}" "${2}" "${3}" "${4}" "${attempt}" "${max}"
}

# ## General Setup

# Create the ievms home folder and `cd` into it. The `INSTALL_PATH` env variable
# is used to determine the full path. The home folder is then added to `PATH`.
create_home() {
    local def_ievms_home="${HOME}/.ievms"
    ievms_home=${INSTALL_PATH:-$def_ievms_home}

    mkdir -p "${ievms_home}"
    cd "${ievms_home}"

    PATH="${PATH}:${ievms_home}"

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
    hash VBoxManage 2>&- || fail "VirtualBox command line utilities are not installed, please (re)install! (http://virtualbox.org)"
}

# Determine the VirtualBox version details, querying the download page to ensure
# validity.
check_version() {
    local version=`VBoxManage -v`
    major_minor_release="${version%%[-_r]*}"
    local major_minor="${version%.*}"
    local dl_page=`curl ${curl_opts} -L "http://download.virtualbox.org/virtualbox/" 2>/dev/null`

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
            log "Virtualbox version ${major_minor_release} not found, skipping."
        fi
    done
}

# Check for the VirtualBox Extension Pack and install if not found.
check_ext_pack() {
    log "Checking for Oracle VM VirtualBox Extension Pack"
    if ! VBoxManage list extpacks | grep "Oracle VM VirtualBox Extension Pack"
    then
        local archive="Oracle_VM_VirtualBox_Extension_Pack-${major_minor_release}.vbox-extpack"
        local url="http://download.virtualbox.org/virtualbox/${major_minor_release}/${archive}"
        local md5s="https://www.virtualbox.org/download/hashes/${major_minor_release}/MD5SUMS"
        local md5=`curl ${curl_opts} -L "${md5s}" | grep "${archive}" | cut -c-32`

        download "Oracle VM VirtualBox Extension Pack" "${url}" "${archive}" "${md5}"

        log "Installing Oracle VM VirtualBox Extension Pack from ${ievms_home}/${archive}"
        VBoxManage extpack install "${archive}" || fail "Failed to install Oracle VM VirtualBox Extension Pack from ${ievms_home}/${archive}, error code ($?)"
    fi
}

# Download and install `unar` from Google Code.
install_unar() {
    local url="http://unarchiver.c3.cx/downloads/unar1.10.1.zip"
    local archive=`basename "${url}"`

    download "unar" "${url}" "${archive}" "d548661e4b6c33512074df81e39ed874"

    unzip "${archive}" || fail "Failed to extract ${ievms_home}/${archive} to ${ievms_home}/, unzip command returned error code $?"

    hash unar 2>&- || fail "Could not find unar in ${ievms_home}"
}

# Check for the `unar` command, downloading and installing it if not found.
check_unar() {
    if [ "${kernel}" == "Darwin" ]
    then
        hash unar 2>&- || install_unar
    else
        hash unar 2>&- || fail "Linux support requires unar (sudo apt-get install for Ubuntu/Debian)"
    fi
}

# Pause execution until the virtual machine with a given name shuts down.
wait_for_shutdown() {
    while true ; do
        log "Waiting for ${1} to shutdown..."
        sleep "${sleep_wait}"
        VBoxManage showvminfo "${1}" | grep "State:" | grep -q "powered off" && return 0 || true
    done
}

# Pause execution until guest control is available for a virtual machine.
wait_for_guestcontrol() {
    while true ; do
        log "Waiting for ${1} to be available for guestcontrol..."
        sleep "${sleep_wait}"
        VBoxManage showvminfo "${1}" | grep 'Additions run level:' | grep -q "3" && return 0 || true
    done
}

# Find or download the ievms control ISO.
find_iso() {
    local url="https://dl.dropboxusercontent.com/u/463624/ievms-control-${ievms_version}.iso"
    local url_bak="https://www.dropbox.com/s/uvgmy7t0phf8lui/ievms-control-${ievms_version}.iso?dl=0"
    local dev_iso="${orig_cwd}/ievms-control.iso" # Use local iso if in ievms dev root
    if [[ -f "${dev_iso}" ]]
    then
        iso=$dev_iso
    else
        iso="${ievms_home}/ievms-control-${ievms_version}.iso"
        download "ievms control ISO" "${url}" "${iso}" "6699cb421fc2f56e854fd3f5e143e84c"
        result=$?
        if [ result != 0 ]
        then
            download "ievms control ISO (fallback url)" "${url_bak}" "${iso}" "6699cb421fc2f56e854fd3f5e143e84c"
        fi
    fi
}

# Find or download the Virtual Box Guest Additions ISO.
find_ga() {
    local dev_iso="VBoxGuestAdditions_${major_minor_release}.iso"
    local url="http://download.virtualbox.org/virtualbox/${major_minor_release}/${dev_iso}"
    ga_iso="${ievms_home}/${dev_iso}"
    download "VirtualBox Guest Additions ISO" "${url}" "${ga_iso}" "8cf1af35478905ea29828954ddb2c5ee"
}

# Attach a dvd image to the virtual machine.
attach() {
    log "Attaching ${3}"
    VBoxManage storageattach "${1}" --storagectl "IDE" --port 1 \
        --device 0 --type dvddrive --medium "${2}"
}

# Eject the dvd image from the virtual machine.
eject() {
    log "Ejecting ${2}"
    VBoxManage storageattach "${1}" --storagectl "IDE" --port 1 \
        --device 0 --medium none
}

# Boot the virtual machine with the control ISO in the dvd drive then wait for
# it to do its magic and shut down. For XP images, the "magic" is simply
# enabling guest control without a password. For other images, it installs
# a batch file that runs on first boot to install guest additions and activate
# the OS if possible.
boot_ievms() {
    find_iso
    attach "${1}" "${iso}" "ievms control ISO"
    start_vm "${1}"
    wait_for_shutdown "${1}"
    eject "${1}" "ievms control ISO"
}

# Boot the virtual machine with guest additions in the dvd drive. After running
# `boot_ievms`, the next boot will attempt automatically install guest additions
# if present in the drive. It will shut itself down after installation.
boot_auto_ga() {
    boot_ievms "${1}"
    find_ga
    attach "${1}" "${ga_iso}" "Guest Additions"
    start_vm "${1}"
    wait_for_shutdown "${1}"
    eject "${1}" "Guest Additions"
}

# Start a virtual machine in headless mode.
start_vm() {
    log "Starting VM ${1}"
    VBoxManage startvm "${1}" --type headless
}

# Copy a file to the virtual machine from the ievms home folder.
copy_to_vm() {
    log "Copying ${2} to ${3}"
    guest_control_exec "${1}" cmd.exe /c copy "D:\\${2}" "${3}"
}

# Execute a command with arguments on a virtual machine.
guest_control_exec() {
    local vm="${1}"
    local image="${2}"
    shift
    VBoxManage guestcontrol "${vm}" run \
        --username "${guest_user}" --password "${guest_pass}" \
        --exe "${image}" -- "$@"
}

# Start an XP virtual machine and set the password for the guest user.
set_xp_password() {
    start_vm "${1}"
    wait_for_guestcontrol "${1}"

    log "Setting ${guest_user} password"
    VBoxManage guestcontrol "${1}" run --username Administrator \
        --password "${guest_pass}" --exe "net.exe" -- \
        net.exe user "${guest_user}" "${guest_pass}"

    log "Setting auto logon password"
    VBoxManage guestcontrol "${1}" run --username Administrator \
        --password "${guest_pass}" --exe "reg.exe" -- reg.exe add \
        "HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon" \
        /f /v DefaultPassword /t REG_SZ /d "${guest_pass}"

    log "Enabling auto admin logon"
    VBoxManage guestcontrol "${1}" run --username Administrator \
        --password "${guest_pass}" --exe "reg.exe" -- reg.exe add \
        "HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon" \
        /f /v AutoAdminLogon /t REG_SZ /d 1
}

# Shutdown an XP virtual machine and wait for it to power off.
shutdown_xp() {
    log "Shutting down ${1}"
    guest_control_exec "${1}" "shutdown.exe" /s /f /t 0
    wait_for_shutdown "${1}"
}

# Install an alternative version of IE in an XP virtual machine. Downloads the
# installer, copies it to the vm, then runs it before shutting down.
install_ie_xp() { # vm url md5
    local src=`basename "${2}"`
    local dest="C:\\Documents and Settings\\${guest_user}\\Desktop\\${src}"

    download "${src}" "${2}" "${src}" "${3}"
    copy_to_vm "${1}" "${src}" "${dest}"

    log "Installing IE" # Always "fails"
    guest_control_exec "${1}" "${dest}" /passive /norestart || true

    shutdown_xp "${1}"
}

# Install an alternative version of IE in a Win7 virtual machine. Downloads the
# installer, copies it to the vm, then runs it before shutting down.
install_ie_win7() { # vm url md5
    local src=`basename "${2}"`
    local dest="C:\\Users\\${guest_user}\\Desktop\\${src}"

    download "${src}" "${2}" "${src}" "${3}"
    start_vm "${1}"
    wait_for_guestcontrol "${1}"
    copy_to_vm "${1}" "${src}" "${dest}"

    log "Installing IE"
    guest_control_exec "${1}" "cmd.exe" /c \
        "echo ${dest} /passive /norestart >C:\\Users\\${guest_user}\\ievms.bat"
    guest_control_exec "${1}" "cmd.exe" /c \
        "echo shutdown.exe /s /f /t 0 >>C:\\Users\\${guest_user}\\ievms.bat"
    guest_control_exec "${1}" "schtasks.exe" /run /tn ievms

    wait_for_shutdown "${1}"
}

# Build an ievms virtual machine given the IE version desired.
build_ievm() {
    unset archive
    unset unit
    local prefix="IE"
    local suffix=""
    local version="${1}"
    case $1 in
        8|9|10) os="Win7" ;;
        11)
            if [ "${reuse_win7}" != "yes" ]
            then
                os="Win8.1"
            else
                os="Win7"
            fi
            ;;
        EDGE)
            prefix="MS"
            version="Edge"
            os="Win10"
            unit="8"
            suffix="_preview"
            ;;
        *) fail "Invalid IE version: ${1}" ;;
    esac

    local vm="${prefix}${version} - ${os}"
    local def_archive="${vm/ - /_}.zip"
    archive=${archive:-$def_archive}
    unit=${unit:-"11"}
    local ova=`basename "${archive/_/ - }" .zip`"${suffix}".ova

    local url
    if [ "${os}" == "Win10" ]
    then
        url="https://az792536.vo.msecnd.net/vms/VMBuild_20160802/VirtualBox/MSEdge/MSEdge.Win10_RS1.VirtualBox.zip"
    else
        url="https://az412801.vo.msecnd.net/vhd/VMBuild_20141027/VirtualBox/IE${version}/Windows/IE${version}.${os}.For.Windows.VirtualBox.zip"
    fi

    local md5
    case $archive in
        IE8_Win7.zip) md5="86d481f517ca18d50f298fc9fb1c5a18" ;;
        IE9_Win7.zip) md5="61a2b69a5712abd6566fcbd1f44f7a2b" ;;
        IE10_Win7.zip) md5="755f05af1507cd8940354bf564a08d50" ;;
        IE11_Win7.zip) md5="7aa66ec15a51ee8b0a4ab39353472f07" ;;
        IE11_Win8.1.zip) md5="080c652c69359b6742de547ba594ab2a" ;;
        MSEdge_Win10.zip) md5="467d8286cb8cbed90f0761c3566abdda" ;;
    esac
    
    log "Checking for existing OVA at ${ievms_home}/${ova}"
    if [[ ! -f "${ova}" ]]
    then
        download "OVA ZIP" "${url}" "${archive}" "${md5}"

        log "Extracting OVA from ${ievms_home}/${archive}"
        unar "${archive}" || fail "Failed to extract ${archive} to ${ievms_home}/${ova}, unar command returned error code $?"
    fi

    log "Checking for existing ${vm} VM"
    if ! VBoxManage showvminfo "${vm}" >/dev/null 2>/dev/null
    then
        local disk_path="${ievms_home}/${vm}-disk1.vmdk"
        log "Creating ${vm} VM (disk: ${disk_path})"
        VBoxManage import "${ova}" --vsys 0 --vmname "${vm}" --unit "${unit}" --disk "${disk_path}"

        log "Adding shared folder"
        VBoxManage sharedfolder add "${vm}" --automount --name ievms \
            --hostpath "${ievms_home}"

        log "Building ${vm} VM"
        declare -F "build_ievm_ie${1}" && "build_ievm_ie${1}"

        log "Tagging VM with ievms version"
        VBoxManage setextradata "${vm}" "ievms" "{\"version\":\"${ievms_version}\"}"
        
        log "Creating clean snapshot"
        VBoxManage snapshot "${vm}" take clean --description "The initial VM state"
    fi
}

# Build the IE8 virtual machine, reusing the XP VM if requested (the default).
build_ievm_ie8() {
    boot_auto_ga "IE8 - Win7"
}

# Build the IE9 virtual machine.
build_ievm_ie9() {
    boot_auto_ga "IE9 - Win7"
}

# Build the IE10 virtual machine, reusing the Win7 VM if requested (the default).
build_ievm_ie10() {
    boot_auto_ga "IE10 - Win7"
}

# Build the IE11 virtual machine, reusing the Win7 VM always.
build_ievm_ie11() {
    if [ "${reuse_win7}" != "yes" ]
    then
        boot_auto_ga "IE11 - Win8.1"
    else
        boot_auto_ga "IE11 - Win7"
    fi
}

# ## Main Entry Point

# Run through all checks to get the host ready for installation.
check_system
create_home
check_virtualbox
check_version
check_ext_pack
check_unar

# Install each requested virtual machine sequentially.
all_versions="8 9 10 11 EDGE"
for ver in ${IEVMS_VERSIONS:-$all_versions}
do
    log "Building IE ${ver} VM"
    build_ievm $ver
done

# We made it!
log "Done!"
