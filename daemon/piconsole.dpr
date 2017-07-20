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

  Main project file
  ---------------------------------------------------------------------------- }
program piconsole;

uses
  sysutils,
  classes,
  process,
  unix,
  baseunix,
  rpigpio,
  lcore,
  lcoreselect,
  btime,
  unitdaemon in 'unitdaemon.pas',
  unitconfig in 'unitconfig.pas',
  unitglobal in 'unitglobal.pas',
  unitgpl in 'unitgpl.pas';

{ ---------------------------------------------------------------------------
  Main program
  --------------------------------------------------------------------------- }
begin
  try
    lcoreinit;
    writeln('piconsole - Copyright (C) 2017  Michael Andrew Nixon');
    writeln('This program comes with ABSOLUTELY NO WARRANTY; for details type ''--warranty''.');
    writeln('This is free software, and you are welcome to redistribute it');
    writeln('under certain conditions; type ''--license'' for details.');
    writeln;

    if paramcount >= 1 then begin
      if lowercase(paramstr(1)) = '--warranty' then begin
        DisplayGPLWarranty;
        writeln('Type --license to view the entire license.');
        exit;
      end else if lowercase(paramstr(1)) = '--license' then begin
        DisplayGPL;
        exit;
      end else begin
        _settings.configfile := paramstr(1);
      end;
    end;
    if not ReadSettings then begin
      writeln('Failed to load settings.');
      exit;
    end;

    _daemon := tdaemon.Create;
    writeln('Starting daemon loop');
    _daemon.RunDaemon;
    writeln('Daemon loop stopped.');
    freeandnil(_daemon);
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
