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


## Custom kernels for the Piconsole project

These kernels have force feedback enabled for all supported controller adaptors,
and are currently based on the 4.11 branch. This means they support DualShock 4
controllers using native bluetooth (on the Pi 3) or with a decent bluetooth USB
adaptor (all other Pi models) without requiring you to install ds4drv - even if
you are using a brand new PS4 controller (the recent version with the better
lightbar and grey buttons).


## Installation

You do this at your own risk, MAKE A BACKUP FIRST.

* Run install.sh as root and it should guide you through installation.
