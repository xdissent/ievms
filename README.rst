Overview
========

Microsoft provides virtual machine disk images to facilitate website testing 
in multiple versions of IE, regardless of the host operating system. 
Unfortunately, setting these virtual machines up without Microsoft's VirtualPC
can be extremely difficult. These scripts aim to facilitate that process using
VirtualBox on Linux or OS X. With a single command, you can have IE6, IE7, IE8
and IE9 running in separate virtual machines.

Requirements
============

* VirtualBox (http://virtualbox.org)
* Curl (Ubuntu: ``apt-get install curl``)
* Patience


Installation
============

* Install all IE versions (IE7, IE8 and IE9 - no support for IE6 currently)

    curl -s https://raw.github.com/xdissent/ievms/master/ievms.sh | bash

* Install specific IE versions (IE7 and IE9 only for example):

    curl -s https://raw.github.com/xdissent/ievms/master/ievms.sh | IEVMS_VERSIONS="7 9" bash


The VHD archives are massive and can take hours or tens of minutes to 
download, depending on the speed of your internet connection. You might want
to start the install and then go catch a movie, or maybe dinner, or both. 


Features
========

Clean Snapshot
    A snapshot is automatically taken upon install, allowing rollback to the
    pristine virtual environment configuration. Anything can go wrong in 
    Windows and rather than having to worry about maintaining a stable VM,
    you can simply revert to the ``clean`` snapshot to reset your VM to the
    initial state.

    The VMs provided by Microsoft will not pass the Windows Genuine Advantage
    and cannot be activated. Unfortunately for us, that means our VMs will
    lock us out after 30 days of unactivated use. By reverting to the 
    ``clean`` snapshot the countdown to the activation apocalypse is reset,
    effectively allowing your VM to work indefinitely.