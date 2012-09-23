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
    hash VBoxManage 2>&- || fail "VirtualBox is not installed! (http://virtualbox.org)"
}

check_version() {
    version=`VBoxManage -v`
    major_minor_release="${version%%[-_r]*}"
    major_minor="${version%.*}"
    dl_page=`curl ${curl_opts} -L "http://download.virtualbox.org/virtualbox/" 2>/dev/null`

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

install_unrar() {
    case $kernel in
        Darwin) download_unrar ;;
        Linux) fail "Linux support requires unrar (sudo apt-get install for Ubuntu/Debian)" ;;
    esac
}

install_cabextract() {
    case $kernel in
        Darwin) download_cabextract ;;
        Linux) fail "Linux support requires cabextract (sudo apt-get install for Ubuntu/Debian)" ;;
    esac
}

download_unrar() {
    url="http://www.rarlab.com/rar/rarosx-4.0.1.tar.gz"
    archive="rar.tar.gz"

    log "Downloading unrar from ${url} to ${ievms_home}/${archive}"
    if ! curl ${curl_opts} -C - -L "${url}" -o "${archive}"
    then
        fail "Failed to download ${url} to ${ievms_home}/${archive} using 'curl', error code ($?)"
    fi

    if ! tar zxf "${archive}" -C "${ievms_home}/" --no-same-owner
    then
        fail "Failed to extract ${ievms_home}/${archive} to ${ievms_home}/," \
            "tar command returned error code $?"
    fi

    hash unrar 2>&- || fail "Could not find unrar in ${ievms_home}/rar/"
}

download_cabextract() {
    url="http://rudix.googlecode.com/files/cabextract-1.4-3.pkg"
    archive="cabextract.pkg"

    log "Downloading cabextract from ${url} to ${ievms_home}/${archive}"
    if ! curl ${curl_opts} -C - -L "${url}" -o "${archive}"
    then
        fail "Failed to download ${url} to ${ievms_home}/${archive} using 'curl', error code ($?)"
    fi

    mkdir -p "${ievms_home}/cabextract"
    if ! xar -xf "${archive}" -C "${ievms_home}/cabextract"
    then
        fail "Failed to extract ${ievms_home}/${archive} to ${ievms_home}/cabextract," \
            "xar command returned error code $?"
    fi

    cd "${ievms_home}/cabextract/cabextractinstall.pkg"
    gzcat Payload | cpio -i --quiet
    cd "${ievms_home}"
    hash cabextract 2>&- || fail "Could not find cabextract in ${ievms_home}/cabextract/cabextractinstall.pkg/usr/local/bin"
}

check_unrar() {
    PATH="${PATH}:${ievms_home}/rar"
    hash unrar 2>&- || install_unrar
}

check_cabextract() {
    PATH="${PATH}:${ievms_home}/cabextract/cabextractinstall.pkg/usr/local/bin"
    hash cabextract 2>&- || install_cabextract
}

build_ievm() {
    extract_cmd="unrar e -y"

    case $1 in
        6) 
            urls="http://download.microsoft.com/download/B/7/2/B72085AE-0F04-4C6F-9182-BF1EE90F5273/Windows_XP_IE6.exe"
            vhd="Windows XP.vhd"
            vm_type="WindowsXP"
            extract_cmd="cabextract"
            ;;
        7) 
            urls=`echo http://download.microsoft.com/download/B/7/2/B72085AE-0F04-4C6F-9182-BF1EE90F5273/Windows_Vista_IE7.part0{1.exe,2.rar,3.rar,4.rar,5.rar,6.rar}`
            vhd="Windows Vista.vhd"
            vm_type="WindowsVista"
            ;;
        8) 
            urls=`echo http://download.microsoft.com/download/B/7/2/B72085AE-0F04-4C6F-9182-BF1EE90F5273/Windows_7_IE8.part0{1.exe,2.rar,3.rar,4.rar}`
            vhd="Win7_IE8.vhd"
            vm_type="Windows7"
            ;;
        9) 
            urls=`echo http://download.microsoft.com/download/B/7/2/B72085AE-0F04-4C6F-9182-BF1EE90F5273/Windows_7_IE9.part0{1.exe,2.rar,3.rar,4.rar,5.rar,6.rar,7.rar}`
            vhd="Windows 7.vhd"
            vm_type="Windows7"
            ;;
        *)
            fail "Invalid IE version: ${1}"
            ;;
    esac

    vm="IE${1}"
    vhd_path="${ievms_home}/vhd/${vm}"
    mkdir -p "${vhd_path}"
    cd "${vhd_path}"

    log "Checking for existing VHD at ${vhd_path}/${vhd}"
    if [[ ! -f "${vhd}" ]]
    then

        log "Checking for downloaded VHDs at ${vhd_path}/"
        for url in $urls
        do
            archive=`basename $url`
            log "Downloading VHD from ${url} to ${ievms_home}/"
            if ! curl ${curl_opts} -C - -L -O "${url}"
            then
                fail "Failed to download ${url} to ${vhd_path}/ using 'curl', error code ($?)"
            fi
        done

        rm -f "${vhd_path}/"*.vmc

        log "Extracting VHD from ${vhd_path}/${archive}"
        if ! ${extract_cmd} "${archive}"
        then
            fail "Failed to extract ${archive} to ${vhd_path}/${vhd}," \
                "unrar command returned error code $?"
        fi
    fi

    log "Checking for existing ${vm} VM"
    if ! VBoxManage showvminfo "${vm}"
    then

        case $kernel in
            Darwin) ga_iso="/Applications/VirtualBox.app/Contents/MacOS/VBoxGuestAdditions.iso" ;;
            Linux) ga_iso="/usr/share/virtualbox/VBoxGuestAdditions.iso" ;;
        esac

        if [[ ! -f "${ga_iso}" ]]
        then
            check_version
            ga_iso="${ievms_home}/VBoxGuestAdditions_${major_minor_release}.iso"

            if [[ ! -f "${ga_iso}" ]]
            then
                url="http://download.virtualbox.org/virtualbox/${major_minor_release}/VBoxGuestAdditions_${major_minor_release}.iso"
                log "Downloading Virtualbox Guest Additions ISO from ${url} to ${ga_iso}"
                if ! curl ${curl_opts} -L "${url}" -o "${ga_iso}"
                then
                    fail "Failed to download ${url} to ${ga_iso} using 'curl', error code ($?)"
                fi
            fi
        fi

        log "Creating ${vm} VM"
        VBoxManage createvm --name "${vm}" --ostype "${vm_type}" --register
        VBoxManage modifyvm "${vm}" --memory 256 --vram 32
        VBoxManage storagectl "${vm}" --name "IDE Controller" --add ide --controller PIIX4 --bootable on
        VBoxManage storagectl "${vm}" --name "Floppy Controller" --add floppy
        VBoxManage internalcommands sethduuid "${vhd_path}/${vhd}"
        VBoxManage storageattach "${vm}" --storagectl "IDE Controller" --port 0 --device 0 --type hdd --medium "${vhd_path}/${vhd}"
        VBoxManage storageattach "${vm}" --storagectl "IDE Controller" --port 0 --device 1 --type dvddrive --medium "${ga_iso}"
        VBoxManage storageattach "${vm}" --storagectl "Floppy Controller" --port 0 --device 0 --type fdd --medium emptydrive
        declare -F "build_ievm_ie${1}" && "build_ievm_ie${1}"
        VBoxManage snapshot "${vm}" take clean --description "The initial VM state"
    fi

}

build_ievm_ie6() {
    log "Setting up ${vm} VM"

    if [[ ! -f "${ievms_home}/drivers/PRO2KXP.exe" ]]
    then
        download_driver "http://downloadmirror.intel.com/8659/eng/PRO2KXP.exe" "Downloading 82540EM network adapter driver"

        if [[ ! -f "${ievms_home}/drivers/autorun.inf" ]]
        then
            cd "${ievms_home}/drivers"
            echo '[autorun]' > autorun.inf
            echo 'open=PRO2KXP.exe' >> autorun.inf
            cd "${ievms_home}"
        fi
    fi

    log "Changing network adapter to 82540EM"
    VBoxManage modifyvm "${vm}" --nictype1 "82540EM"

    build_and_attach_drivers
}

download_driver() {
    if [[ ! -d "${ievms_home}/drivers" ]]
    then
        mkdir -p "${ievms_home}/drivers"
    fi

    log $2

    cd "${ievms_home}/drivers"
    # Currently the IE6 driver download server doesn't support resume
    if ! curl ${curl_opts} -L -O "$1"
    then
        fail "Failed to download $1 to ${ievms_home}/drivers/ using 'curl', error code ($?)"
    fi
    cd ..
}

build_and_attach_drivers() {
    log "Building drivers ISO for ${vm}"
    if [[ ! -f "${ievms_home}/drivers.iso" ]]
    then
      log "Writing drivers ISO"

      
      case $kernel in
          Darwin) hdiutil makehybrid "${ievms_home}/drivers" -o "${ievms_home}/drivers.iso" ;;
          Linux) mkisofs -o "${ievms_home}/drivers.iso" "${ievms_home}/drivers" ;;
      esac
    fi

    VBoxManage storageattach "${vm}" --storagectl "IDE Controller" --port 1 --device 0 --type dvddrive --medium "${ievms_home}/drivers.iso"
}

check_system
create_home
check_virtualbox
check_ext_pack
check_unrar
check_cabextract

all_versions="6 7 8 9"
for ver in ${IEVMS_VERSIONS:-$all_versions}
do
    log "Building IE${ver} VM"
    build_ievm $ver
done

log "Done!"
