@echo off
rem Runs scripts\cgra.py: "cgra sim configs\rsqrt.csv", "cgra fpga configs\rsqrt.csv".
rem Uses python from PATH if it works, otherwise the copy bundled with Vivado.
setlocal
set "PY="
python -c "" >nul 2>&1 && set "PY=python"
if not defined PY if defined CGRA_VIVADO (
    for /d %%p in ("%CGRA_VIVADO%\..\tps\win64\python-3*") do set "PY=%%p\python.exe"
)
if not defined PY (
    for /d %%v in ("C:\Xilinx\*" "C:\AMDDesignTools\*") do (
        for /d %%p in ("%%v\tps\win64\python-3*") do set "PY=%%p\python.exe"
    )
)
if not defined PY (
    echo error: no Python found. Install Python or set CGRA_VIVADO to your Vivado install dir.
    exit /b 1
)
"%PY%" "%~dp0scripts\cgra.py" %*
