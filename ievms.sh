#!/usr/bin/env bash

# Caution is a virtue
set -o nounset
set -o errtrace
set -o errexit
set -o pipefail

curl_opts=${CURL_OPTS:-"-L -O"}
axel_opts=${AXEL_OPTS:-"-a"}
agent=${FORCE_AGENT:-""}
reuse_xp=${REUSE_XP:-"yes"}

log()  { printf "$*\n" ; return $? ;  }

fail() { log "\nERROR: $*\n" ; exit 1 ; }

download_agent() {
	# Check if an agent is forced. Otherwise use axel if available 
	# and curl as a fallback.
	if [ "$agent" == "" ]; then
		if hash axel 2>/dev/null; then
			agent="axel"
			agent_opts=${axel_opts}
		else
			agent="curl"
			agent_opts=${curl_opts}
		fi
	elif [ "$agent" == "axel" ]; then
		agent_opts=${axel_opts}
	else
		agent_opts=${curl_opts}
	fi
}

create_home() {
    def_ievms_home="${HOME}/.ievms"
    ievms_home=${INSTALL_PATH:-$def_ievms_home}

    mkdir -p "${ievms_home}"
    cd "${ievms_home}"

    # Move old ovas and zips into place:
    mv -f ./ova/IE*/IE*.{ova,zip} "${ievms_home}/" 2>/dev/null || true
}

check_system() {
    # Check for supported system
    kernel=`uname -s`
    case $kernel in
        Darwin|Linux) ;;
        *) fail "Sorry, $kernel is not supported." ;;
    esac
}

check_virtualbox() {
    log "Checking for VirtualBox"
    hash VBoxManage 2>&- || fail "VirtualBox command line utilities are not installed, please reinstall! (http://virtualbox.org)"
}

check_version() {
    version=`VBoxManage -v`
    major_minor_release="${version%%[-_r]*}"
    major_minor="${version%.*}"
    dl_page=`${agent} ${agent_opts} "http://download.virtualbox.org/virtualbox/" 2>/dev/null`

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
            if ! ${agent} ${agent_opts} "${url}" -o "${archive}"
            then
                fail "Failed to download ${url} to ${ievms_home}/${archive} using '${agent}', error code ($?)"
            fi
        fi

        log "Installing Oracle VM VirtualBox Extension Pack from ${ievms_home}/${archive}"
        if ! VBoxManage extpack install "${archive}"
        then
            fail "Failed to install Oracle VM VirtualBox Extension Pack from ${ievms_home}/${archive}, error code ($?)"
        fi
    fi
}

download_unar() {
    unar_url="http://theunarchiver.googlecode.com/files/unar1.5.zip"
    unar_archive=`basename "${unar_url}"`

    log "Downloading unar from ${unar_url} to ${ievms_home}/${unar_archive}"
    if [[ ! -f "${unar_archive}" ]] && ! ${agent} ${agent_opts} "${unar_url}" -o "${unar_archive}"
    then
        fail "Failed to download ${unar_url} to ${ievms_home}/${unar_archive} using '${agent}', error code ($?)"
    fi

    if ! unzip "${unar_archive}"
    then
        fail "Failed to extract ${ievms_home}/${unar_archive} to ${ievms_home}/," \
            "unzip command returned error code $?"
    fi

    hash unar 2>&- || fail "Could not find unar in ${ievms_home}"
}

check_unar() {
    if [ "${kernel}" == "Darwin" ]
    then
        PATH="${PATH}:${ievms_home}"
        hash unar 2>&- || download_unar
    else
        hash unar 2>&- || fail "Linux support requires unar (sudo apt-get install for Ubuntu/Debian)"
    fi
}

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
        10) os="Win8" ;;
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
        if [[ ! -f "${archive}" ]] && ! ${agent} ${agent_opts} "${url}"
        then
            fail "Failed to download ${url} to ${ievms_home}/ using '${agent}', error code ($?)"
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

build_ievm_xp() {
    sleep_wait="10"

    installer=`basename "${2}"`
    installer_host="${ievms_home}/${installer}"
    installer_guest="/Documents and Settings/IEUser/Desktop/Install IE${1}.exe"
    log "Downloading IE${1} installer from ${2}"
    if [[ ! -f "${installer}" ]] && ! ${agent} ${agent_opts} "${2}" -o "${installer}"
    then
        fail "Failed to download ${url} to ${ievms_home}/${installer} using '${agent}', error code ($?)"
    fi

    iso_url="https://dl.dropbox.com/u/463624/ievms-control.iso"
    dev_iso=`pwd`/ievms-control.iso # Use local iso if in ievms dev root
    if [[ -f "${dev_iso}" ]]; then iso=$dev_iso; else iso="${ievms_home}/ievms-control.iso"; fi
    log "Downloading ievms ISO from ${iso_url}"
    if [[ ! -f "${iso}" ]] && ! ${agent} ${agent_opts} "${iso_url}" -o "${iso}"
    then
        fail "Failed to download ${iso_url} to ${ievms_home}/${iso} using '${agent}', error code ($?)"
    fi

    log "Attaching ievms.iso"
    VBoxManage storageattach "${vm}" --storagectl "IDE Controller" --port 1 --device 0 --type dvddrive --medium "${iso}"

    log "Starting VM ${vm}"
    VBoxManage startvm "${vm}" --type headless

    log "Waiting for ${vm} to shutdown..."
    x="0" ; until [ "${x}" != "0" ]; do
      sleep "${sleep_wait}"
      VBoxManage list runningvms | grep "${vm}" >/dev/null && x=$? || x=$?
    done

    log "Ejecting ievms.iso"
    VBoxManage modifyvm "${vm}" --dvd none

    log "Starting VM ${vm}"
    VBoxManage startvm "${vm}" --type headless

    log "Waiting for ${vm} to be available for guestcontrol..."
    x="1" ; until [ "${x}" == "0" ]; do
      sleep "${sleep_wait}"
      VBoxManage guestcontrol "${vm}" cp "${installer_host}" "${installer_guest}" --username IEUser --dryrun && x=$? || x=$?
    done

    sleep "${sleep_wait}" # Extra sleep for good measure.
    log "Copying IE${1} installer to Desktop"
    VBoxManage guestcontrol "${vm}" cp "${installer_host}" "${installer_guest}" --username IEUser

    log "Installing IE${1}" # Always "fails"
    VBoxManage guestcontrol "${vm}" exec --image "${installer_guest}" --username IEUser --wait-exit -- /passive /norestart || true

    log "Shutting down VM ${vm}"
    VBoxManage guestcontrol "${vm}" exec --image "/WINDOWS/system32/shutdown.exe" --username IEUser --wait-exit -- -s -f -t 0

    x="0" ; until [ "${x}" != "0" ]; do
      sleep "${sleep_wait}"
      log "Waiting for ${vm} to shutdown..."
      VBoxManage list runningvms | grep "${vm}" >/dev/null && x=$? || x=$?
    done

    sleep "${sleep_wait}" # Extra sleep for good measure.
}

build_ievm_ie7() {
    if [ "${reuse_xp}" != "yes" ]; then return; fi
    build_ievm_xp 7 "http://download.microsoft.com/download/3/8/8/38889dc1-848c-4bf2-8335-86c573ad86d9/IE7-WindowsXP-x86-enu.exe"
}

build_ievm_ie8() {
    if [ "${reuse_xp}" != "yes" ]; then return; fi
    build_ievm_xp 8 "http://download.microsoft.com/download/C/C/0/CC0BD555-33DD-411E-936B-73AC6F95AE11/IE8-WindowsXP-x86-ENU.exe"
}

download_agent
check_system
create_home
check_virtualbox
check_ext_pack
check_unar

all_versions="6 7 8 9 10"
for ver in ${IEVMS_VERSIONS:-$all_versions}
do
    log "Building IE${ver} VM"
    build_ievm $ver
done

log "Done!"
