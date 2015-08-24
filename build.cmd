@echo off

if "%1" == "" goto ERROR

goto MAIN

:ERROR

Echo You need to introduce a release number (example 0.6)

goto DONE 

:MAIN

echo Release: v%1

call pp -c -o pbp.exe pbp.pl

if exist pbp.exe (
	echo Creating package pbp-v%1.zip
	"c:\Program Files\7-Zip\7z.exe" a -r -y pbp-v%1.zip Desktops doc pbp.conf pbp.pl pbp.exe 
) else (
	echo Package file creation failed!
)

if exist pbp-v%1.zip (
	echo Package creation complete. Cleaning temp files
	del pbp.exe
) else (
	echo ZIP file pbp-v%1.zip not created
)
:DONE