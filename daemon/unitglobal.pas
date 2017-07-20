{ ----------------------------------------------------------------------------
  piconsole - The Raspberry Pi retro videogame console project
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
  
  Contact: zipplet@zipplet.co.uk

  Global unit
  ---------------------------------------------------------------------------- }
unit unitglobal;

interface

uses
  sysutils,
  classes,
  lcore,
  lcoreselect,
  btime,
  unix,
  baseunix,
  unitconfig,
  unitdaemon,
  rpigpio;

const
  DEFAULT_CONFIGFILE_NAME = 'config.ini';

  SYSTEM_LED_PATH = '/sys/class/leds/';
  SYSTEM_POWER_PATH = '/sys/class/power_supply/';

  DUALSHOCK4_RED_LED = ':red/brightness';
  DUALSHOCK4_GREEN_LED = ':green/brightness';
  DUALSHOCK4_BLUE_LED = ':blue/brightness';
  DUALSHOCK4_BATTERY_SEARCH_MASK = 'sony_controller_battery_*';
  DUALSHOCK4_BATTERY_CHARGE = '/capacity';
  DUALSHOCK4_REAL_DEVICE = '/device';

  BUTTON_POLL_INTERVAL = 50;

var
  _daemon: tdaemon;
  _settings: rSettings;

implementation

end.
