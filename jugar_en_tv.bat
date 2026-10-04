@echo off
rem Abre PARTY-GAME como TV en pantalla completa (PC con Windows conectada a la tele por HDMI).
rem Uso: doble clic en este archivo. Guia completa: docs\BUILD.md, seccion "Jugar con la PC conectada a la TV".
rem Si Godot esta en otra carpeta, cambia SOLO la linea de abajo.
set "GODOT=D:\Claude\Godot\Godot_v4.4.1-stable_win64_console.exe"

if not exist "%GODOT%" (
	echo.
	echo  No encuentro Godot en:
	echo    %GODOT%
	echo.
	echo  Abri este archivo con el Bloc de notas y cambia la linea "set GODOT=..."
	echo  por la ruta donde tengas Godot 4.4.1 (el .exe que termina en _console.exe).
	echo.
	pause
	exit /b 1
)

rem %~dp0 = carpeta de este .bat (la raiz del proyecto), funcione desde donde se lo abra.
"%GODOT%" --path "%~dp0." -- --host --fullscreen
if errorlevel 1 (
	echo.
	echo  Godot se cerro con un error. Revisa los mensajes de arriba.
	pause
)
