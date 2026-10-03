@echo off
rem Opens MATLAB in a console window and starts the interactive swarm receiver demo.
matlab -nodesktop -nosplash -sd "%~dp0." -r "swarm_receivers"
