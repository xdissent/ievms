#!/usr/bin/env bash

# Caution is a virtue
set -o nounset
set -o errtrace
set -o errexit
set -o pipefail

log()  { printf "$*\n" ; return $? ;  }

fail() { log "\nERROR: $*\n" ; exit 1 ; }

DOWNLOADER=curl
DOWNLOADTYPE=1
EXTPACK=""
GA_ADDONS=""
GA_ADDONS_URL=""

while getopts "e:a:d:" Option; do
  case $Option in
    e)
      log "using extension pack url: $OPTARG"
      EXTPACK=$OPTARG
      ;;
    d)
      log "Guest Addons iso url to download: $OPTARG"
      GA_ADDONS_URL=$OPTARG
      ;;
    a)
      log "using addons iso dir: $OPTARG"
      GA_ADDONS=$OPTARG
      ;;
    \?)
      exit 1
      ;;
  esac
done

check_downloader() {
  if curl=$(which curl)
  then
    DOWNLOADER=$curl
    DOWNLOADTYPE=1
  else
    if wget=$(which wget)
    then
      DOWNLOADER=$wget
      DOWNLOADTYPE=2
    else
      fail "Curl or wget could not be found"
    fi
  fi
}

download_file() {
  file=$1
  output=$2

  if [[ $DOWNLOADTYPE -eq 1 ]]
  then
    # -C - tries to resume download from where it was left
    $DOWNLOADER -C - -L $1 -o "$2"
  else
    $DOWNLOADER -c $1 -O "$2"
  fi
}

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
        if [ "x$EXTPACK" == "x" ]
        then
          version=`VBoxManage -v`
          ext_version="${version/r/-}"
          short_version="${version/r*/}"
          url="http://download.virtualbox.org/virtualbox/${short_version}/Oracle_VM_VirtualBox_Extension_Pack-${ext_version}.vbox-extpack"
          archive="Oracle_VM_VirtualBox_Extension_Pack-${ext_version}.vbox-extpack"
        else
          url=$EXTPACK
          archive=$(basename $EXTPACK)
        fi

        if [[ ! -s "${ievms_home}/${archive}" ]]
        then
            log "Downloading Oracle VM VirtualBox Extension Pack from ${url} to ${ievms_home}/${archive}"
            if ! download_file "${url}" "${archive}"
            then
                fail "Failed to download ${url} to ${ievms_home}/${archive} using '$DOWNLOADER', error code ($?)"
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
    if ! download_file "${url}" "${archive}"
    then
        fail "Failed to download ${url} to ${ievms_home}/${archive} using '$DOWNLOADER', error code ($?)"
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
            urls=( "http://download.microsoft.com/download/B/7/2/B72085AE-0F04-4C6F-9182-BF1EE90F5273/Windows_XP_IE6.exe" )
            archive="Windows_XP_IE6.exe"
            vhd="Windows XP.vhd"
            vm_type="WindowsXP"
            fail "IE6 support is currently disabled"
            ;;
        7)
            urls=( \
              "http://www.microsoft.com/downloads/info.aspx?na=41&srcfamilyid=21eabb90-958f-4b64-b5f1-73d0a413c8ef&srcdisplaylang=en&u=http%3a%2f%2fdownload.microsoft.com%2fdownload%2fB%2f7%2f2%2fB72085AE-0F04-4C6F-9182-BF1EE90F5273%2fWindows_Vista_IE7.part01.exe" \
              "http://www.microsoft.com/downloads/info.aspx?na=41&srcfamilyid=21eabb90-958f-4b64-b5f1-73d0a413c8ef&srcdisplaylang=en&u=http%3a%2f%2fdownload.microsoft.com%2fdownload%2fB%2f7%2f2%2fB72085AE-0F04-4C6F-9182-BF1EE90F5273%2fWindows_Vista_IE7.part02.rar" \
              "http://www.microsoft.com/downloads/info.aspx?na=41&srcfamilyid=21eabb90-958f-4b64-b5f1-73d0a413c8ef&srcdisplaylang=en&u=http%3a%2f%2fdownload.microsoft.com%2fdownload%2fB%2f7%2f2%2fB72085AE-0F04-4C6F-9182-BF1EE90F5273%2fWindows_Vista_IE7.part03.rar" \
              "http://www.microsoft.com/downloads/info.aspx?na=41&srcfamilyid=21eabb90-958f-4b64-b5f1-73d0a413c8ef&srcdisplaylang=en&u=http%3a%2f%2fdownload.microsoft.com%2fdownload%2fB%2f7%2f2%2fB72085AE-0F04-4C6F-9182-BF1EE90F5273%2fWindows_Vista_IE7.part04.rar" \
              "http://www.microsoft.com/downloads/info.aspx?na=41&srcfamilyid=21eabb90-958f-4b64-b5f1-73d0a413c8ef&srcdisplaylang=en&u=http%3a%2f%2fdownload.microsoft.com%2fdownload%2fB%2f7%2f2%2fB72085AE-0F04-4C6F-9182-BF1EE90F5273%2fWindows_Vista_IE7.part05.rar" \
              "http://www.microsoft.com/downloads/info.aspx?na=41&srcfamilyid=21eabb90-958f-4b64-b5f1-73d0a413c8ef&srcdisplaylang=en&u=http%3a%2f%2fdownload.microsoft.com%2fdownload%2fB%2f7%2f2%2fB72085AE-0F04-4C6F-9182-BF1EE90F5273%2fWindows_Vista_IE7.part06.rar" \
            )
            md5s=( \
              0e6cc7b812cb4a0a2740cb271708ba10 \
              5e0c6f37dbb011e5f3870ce1a20b5c61 \
              0c9e1d25f2e590ae4d3215e8b1bd8825 \
              c3c4edabc458f21fe2211845bf1d51f7 \
              17e48893ded8587c972743af825dea67 \
              d5e9e11476ba33cee0494a48b7fb085a \
            )
            archive=$(basename ${urls[0]})
            vhd="Windows Vista.vhd"
            vm_type="WindowsVista"
            ;;
        8)
            urls=( \
              "http://www.microsoft.com/downloads/info.aspx?na=41&srcfamilyid=21eabb90-958f-4b64-b5f1-73d0a413c8ef&srcdisplaylang=en&u=http%3a%2f%2fdownload.microsoft.com%2fdownload%2fB%2f7%2f2%2fB72085AE-0F04-4C6F-9182-BF1EE90F5273%2fWindows_7_IE8.part01.exe" \
              "http://www.microsoft.com/downloads/info.aspx?na=41&srcfamilyid=21eabb90-958f-4b64-b5f1-73d0a413c8ef&srcdisplaylang=en&u=http%3a%2f%2fdownload.microsoft.com%2fdownload%2fB%2f7%2f2%2fB72085AE-0F04-4C6F-9182-BF1EE90F5273%2fWindows_7_IE8.part02.rar" \
              "http://www.microsoft.com/downloads/info.aspx?na=41&srcfamilyid=21eabb90-958f-4b64-b5f1-73d0a413c8ef&srcdisplaylang=en&u=http%3a%2f%2fdownload.microsoft.com%2fdownload%2fB%2f7%2f2%2fB72085AE-0F04-4C6F-9182-BF1EE90F5273%2fWindows_7_IE8.part03.rar" \
              "http://www.microsoft.com/downloads/info.aspx?na=41&srcfamilyid=21eabb90-958f-4b64-b5f1-73d0a413c8ef&srcdisplaylang=en&u=http%3a%2f%2fdownload.microsoft.com%2fdownload%2fB%2f7%2f2%2fB72085AE-0F04-4C6F-9182-BF1EE90F5273%2fWindows_7_IE8.part04.rar" \
            )
            md5s=( \
              31636fb412fd2e9fd250d4b831a70903 \
              6fdb27bc33e56dd2928c86fa8101b0e4 \
              64b26e846d0fdf515a97a2234edddc2e \
              cf838d245245975723d975cef581fcbb \
            )
            archive=$(basename ${urls[0]})
            vhd="Win7_IE8.vhd"
            vm_type="Windows7"
            ;;
        9)
            urls=( \
              "http://www.microsoft.com/downloads/info.aspx?na=41&srcfamilyid=21eabb90-958f-4b64-b5f1-73d0a413c8ef&srcdisplaylang=en&u=http%3a%2f%2fdownload.microsoft.com%2fdownload%2fB%2f7%2f2%2fB72085AE-0F04-4C6F-9182-BF1EE90F5273%2fWindows_7_IE9.part01.exe" \
              "http://www.microsoft.com/downloads/info.aspx?na=41&srcfamilyid=21eabb90-958f-4b64-b5f1-73d0a413c8ef&srcdisplaylang=en&u=http%3a%2f%2fdownload.microsoft.com%2fdownload%2fB%2f7%2f2%2fB72085AE-0F04-4C6F-9182-BF1EE90F5273%2fWindows_7_IE9.part02.rar" \
              "http://www.microsoft.com/downloads/info.aspx?na=41&srcfamilyid=21eabb90-958f-4b64-b5f1-73d0a413c8ef&srcdisplaylang=en&u=http%3a%2f%2fdownload.microsoft.com%2fdownload%2fB%2f7%2f2%2fB72085AE-0F04-4C6F-9182-BF1EE90F5273%2fWindows_7_IE9.part03.rar" \
              "http://www.microsoft.com/downloads/info.aspx?na=41&srcfamilyid=21eabb90-958f-4b64-b5f1-73d0a413c8ef&srcdisplaylang=en&u=http%3a%2f%2fdownload.microsoft.com%2fdownload%2fB%2f7%2f2%2fB72085AE-0F04-4C6F-9182-BF1EE90F5273%2fWindows_7_IE9.part04.rar" \
              "http://www.microsoft.com/downloads/info.aspx?na=41&srcfamilyid=21eabb90-958f-4b64-b5f1-73d0a413c8ef&srcdisplaylang=en&u=http%3a%2f%2fdownload.microsoft.com%2fdownload%2fB%2f7%2f2%2fB72085AE-0F04-4C6F-9182-BF1EE90F5273%2fWindows_7_IE9.part05.rar" \
              "http://www.microsoft.com/downloads/info.aspx?na=41&srcfamilyid=21eabb90-958f-4b64-b5f1-73d0a413c8ef&srcdisplaylang=en&u=http%3a%2f%2fdownload.microsoft.com%2fdownload%2fB%2f7%2f2%2fB72085AE-0F04-4C6F-9182-BF1EE90F5273%2fWindows_7_IE9.part06.rar" \
              "http://www.microsoft.com/downloads/info.aspx?na=41&srcfamilyid=21eabb90-958f-4b64-b5f1-73d0a413c8ef&srcdisplaylang=en&u=http%3a%2f%2fdownload.microsoft.com%2fdownload%2fB%2f7%2f2%2fB72085AE-0F04-4C6F-9182-BF1EE90F5273%2fWindows_7_IE9.part07.rar" \
            )
            md5s=( \
              4ad277a45ebe98e4d56d4adad14a64f6 \
              b5e74d497424509d981ef2fa1d22a873 \
              239c9b4a0ea67187c96861100688c180 \
              2e1fb5f62de4fd5b364c91712b038ed0 \
              6789d8e438f5d5934a72b874ad9acf17 \
              c47aa0336d32f25c7d5f30e3d1261b4e \
              a5966bc97e6d7b03dd32c048c0d0ee5d \
            )
            archive=$(basename ${urls[0]})
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
        i=0
        for url in "${urls[@]}"
        do
          downloaded=0
          d=0
          file=${vhd_path}/$(basename $url)
          # Try redownloading if md5 mismatches up to 3 times
          while true;
          do
            log "Checking for downloaded VHD at $file"
            if [[ ! -s $file ]]
            then
              log "Downloading VHD from ${urls} to ${ievms_home}/"
              if ! download_file "${url}" "$file"
              then
                  fail "Failed to download ${url} to ${vhd_path}/ using '$DOWNLOADER', error code ($?)"
              fi
            else
              log "Checking md5sum of file " $file " for " ${md5s[$i]}
              md5sum=$(md5sum $file|awk '{ print $1 }')
              if [[ $md5sum == ${md5s[$i]} ]]
              then
                downloaded=1
              fi
            fi
            if [[ $downloaded -eq 1 ]]
            then
              log "Downloaded successfully"
              break
            fi
            d=$(($d+1))
            if [[ $d -eq 4 ]]
            then
              fail "Download of file $file failed at least 3 times"
              break;
            fi;
          done
          i=$(($i+1))
        done
        rm -f "${vhd_path}/*.vmc"

        log "Extracting VHD from ${vhd_path}/${archive}"
        if ! unrar e "${archive}"
        then
            fail "Failed to extract ${archive} to ${vhd_path}/${vhd}," \
                "unrar command returned error code $?"
        fi
    fi



    if [[ $GA_ADDONS_URL != "" ]]
    then
      if ! download_file "$GA_ADDONS_URL" "$ievms_home/$(basename $GA_ADDONS_URL)"
      then
          fail "Failed to download ${GA_ADDONS_URL} to ${ievms_home}/"
      fi
    fi

    log "Checking for existing ${vm} VM"
    if ! VBoxManage showvminfo "${vm}"
    then
        if [[ $GA_ADDONS == "" && $GA_ADDONS_URL == "" ]]
        then
          case $kernel in
              Darwin) ga_iso="/Applications/VirtualBox.app/Contents/MacOS/VBoxGuestAdditions.iso" ;;
              Linux) ga_iso="/usr/share/virtualbox/VBoxGuestAdditions.iso" ;;
          esac
        elif [[ $GA_ADDONS_URL != "" ]]
        then
          ga_iso=$ievms_home/$(basename $GA_ADDONS_URL)
        else
          ga_iso=$GA_ADDONS
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
        VBoxManage snapshot "${vm}" take clean --description "The initial VM state"
    fi
}

check_system
check_downloader
create_home
check_virtualbox
check_unrar

all_versions="7 8 9"
for ver in ${IEVMS_VERSIONS:-$all_versions}
do
    log "Building IE${ver} VM"
    build_ievm $ver
done

log "Done!"
