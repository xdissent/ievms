cd /d D:\
cd \cert
VBoxCertUtil.exe add-trusted-publisher oracle-vbox.cer --root oracle-vbox.cer
cd \
VBoxWindowsAdditions.exe /S
regedit.exe /S C:\reuac.reg
del C:\reuac.reg
FOR /F "usebackq" %%i IN (`hostname`) DO SET HOST=%%i
schtasks.exe /create /s %HOST% /ru %HOST%\IEUser /rp Passw0rd! /tn ievms /xml C:\ievms.xml
echo slmgr.vbs /ato >C:\Users\IEUser\ievms.bat
schtasks.exe /run /tn ievms
timeout /t 30
del C:\Users\IEUser\ievms.bat
shutdown.exe /s /t 00
del %0