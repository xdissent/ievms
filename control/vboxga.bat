cd /d D:\
cd \cert
VBoxCertUtil.exe add-trusted-publisher oracle-vbox.cer --root oracle-vbox.cer
cd \
VBoxWindowsAdditions.exe /S
regedit.exe /S C:\reuac.reg
del C:\reuac.reg
shutdown.exe /s /t 00
del %0