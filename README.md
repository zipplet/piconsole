## piconsole - The Raspberry Pi retro videogame console project

  Copyright (C) 2017  Michael Andrew Nixon

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.


## What is this?

A collection of software (for the Raspberry Pi), firmware (for microcontrollers)
and schematics to allow you to build a retro videogames console, designed to be
used alongside RetroPie - https://retropie.org.uk/ - to enhance the experience
by providing:

* Clean power-up and shutdown sequence for the Raspberry Pi system
* Reset button support to back-out of a running game without needing a hotkey
* The daemon automatically fixes controller configuration files generated by Emulation Station to disable unwanted emulator hotkeys -  such as load/save state, reset emulator and exit emulator (each hotkey can be disabled individually depending on your preferences)
  * You will never accidentally exit the game again!
  * I know you can disable the __global__ RetroArch hotkey in newer versions of RetroPie, but that's silly - it's a useful hotkey and without it you can no longer access RetroArch configuration in-game (select+X). This hot-patching allows you to keep the global hotkey enabled but just have the annoying hotkey combinations disabled.
  * It works on the fly, patching configuration files as they change, get created or at system startup/shutdown (configurable).
* Later, a script to recompile the Raspberry Pi kernel and modules to enable force-feedback for supported controllers / controller-to-USB adaptors
  * It is disabled by default, probably for maximum compatibility with poor power supplies.
  * Please use a good power supply!

See it in action here, being constructed inside an old PlayStation: https://www.youtube.com/playlist?list=PLqM2eWK6z3M0DvGwcI3AX9BVud6s98hcG


## Dependencies / compiler information

* piconsole (daemon for Raspberry Pi):
  * Compilation only tested and supported under free pascal 3.
  * Requires the rpiio library - https://github.com/zipplet/rpiio
  * Requires the lcore library - https://github.com/zipplet/lcore
  * Supplied with and designed to be used with a copy of godaemon (godaemontask) built for ARMv6
  * godaemon is also one of my projects and the source can be found at https://github.com/zipplet/godaemon

* firmware / ATTINY85 (firmware for the control PCB without fan PWM):
  * Compiles with Atmel Studio 7.0
  * Should also fit on the smaller ATTINY chips (the code compiles to <2KB)

## Coming soon

* More microcontroller firmware
* Schematics
* Installer/etc
* Releases so you do not need to compile anything
* See todo.txt for more information
