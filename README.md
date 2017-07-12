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


## Dependencies / compiler information

* piconsole (daemon for Raspberry Pi):
  * Compilation only tested and supported under free pascal 3.
  * piconsole requires the rpiio library.
  * This is available under my GitHub account at https://github.com/zipplet/rpiio
  * Supplied with and designed to be used with a copy of godaemon (godaemontask) built for ARMv6


## Coming soon

* Microcontroller firmware
* Schematics
* Installer/etc
* See todo.txt for more information
