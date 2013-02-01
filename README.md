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


Requirements
============

* VirtualBox (http://virtualbox.org)
* Curl (Ubuntu: `sudo apt-get install curl`)
* Linux Only: unzip (Ubuntu: `sudo apt-get install unzip`)
* Patience


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

Each version is installed into a subdirectory of `~/.ievms/ova/`. If the installation fails
for any reason (corrupted download, for instance), delete the version-specific subdirectory
and rerun the install.

If nothing else, you can delete `~/.ievms` and rerun the install.


Specifying the install path
---------------------------

To specify where the VMs are installed, use the INSTALL_PATH variable:

    curl -s https://raw.github.com/xdissent/ievms/master/ievms.sh | INSTALL_PATH="/Path/to/.ievms" bash


Passing additional options to curl
----------------------------------

The `curl` command is passed any options present in the `CURL_OPTS` 
environment variable. For example, you can set a download speed limit:

    curl -s https://raw.github.com/xdissent/ievms/master/ievms.sh | CURL_OPTS="--limit-rate 50k" bash


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

If one of the comically large files fails to download, the `curl` 
command used will automatically attempt to resume where it left off. 


License
=======

None. (To quote Morrissey, "take it, it's yours")
