#!/usr/bin/env bash

# Caution is a virtue
set -o nounset
set -o errtrace
set -o errexit
set -o pipefail

log()  { printf "$*\n" ; return $? ;  }

fail() { log "\nERROR: $*\n" ; exit 1 ; }

create_home() {
  ievms_home="${HOME}/ievms"
  mkdir -p "${ievms_home}"
  cd "${ievms_home}"
}

install_packages() {
  apt-get install -y uck curl unzip
}

download_cross_compiler() {
  url="http://landley.net/aboriginal/downloads/binaries/cross-compiler-i686.tar.bz2"
  archive=`basename "${url}"`
  log "Downloading cross compiler archive from ${url} to ${ievms_home}/${archive}"
  if [[ ! -e "${archive}" ]] && ! curl -L "${url}" -o "${archive}"
  then
    fail "Failed to download ${url} to ${ievms_home}/${archive} using 'curl', error code ($?)"
  fi
}

extract_cross_compiler() {
  cross_compiler=`basename "${archive}" .tar.bz2`
  log "Extracting cross compiler archive from ${archive} to ${ievms_home}/${cross_compiler}"
  if [[ ! -e "${cross_compiler}" ]] && ! tar -jxf "${archive}"
  then
    fail "Failed to extract ${archive} to ${ievms_home}/${cross_compiler} using 'tar', error code ($?)"
  fi
}

download_kernel() {
  url="http://www.kernel.org/pub/linux/kernel/v3.0/linux-3.5.tar.bz2"
  archive=`basename "${url}"`
  log "Downloading kernel archive from ${url} to ${ievms_home}/${archive}"
  if [[ ! -e "${archive}" ]] && ! curl -L "${url}" -o "${archive}"
  then
    fail "Failed to download ${url} to ${ievms_home}/${archive} using 'curl', error code ($?)"
  fi  
}

extract_kernel() {
  kernel_src=`basename "${archive}" .tar.bz2`
  log "Extracting kernel archive from ${archive} to ${ievms_home}/${kernel_src}"
  if [[ ! -e "${kernel_src}" ]] && ! tar -jxf "${archive}"
  then
    fail "Failed to extract ${archive} to ${ievms_home}/${kernel_src} using 'tar', error code ($?)"
  fi  
}

configure_kernel() {
  kernel_config="/vagrant/control/kernel.config"
  log "Configuring kernel from ${kernel_config} to ${ievms_home}/${kernel_src}/.config"
  cp "${kernel_config}" "${kernel_src}/.config"
}

build_kernel() {
  kernel="${ievms_home}/${kernel_src}/arch/x86/boot/bzImage"
  cd "${kernel_src}"
  log "Building kernel in ${ievms_home}/${kernel_src} to ${kernel}"
  if [[ ! -e "${kernel}" ]] && ! make
  then
    fail "Failed to build kernel in ${ievms_home}/${kernel_src} using 'make', error code ($?)"
  fi
  cd -
}

download_iso() {
  url="http://pogostick.net/~pnh/ntpasswd/cd110511.zip"
  archive=`basename "${url}"`
  log "Downloading ntpasswd ISO archive from ${url} to ${ievms_home}/${archive}"
  if [[ ! -e "${archive}" ]] && ! curl -L "${url}" -o "${archive}"
  then
    fail "Failed to download ${url} to ${ievms_home}/${archive} using 'curl', error code ($?)"
  fi  
}

extract_iso() {
  iso=`basename "${archive}" .zip`.iso
  log "Extracting ntpasswd ISO archive from ${archive} to ${ievms_home}/${iso}"
  if [[ ! -e "${iso}" ]] && ! unzip "${archive}"
  then
    fail "Failed to extract ${archive} to ${ievms_home}/${iso} using 'unzip', error code ($?)"
  fi  
}

unpack_iso() {
  remaster_iso="${HOME}/tmp/remaster-iso"
  log "Unpacking ntpasswd ISO from ${iso} to ${remaster_iso}"
  if [[ ! -e "${remaster_iso}" ]] && ! uck-remaster-unpack-iso "${iso}"
  then
    fail "Failed to unpack ${iso} to ${remaster_iso} using 'uck-remaster-unpack-iso', error code ($?)"
  fi
}

extract_initrd() {
  initrd="${ievms_home}/initrd"
  initrd_cgz="${remaster_iso}/initrd.cgz"
  mkdir -p "${initrd}"
  cd "${initrd}"
  log "Extracting initrd from ${initrd_cgz} to ${initrd}"
  if ! gzip -cd "${initrd_cgz}" | cpio -i -d -H newc --no-absolute-filenames
  then
    fail "Failed to extract ${initrd_cgz} to ${initrd} using 'gzip | cpio', error code ($?)"
  fi
}

copy_scripts() {
  log "Copying scripts"
  cp "/vagrant/control/stage2" "${initrd}/scripts/"
  cp "/vagrant/control/ievms.reg" "${initrd}/scripts/"
  cp "/vagrant/control/deuac.reg" "${initrd}/scripts/"
  cp "/vagrant/control/reuac.reg" "${initrd}/scripts/"
  cp "/vagrant/control/vboxga.bat" "${initrd}/scripts/"
  cp "/vagrant/control/isolinux.cfg" "${remaster_iso}/isolinux.cfg"
  cp "/vagrant/control/isolinux.cfg" "${remaster_iso}/syslinux.cfg"
  cp "${kernel}" "${remaster_iso}/"
  chmod 755 "${remaster_iso}/bzImage"
  rm -f "${remaster_iso}/vmlinuz" "${remaster_iso}/scsi.cgz" "${remaster_iso}/readme.txt"
}

compress_initrd() {
  cd "${initrd}"
  log "Compressing initrd from ${initrd} to ${initrd_cgz}"
  if ! find . | cpio -o -H newc | gzip > "${initrd_cgz}"
  then
    fail "Failed to compress ${initrd} to ${initrd_cgz} using 'cpio | gzip', error code ($?)"
  fi
}

pack_iso() {
  iso_out="/vagrant/ievms-control.iso"
  log "Packing ievms ISO from ${remaster_iso} to ${iso_out}"
  if ! genisoimage -o "${iso_out}" -b isolinux.bin -c boot.cat -p "ievms" -no-emul-boot -boot-load-size 4 -boot-info-table -V "IEVMS" -cache-inodes -r -J -l -joliet-long "${remaster_iso}" 
  then
    fail "Failed to pack ${remaster_iso} to ${iso_out} using 'genisoimage', error code ($?)"
  fi
}

create_home
install_packages
download_cross_compiler
extract_cross_compiler
export PATH="${ievms_home}/${cross_compiler}/bin:$PATH"
download_kernel
extract_kernel
configure_kernel
build_kernel
download_iso
extract_iso
unpack_iso
extract_initrd
copy_scripts
compress_initrd
pack_iso