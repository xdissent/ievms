Overview
========

Microsoft provides virtual machine disk images to facilitate website testing 
in multiple versions of IE, regardless of the host operating system. 
~~Unfortunately, setting these virtual machines up without Microsoft's VirtualPC
can be extremely difficult. The ievms scripts aim to facilitate that process using
VirtualBox on Linux or OS X.~~ With a single command, you can have IE6, IE7, IE8,
IE9 and IE10 running in separate virtual machines. 

**NOTE:** As of Feb. 1st, 2013, the [MS images](http://www.modern.ie/virtualization-tools)
are fully compatible with Virtualbox, thanks to the [modern.IE](http://modern.IE)
project.

[![Click here to lend your support to ievms and make a donation at pledgie.com!](http://pledgie.com/campaigns/15995.png?skin_name=chrome)](http://pledgie.com/campaigns/15995)


Quickstart
==========

Just paste this into a terminal: `curl -s https://raw.github.com/xdissent/ievms/master/ievms.sh | bash`


Requirements
============

* VirtualBox (http://virtualbox.org)
* Curl (Ubuntu: `sudo apt-get install curl`)
* Linux Only: unar (Ubuntu: `sudo apt-get install unar`)
* Patience


Disk requirements
-----------------

A full ievms install will require approximately 37G:

    Servo:.ievms xdissent$ du -ch *
    5.7G  IE10 - Win8-disk1.vmdk
    2.6G  IE10 - Win8.ova
    2.5G  IE10_Win8.zip
    1.5G  IE6 - WinXP-disk1.vmdk
    724M  IE6 - WinXP.ova
    717M  IE6_WinXP.zip
    1.6G  IE7 - WinXP-disk1.vmdk
     15M  IE7-WindowsXP-x86-enu.exe
    1.6G  IE8 - WinXP-disk1.vmdk
     16M  IE8-WindowsXP-x86-ENU.exe
     10G  IE9 - Win7-disk1.vmdk
    4.7G  IE9 - Win7.ova
    4.7G  IE9_Win7.zip
    3.4M  ievms-control.iso
    4.6M  lsar
    4.5M  unar
    4.1M  unar1.5.zip
     37G  total
   
You may remove all files except `*.vmdk` after installation and they will be
re-downloaded if ievms is run again in the future:

    $ find ~/.ievms -type f ! -name "*.vmdk" -exec rm {} \;

If all installation related files are removed, around 21G is required:

    Servo:.ievms xdissent$ du -ch *
    5.7G  IE10 - Win8-disk1.vmdk
    1.5G  IE6 - WinXP-disk1.vmdk
    1.6G  IE7 - WinXP-disk1.vmdk
    1.6G  IE8 - WinXP-disk1.vmdk
     10G  IE9 - Win7-disk1.vmdk
     21G  total


Bandwidth requirements
----------------------

A full installation will download roughly 7.5G of data.

**NOTE:** Reusing the XP VM for IE7 and IE8 (the default) saves an incredible
amount of space and bandwidth. If it is disabled (`REUSE_XP=no`) the disk space
required climbs to 74G (39G if cleaned post-install) and around 17G will be 
downloaded.


Installation
============

1. Install VirtualBox (make sure command line utilities are selected and installed).

2. Download and unpack ievms:

   * Install IE versions 6, 7, 8, 9 and 10.

        curl -s https://raw.github.com/xdissent/ievms/master/ievms.sh | bash

   * Install specific IE versions (IE7 and IE9 only for example):

        curl -s https://raw.github.com/xdissent/ievms/master/ievms.sh | IEVMS_VERSIONS="7 9" bash

3. Launch Virtual Box.

4. Choose ievms image from Virtual Box.

The OVA images are massive and can take hours or tens of minutes to 
download, depending on the speed of your internet connection. You might want
to start the install and then go catch a movie, or maybe dinner, or both. 


Recovering from a failed installation
-------------------------------------

Each version is installed into `~/.ievms/` (or `INSTALL_PATH`). If the installation fails
for any reason (corrupted download, for instance), delete the appropriate ZIP/ova file
and rerun the install.

If nothing else, you can delete `~/.ievms` (or `INSTALL_PATH`) and rerun the install.


Specifying the install path
---------------------------

To specify where the VMs are installed, use the `INSTALL_PATH` variable:

    curl -s https://raw.github.com/xdissent/ievms/master/ievms.sh | env INSTALL_PATH="/Path/to/.ievms" bash


Passing additional options to curl
----------------------------------

The `curl` command is passed any options present in the `CURL_OPTS` 
environment variable. For example, you can set a download speed limit:

    curl -s https://raw.github.com/xdissent/ievms/master/ievms.sh | env CURL_OPTS="--limit-rate 50k" bash


Features
========

Clean Snapshot
--------------

A snapshot is automatically taken upon install, allowing rollback to the
pristine virtual environment configuration. Anything can go wrong in 
Windows and rather than having to worry about maintaining a stable VM,
you can simply revert to the `clean` snapshot to reset your VM to the
initial state.


Resuming Downloads
------------------

~~If one of the comically large files fails to download, the `curl` 
command used will automatically attempt to resume where it left off.~~
Unfortunately, the modern.IE download servers do not support resume.


Reusing XP VMs
--------------

IE7 and IE8 ship from MS on Vista and Win7 respectively. Both of these
images are far larger than the IE6 XP image, which also technically supports
IE7 and IE8. To save bandwidth, space and time, ievms will will reuse
(duplicate) the IE6 XP VM image for both. Virtualbox guest control is used
to run the appropriate IE installer within the VM. The `clean` snapshot
includes the updated browser version.

**NOTE:** If you'd like to disable XP VM reuse for IE7 and IE8, set the 
environment variable `REUSE_XP` to anything other than `yes`:

    curl -s https://raw.github.com/xdissent/ievms/master/ievms.sh | env REUSE_XP="no" bash


Control ISO
-----------

Microsoft's XP image uses a blank password for the `IEUser`, which disallows
control via Virtualbox's guest control by default. Changing a value in the
Windows registry enables guest control, but requires accessing the VM's hard
drive. A solution is to boot the VM with a special boot CD image which attaches
the hard disk and edits the registry. A custom linux build has been created
based on [the ntpasswd bootdisk](http://pogostick.net/~pnh/ntpasswd/) which
makes the required registry edits and simply powers off the machine. The ievms
script may then use Virtualbox guest controls to manage the VM.

The control ISO is built within a [Vagrant](http://vagrantup.com) Ubuntu VM.
If you'd like to build it yourself, clone the ievms repository, install
Vagrant and run `vagrant up`. The base ntpasswd boot disk will be downloaded, 
unpacked and customized within the Vagrant VM. A custom linux kernel is 
cross-compiled for the image as well.


Acknowledgements
================

* [modern.IE](http://modern.ie) - Provider of IE VM images.
* [ntpasswd](http://pogostick.net/~pnh/ntpasswd/) - Boot disk starting point
and registry editor.
* [regit-config](https://github.com/regit/regit-config) - Minimal Virtualbox
kernel config reference.
* [uck](http://sourceforge.net/projects/uck/) - Used to (re)master control ISO.

License
=======

None. (To quote Morrissey, "take it, it's yours")
