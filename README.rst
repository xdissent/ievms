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


Installation
============

    curl -s https://raw.github.com/xdissent/ievms/master/ievms.sh | bash
