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

  Configuration and globals unit
  ---------------------------------------------------------------------------- }
unit unitconfig;

interface

uses sysutils, classes;

const
  DEFAULT_CONFIGFILE_NAME = 'config.ini';

type
  rSettings = record
    // other
    configfile: ansistring;
    basepath: ansistring;

    // System
    system_newpi: boolean;
    system_ondelay: longint;

    // gpio
    gpio_powerup: longint;
    gpio_powerdown: longint;
    gpio_useresetbutton: boolean;
    gpio_resetbutton: longint;

    // controller
    controller_disablehotkeys: boolean;
    controller_configdir: ansistring;
    controller_username: ansistring;
    controller_groupname: ansistring;
    controller_disable_load_state_button: boolean;
    controller_disable_save_state_button: boolean;
    controller_disable_exit_emulator_button: boolean;
    controller_disable_state_slot_decrease_button: boolean;
    controller_disable_state_slot_increase_button: boolean;
    controller_disable_reset_button: boolean;
    controller_fix_at_boot: boolean;
    controller_fix_at_shutdown: boolean;
  end;

var
  _settings: rSettings;

function ReadSettings: boolean;

implementation

uses inifiles;

{ ----------------------------------------------------------------------------
  Read all configuration settings. Returns True on success.
  ---------------------------------------------------------------------------- }
function ReadSettings: boolean;
var
  inifile: tinifile;
begin
  result := false;
  if not fileexists(_settings.configfile) then begin
    writeln('Error: The configuration file does not exist: ' + _settings.configfile);
    exit;
  end;
  try
    inifile := tinifile.Create(_settings.configfile);
    writeln('Configuration file: ' + _settings.configfile);

    // First get all settings
    _settings.system_newpi := inifile.ReadBool('system', 'newpi', false);
    _settings.system_ondelay := inifile.ReadInteger('system', 'ondelay', -1);

    _settings.gpio_powerup := inifile.ReadInteger('gpio', 'powerup', -1);
    _settings.gpio_powerdown := inifile.ReadInteger('gpio', 'powerdown', -1);
    _settings.gpio_useresetbutton := inifile.ReadBool('gpio', 'useresetbutton', false);
    _settings.gpio_resetbutton := inifile.ReadInteger('gpio', 'resetbutton', -1);

    _settings.controller_disablehotkeys := inifile.ReadBool('controller', 'disablehotkeys', false);
    _settings.controller_configdir := inifile.ReadString('controller', 'configdir', '');
    _settings.controller_username := inifile.ReadString('controller', 'username', '');
    _settings.controller_groupname := inifile.ReadString('controller', 'groupname', '');
    _settings.controller_disable_load_state_button := inifile.ReadBool('controller', 'disable_load_state_button', false);
    _settings.controller_disable_save_state_button := inifile.ReadBool('controller', 'disable_save_state_button', false);
    _settings.controller_disable_exit_emulator_button := inifile.ReadBool('controller', 'disable_exit_emulator_button', false);
    _settings.controller_disable_state_slot_decrease_button := inifile.ReadBool('controller', 'disable_state_slot_decrease_button', false);
    _settings.controller_disable_state_slot_increase_button := inifile.ReadBool('controller', 'disable_state_slot_increase_button', false);
    _settings.controller_disable_reset_button := inifile.ReadBool('controller', 'disable_reset_button', false);
    _settings.controller_fix_at_boot := inifile.ReadBool('controller', 'fix_at_boot', false);
    _settings.controller_fix_at_shutdown := inifile.ReadBool('controller', 'fix_at_shutdown', false);

    // Now validate them
    if _settings.system_ondelay = -1 then begin
      raise exception.Create('system / ondelay is missing');
      exit;
    end;
    if _settings.gpio_powerup = -1 then begin
      raise exception.Create('gpio / powerup is missing');
      exit;
    end;
    if _settings.gpio_powerdown = -1 then begin
      raise exception.Create('gpio / powerdown is missing');
      exit;
    end;
    if (_settings.gpio_useresetbutton = true) and (_settings.gpio_resetbutton = -1) then begin
      raise exception.Create('gpio / resetbutton is missing (if you do not want to use the reset button, set useresetbutton to 0)');
      exit;
    end;
    if _settings.controller_disablehotkeys then begin
      if _settings.controller_configdir = '' then begin
        raise exception.Create('controller / configdir is missing (if you do not want to use this functionality, set controller / disablehotkeys to 0)');
        exit;
      end;
      if _settings.controller_username = '' then begin
        raise exception.Create('controller / username is missing (if you do not want to use this functionality, set controller / disablehotkeys to 0)');
        exit;
      end;
      if _settings.controller_groupname = '' then begin
        raise exception.Create('controller / groupname is missing (if you do not want to use this functionality, set controller / disablehotkeys to 0)');
        exit;
      end;
    end;

    freeandnil(inifile);
  except
    on e: exception do begin
      writeln('Error: Exception while reading the configuration file: ' + e.Message);
      exit;
    end;
  end;

  result := true;
end;

{ ----------------------------------------------------------------------------
  Unit initialisation
  ---------------------------------------------------------------------------- }
initialization
begin
  _settings.basepath := extractfilepath(paramstr(0));
  _settings.configfile := _settings.basepath + DEFAULT_CONFIGFILE_NAME;
end;

{ ----------------------------------------------------------------------------
  ---------------------------------------------------------------------------- }
end.
