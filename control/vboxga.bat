cd /d D:\
cd \cert
VBoxCertUtil.exe add-trusted-publisher oracle-vbox.cer --root oracle-vbox.cer
cd \
VBoxWindowsAdditions.exe /S
regedit.exe /S C:\reuac.reg
del C:\reuac.reg
FOR /F "usebackq" %%i IN (`hostname`) DO SET HOST=%%i
schtasks.exe /create /s %HOST% /ru %HOST%\IEUser /rp Passw0rd! /tn activate /xml C:\activate.xml
schtasks.exe /create /s %HOST% /ru %HOST%\IEUser /rp Passw0rd! /tn rearm /xml C:\rearm.xml
schtasks.exe /create /s %HOST% /ru %HOST%\IEUser /rp Passw0rd! /tn boot /xml C:\boot.xml
schtasks.exe /run /tn activate
timeout /t 30
shutdown.exe /s /t 00
del %0