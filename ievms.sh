#!/usr/bin/env bash

# Caution is a virtue
set -o nounset
set -o errtrace
set -o errexit
set -o pipefail

curl_opts=${CURL_OPTS:-""}

log()  { printf "$*\n" ; return $? ;  }

fail() { log "\nERROR: $*\n" ; exit 1 ; }

create_home() {
    def_ievms_home="${HOME}/.ievms"
    ievms_home=${INSTALL_PATH:-$def_ievms_home}

    mkdir -p "${ievms_home}"
    cd "${ievms_home}"
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

build_ievm() {
    case $1 in
        6) os="WinXP" ;;
        7) os="Vista" ;;
        8) os="Win7" ;;
        9) os="Win7" ;;
        10) os="Win8" ;;
        *) fail "Invalid IE version: ${1}" ;;
    esac

    url="http://virtualization.modern.ie/vhd/IEKitV1_Final/VirtualBox/OSX/IE${1}_${os}.zip"
    vm="IE${1} - ${os}"
    ova="${vm}.ova"
    ova_path="${ievms_home}/ova/IE${1}"
    mkdir -p "${ova_path}"
    cd "${ova_path}"

    log "Checking for existing OVA at ${ova_path}/${ova}"
    if [[ ! -f "${ova}" ]]
    then

        log "Checking for downloaded OVA ZIPs at ${ova_path}/"
        archive=`basename $url`
        log "Downloading OVA ZIP from ${url} to ${ievms_home}/"
        if ! curl ${curl_opts} -C - -L -O "${url}"
        then
            fail "Failed to download ${url} to ${ova_path}/ using 'curl', error code ($?)"
        fi

        log "Extracting OVA from ${ova_path}/${archive}"
        if ! unzip "${archive}"
        then
            fail "Failed to extract ${archive} to ${ova_path}/${ova}," \
                "unrar command returned error code $?"
        fi
    fi

    log "Checking for existing ${vm} VM"
    if ! VBoxManage showvminfo "${vm}" 2>/dev/null
    then
        log "Creating ${vm} VM"
        VBoxManage import "${ova}"
        VBoxManage snapshot "${vm}" take clean --description "The initial VM state"
    fi
}


check_system
create_home
check_virtualbox
check_ext_pack

all_versions="6 7 8 9 10"
for ver in ${IEVMS_VERSIONS:-$all_versions}
do
    log "Building IE${ver} VM"
    build_ievm $ver
done

log "Done!"
