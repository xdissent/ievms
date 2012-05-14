#!/usr/bin/env bash

# Caution is a virtue
set -o nounset
set -o errtrace
set -o errexit
set -o pipefail

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

    log "Checking for Oracle VM VirtualBox Extension Pack"
    if ! VBoxManage list extpacks | grep "Oracle VM VirtualBox Extension Pack"
    then
        version=`VBoxManage -v`
        if [[ "$version" == *_Ubuntu* ]] # Ubuntu 12.04 modified the version message
        then
            ext_version="${version/_Ubuntur/-}"
            short_version="${version/_Ubuntur*/}"
        else
            ext_version="${version/r/-}"
            short_version="${version/r*/}"
        fi
        url="http://download.virtualbox.org/virtualbox/${short_version}/Oracle_VM_VirtualBox_Extension_Pack-${ext_version}.vbox-extpack"
        archive="Oracle_VM_VirtualBox_Extension_Pack-${ext_version}.vbox-extpack"

        if [[ ! -f "${archive}" ]]
        then
            log "Downloading Oracle VM VirtualBox Extension Pack from ${url} to ${ievms_home}/${archive}"
            if ! curl -L "${url}" -o "${archive}"
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

download_unrar() {
    url="http://www.rarlab.com/rar/rarosx-4.0.1.tar.gz"
    archive="rar.tar.gz"

    log "Downloading unrar from ${url} to ${ievms_home}/${archive}"
    if ! curl -L "${url}" -o "${archive}"
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

check_unrar() {
    PATH="${PATH}:${ievms_home}/rar"
    hash unrar 2>&- || install_unrar
}

build_ievm() {
    case $1 in
        6) 
            url="http://download.microsoft.com/download/B/7/2/B72085AE-0F04-4C6F-9182-BF1EE90F5273/Windows_XP_IE6.exe"
            archive="Windows_XP_IE6.exe"
            vhd="Windows XP.vhd"
            vm_type="WindowsXP"
            ;;
        7) 
            url="http://download.microsoft.com/download/B/7/2/B72085AE-0F04-4C6F-9182-BF1EE90F5273/Windows_Vista_IE7.part0{1.exe,2.rar,3.rar,4.rar,5.rar,6.rar}"
            archive="Windows_Vista_IE7.part01.exe"
            vhd="Windows Vista.vhd"
            vm_type="WindowsVista"
            ;;
        8) 
            url="http://download.microsoft.com/download/B/7/2/B72085AE-0F04-4C6F-9182-BF1EE90F5273/Windows_7_IE8.part0{1.exe,2.rar,3.rar,4.rar}"
            archive="Windows_7_IE8.part01.exe"
            vhd="Win7_IE8.vhd"
            vm_type="Windows7"
            ;;
        9) 
            url="http://download.microsoft.com/download/B/7/2/B72085AE-0F04-4C6F-9182-BF1EE90F5273/Windows_7_IE9.part0{1.exe,2.rar,3.rar,4.rar,5.rar,6.rar,7.rar}"
            archive="Windows_7_IE9.part01.exe"
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

        log "Checking for downloaded VHD at ${vhd_path}/${archive}"
        if [[ ! -f "${archive}" ]]
        then
            log "Downloading VHD from ${url} to ${ievms_home}/"
            if ! curl -L -O "${url}"
            then
                fail "Failed to download ${url} to ${vhd_path}/ using 'curl', error code ($?)"
            fi
        fi

        rm -f "${vhd_path}/*.vmc"

        log "Extracting VHD from ${vhd_path}/${archive}"
        if ! unrar e "${archive}"
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
    curl -L -O $1
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
check_unrar

all_versions="6 7 8 9"
for ver in ${IEVMS_VERSIONS:-$all_versions}
do
    log "Building IE${ver} VM"
    build_ievm $ver
done

log "Done!"
