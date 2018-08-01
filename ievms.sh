#!/usr/bin/env bash

# Caution is a virtue.
set -o nounset
set -o errtrace
set -o errexit
set -o pipefail

# ## Global Variables

# The ievms version.
ievms_version="0.3.3"

# Options passed to each `curl` command.
curl_opts=${CURL_OPTS:-""}

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
        check_version
        local archive="Oracle_VM_VirtualBox_Extension_Pack-${major_minor_release}.vbox-extpack"
        local url="http://download.virtualbox.org/virtualbox/${major_minor_release}/${archive}"
        local md5s="https://www.virtualbox.org/download/hashes/${major_minor_release}/MD5SUMS"
        local md5=`curl ${curl_opts} -L "${md5s}" | grep "${archive}" | cut -c-32`

        download "Oracle VM VirtualBox Extension Pack" "${url}" "${archive}" "${md5}"

        log "Installing Oracle VM VirtualBox Extension Pack from ${ievms_home}/${archive}"
        VBoxManage extpack install "${archive}" || fail "Failed to install Oracle VM VirtualBox Extension Pack from ${ievms_home}/${archive}, error code ($?)"
    fi
}

# Download and install `unar` from https://theunarchiver.com/ CDN
install_unar() {
    local url="https://cdn.theunarchiver.com/downloads/unarMac.zip"
    local archive=`basename "${url}"`

    download "unar" "${url}" "${archive}" "91796924b1b21ee586ed904b319bb447"

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
        VBoxManage showvminfo "${1}" | grep "State:" | grep -q "powered off" && sleep "${sleep_wait}" && return 0 || true
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
    local url="https://github.com/xdissent/ievms/releases/download/v${ievms_version}/ievms-control.iso"
    local dev_iso="${orig_cwd}/ievms-control.iso" # Use local iso if in ievms dev root
    if [[ -f "${dev_iso}" ]]
    then
        iso=$dev_iso
    else
        iso="${ievms_home}/ievms-control-${ievms_version}.iso"
        download "ievms control ISO" "${url}" "${iso}" "1fe3f95e0731bbcba949564cf9bbe28a"
    fi
}

# Attach a dvd image to the virtual machine.
attach() {
    log "Attaching ${3}"
    VBoxManage storageattach "${1}" --storagectl "IDE Controller" --port 0 \
        --device 1 --type dvddrive --medium "${2}"
}

# Eject the dvd image from the virtual machine.
eject() {
    log "Ejecting ${2}"
    VBoxManage storageattach "${1}" --storagectl "IDE Controller" --port 0 \
        --device 1 --type dvddrive --medium "emptydrive"
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
    attach "${1}" "additions" "Guest Additions"
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
    guest_control_exec "${1}" cmd.exe /c copy "E:\\${2}" "${3}"
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
# VMs are downloaded from https://developer.microsoft.com/en-us/microsoft-edge/tools/vms/
build_ievm() {
    unset archive
    unset unit
    local prefix="IE"
    local suffix=""
    local version="${1}"
    case $1 in
        6|7)
            fail "No longer supports IE6 or IE7"
            ;;
        8|9) os="Win7" ;;
        10|11)
            if [ "${reuse_win7}" != "yes" ]
            then
                if [ "$1" == "10" ]; then fail "IE10 is only available if REUSE_WIN7 is set"; fi
                os="Win81"
            else
                os="Win7"
                archive="IE9_Win7.zip"
            fi
            ;;
        EDGE)
            prefix="MS"
            version="Edge"
            os="Win10"
            unit="10"
            ;;
        *) fail "Invalid IE version: ${1}" ;;
    esac

    local browser="${prefix}${version}"
    local vm="${browser} - ${os}"
    local def_archive="${vm/ - /_}.zip"
    archive=${archive:-$def_archive}
    unit=${unit:-"9"}
    local ova="`basename "${archive/_/ - }" .zip`${suffix}.ova"

    local build_timestamp
    if [ "${os}" == "Win10" ]
    then
        build_timestamp="20180425"
    elif [ "${os}" == "Win81" ]
    then
        build_timestamp="20180102"
    else
        build_timestamp="20150916"
    fi
    local url="https://az792536.vo.msecnd.net/vms/VMBuild_${build_timestamp}/VirtualBox/${browser}/${browser}.${os}.VirtualBox.zip"

    local md5
    case $archive in
        IE8_Win7.zip)     md5="342e3d2d163f3ce345cfaa9cb5fa8012" ;;
        IE9_Win7.zip)     md5="0e1d3669b426fce8b0d772665f113302" ;;
        IE10_Win7.zip)    md5="21d0dee59fd11bdfce237864ef79063b" ;;
        IE11_Win7.zip)    md5="24675c913c4a74c87dc11f8ccb6c8f9e" ;;
        IE11_Win81.zip)   md5="896db7a54336982241d25f704f35d6c2" ;;
        MSEdge_Win10.zip) md5="fdbcfb79d36c6ffd424c9d36a88ddc02" ;;
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
        VBoxManage import "${ova}" --vsys 0 --vmname "${vm}" \
            --unit "${unit}" --disk "${disk_path}"

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

# Build the IE8 virtual machine.
build_ievm_ie8() {
    boot_auto_ga "IE8 - Win7"
}

# Build the IE9 virtual machine.
build_ievm_ie9() {
    boot_auto_ga "IE9 - Win7"
}

# Build the IE10 virtual machine.
build_ievm_ie10() {
    boot_auto_ga "IE10 - Win7"
    install_ie_win7 "IE10 - Win7" "https://raw.githubusercontent.com/kbandla/installers/master/MSIE/IE10-Windows6.1-x86-en-us.exe" "0f14b2de0b3cef611b9c1424049e996b"
}

# Build the IE11 virtual machine, reusing the Win7 VM if requested (the default).
build_ievm_ie11() {
    if [ "${reuse_win7}" != "yes" ]
    then
        boot_auto_ga "IE11 - Win81"
    else
        boot_auto_ga "IE11 - Win7"
        install_ie_win7 "IE11 - Win7" "http://download.microsoft.com/download/9/2/F/92FC119C-3BCD-476C-B425-038A39625558/IE11-Windows6.1-x86-en-us.exe" "7d3479b9007f3c0670940c1b10a3615f"
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
all_versions="8 9 10 11 EDGE"
for ver in ${IEVMS_VERSIONS:-$all_versions}
do
    log "Building IE ${ver} VM"
    build_ievm $ver
done

# We made it!
log "Done!"
