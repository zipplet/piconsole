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

  Main daemon unit
  ---------------------------------------------------------------------------- }
unit unitdaemon;

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
  rpigpio;

type
  tdaemon = class(tobject)
    private
    protected
      gpiodriver: trpiGPIO;
      buttonCheckTimer: tltimer;
      configCheckTimer: tltimer;
      lastConfigCheckTime: tunixtimeint;

      // Timer events
      procedure ButtonCheckTimerEvent(Sender: TObject);
      procedure ConfigCheckTimerEvent(Sender: TObject);

      procedure CheckConfigurationChangesSince(ts: tunixtimeint);
      procedure CloseRetroarch;
      procedure StartShutdown;
    public
      procedure FixControllerConfigurationFiles;

      procedure RunDaemon;
      constructor Create;
      destructor Destroy; override;
  end;

implementation

uses process, unitglobal;

{ ---------------------------------------------------------------------------
  Timer: Check for configuration file changes
  --------------------------------------------------------------------------- }
procedure tdaemon.ConfigCheckTimerEvent(Sender: TObject);
begin
  self.configCheckTimer.enabled := false;

  self.CheckConfigurationChangesSince(self.lastConfigCheckTime);
  self.lastConfigCheckTime := unixtimeint;

  self.configCheckTimer.enabled := true;
end;

{ ---------------------------------------------------------------------------
  Timer: Check for button events
  --------------------------------------------------------------------------- }
procedure tdaemon.ButtonCheckTimerEvent(Sender: TObject);
var
  i: longint;
begin
  self.buttonCheckTimer.enabled := false;

  // Shutdown request?
  if self.gpiodriver.readPin(_settings.gpio_powerdown) then begin
    // Wait for another 10ms and read again to be certain
    sleep(10);
    if self.gpiodriver.readPin(_settings.gpio_powerdown) then begin
      // Yep, shutdown request.
      writeln('tdaemon: *** Shutdown request received ***');
      write('tdaemon: Shutting down GPIO driver: ');
      self.gpiodriver.shutdown;
      freeandnil(gpiodriver);
      writeln('Done');
      self.CloseRetroarch;
      writeln('tdaemon: Waiting...');
      sleep(5000);
      // Fixup controller configurations at shutdown if requested
      if _settings.controller_disablehotkeys and _settings.controller_fix_at_shutdown then begin
        self.FixControllerConfigurationFiles;
      end;
      write('tdaemon: Starting shutdown process: ');
      self.StartShutdown;
      writeln('tdaemon: Done');
      exitmessageloop;
      exit;
    end;
  end;

  // Reset button request?
  if _settings.gpio_useresetbutton then begin
    if not self.gpiodriver.readPin(_settings.gpio_resetbutton) then begin
      // Wait for 10ms and read again to debounce
      sleep(10);
      if not self.gpiodriver.readPin(_settings.gpio_resetbutton) then begin
        // Reset button - try to kill retroarch nicely so it saves SRAM/etc
        self.CloseRetroarch;
        // Now wait for it to be released
        i := 10;
        while (i > 0) do begin
          sleep(10);
          dec(i);
          if not self.gpiodriver.readPin(_settings.gpio_resetbutton) then begin
            i := 10;
          end;
        end;
      end;
    end;
  end;

  self.buttonCheckTimer.enabled := true;
end;

{ ---------------------------------------------------------------------------
  Begin system shutdown
  --------------------------------------------------------------------------- }
procedure tdaemon.StartShutdown;
var
  process: tprocess;
begin
  try
    process := tprocess.Create(nil);
    process.executable := '/sbin/poweroff';
    process.execute;
    process.WaitOnExit;
    freeandnil(process);
    exit;
  except
    on e: exception do begin
      writeln('tdaemon: Exception while trying to shutdown: ' + e.message);
    end;
  end;
end;

{ ---------------------------------------------------------------------------
  Close Retroarch nicely if running
  --------------------------------------------------------------------------- }
procedure tdaemon.CloseRetroarch;
var
  process: tprocess;
begin
  writeln('tdaemon: Trying to kill retroarch nicely if it is running');
  try
    process := tprocess.Create(nil);
    process.executable := '/usr/bin/killall';
    process.parameters.add('-s');
    process.parameters.add('SIGTERM');
    process.parameters.add('retroarch');
    process.execute;
    process.WaitOnExit;
    freeandnil(process);
  except
    on e: exception do begin
      writeln('tdaemon: Exception while trying to stop retroarch: ' + e.message);
      end;
  end;
end;

{ ---------------------------------------------------------------------------
  Check if any controller configuration files have been modified since <ts>,
  and if they have fix them.
  --------------------------------------------------------------------------- }
procedure tdaemon.CheckConfigurationChangesSince(ts: tunixtimeint);
var
  fileinfo: tsearchrec;
  needfix: boolean;
begin
  needfix := false;
  if FindFirst(_settings.controller_configdir + '/*.cfg', faAnyFile, fileinfo) = 0 then begin
    repeat
      if fileinfo.time >= ts then begin
        needfix := true;
      end;
    until FindNext(fileinfo) <> 0;
  end;
  FindClose(fileinfo);
  if needfix then begin
    writeln('tdaemon: Found changed controller configuration files.');
    self.FixControllerConfigurationFiles;
  end;
end;

{ ----------------------------------------------------------------------------
  Fixup controller configurations saved by RetroPie to disable unwanted
  hotkeys that the user does not desire.
  ---------------------------------------------------------------------------- }
procedure tdaemon.FixControllerConfigurationFiles;
var
  fileinfo: tsearchrec;
  infile: textfile;
  binfile: file;
  s: ansistring;
  sl: tstringlist;
  sl2: tstringlist;
  i, x: longint;
  lineending: byte;
begin
  writeln('tdaemon: Scanning for and fixing controller configuration files in ' + _settings.controller_configdir + '...');
  sl := tstringlist.create;
  if FindFirst(_settings.controller_configdir + '/*.cfg', faAnyFile, fileinfo) = 0 then begin
    repeat
      sl.add(_settings.controller_configdir + '/' + fileinfo.name);
    until FindNext(fileinfo) <> 0;
  end;
  FindClose(fileinfo);

  for i := 0 to sl.count - 1 do begin
    write('[' + sl.strings[i] + ']: checking...');
    try
      filemode := fmOpenRead;
      assignfile(infile, sl.strings[i]);
      reset(infile);
      // Check if the first line is our "processing done" marker
      readln(infile, s);
      if s <> '# piconsole modified' then begin
        // Needs fixing!
        write('fixing...');
        // First read the entire file into a stringlist altering as necessary
        sl2 := tstringlist.create;
        sl2.add('# piconsole modified');
        // Make sure to re-add the first line!
        sl2.add(s);
        while not eof(infile) do begin
          readln(infile, s);
          if _settings.controller_disable_load_state_button then begin
            if pos('input_load_state_', s) > 0 then begin
              s := '#' + s;
            end;
          end;
          if _settings.controller_disable_save_state_button then begin
            if pos('input_save_state_', s) > 0 then begin
              s := '#' + s;
            end;
          end;
          if _settings.controller_disable_exit_emulator_button then begin
            if pos('input_exit_emulator_', s) > 0 then begin
              s := '#' + s;
            end;
          end;
          if _settings.controller_disable_state_slot_decrease_button then begin
            if pos('input_state_slot_decrease_', s) > 0 then begin
              s := '#' + s;
            end;
          end;
          if _settings.controller_disable_state_slot_increase_button then begin
            if pos('input_state_slot_increase_', s) > 0 then begin
              s := '#' + s;
            end;
          end;
          if _settings.controller_disable_reset_button then begin
            if pos('input_reset_', s) > 0 then begin
              s := '#' + s;
            end;
          end;
          sl2.add(s);
        end;
        // Now truncate the file and write the new contents - this keeps the
        // ownership/etc the same
        closefile(infile);
        filemode := fmOpenReadWrite;
        assignfile(binfile, sl.strings[i]);
        reset(binfile, 1);
        truncate(binfile);
        lineending := 10;
        for x := 0 to sl2.count - 1 do begin
          s := sl2.strings[x];
          blockwrite(binfile, s[1], length(s));
          blockwrite(binfile, lineending, 1);
        end;
        closefile(binfile);
        freeandnil(sl2);
        writeln('patched');
      end else begin
        writeln('already fixed');
      end;
    except
      on e: exception do begin
        writeln('tdaemon: Exception processing controller configuration: ' + e.message);
        closefile(infile);
        if assigned(sl) then begin
          freeandnil(sl);
        end;
      end;
    end;
  end;

  freeandnil(sl);
end;

{ ----------------------------------------------------------------------------
  tdaemon constructor
  ---------------------------------------------------------------------------- }
constructor tdaemon.Create;
begin
  inherited Create;

  // Fixup controller configurations at boot if requested
  if _settings.controller_disablehotkeys and _settings.controller_fix_at_boot then begin
    self.FixControllerConfigurationFiles;
  end;

  self.buttonCheckTimer := tltimer.Create(nil);
  self.buttonCheckTimer.onTimer := self.ButtonCheckTimerEvent;
  self.buttonCheckTimer.interval := BUTTON_POLL_INTERVAL;
  self.buttonCheckTimer.enabled := false;

  // Are we regularly checking for configuration changes?
  self.configCheckTimer := nil;
  if _settings.controller_disablehotkeys then begin
    if _settings.controller_fix_regularly then begin
      self.configCheckTimer := tltimer.Create(nil);
      self.configCheckTimer.onTimer := self.ConfigCheckTimerEvent;
      self.configCheckTimer.interval := _settings.controller_check_interval * 1000;
      self.configCheckTimer.enabled := false;
    end;
  end;
end;

{ ----------------------------------------------------------------------------
  tdaemon destructor
  ---------------------------------------------------------------------------- }
destructor tdaemon.Destroy;
begin
  //
  inherited Destroy;
end;

{ ----------------------------------------------------------------------------
  Daemon main loop
  ---------------------------------------------------------------------------- }
procedure tdaemon.RunDaemon;
begin
  // Initialise GPIO driver
  self.gpiodriver := trpiGPIO.Create;
  if not self.gpiodriver.initialise(_settings.system_newpi) then begin
    freeandnil(gpiodriver);
    writeln('tdaemon: Failed to initialise GPIO driver.');
    exit;
  end;

  write('tdaemon: Waiting (ondelay): ');
  sleep(_settings.system_ondelay * 1000);
  writeln('Done');

  writeln('tdaemon: Setting up GPIO pins...');

  write('tdaemon: Power-up pin: ');
  gpiodriver.setPinMode(_settings.gpio_powerup, RPIGPIO_OUTPUT);
  writeln('Done');

  write('tdaemon: Power-down pin: ');
  gpiodriver.setPinMode(_settings.gpio_powerdown, RPIGPIO_INPUT);
  gpiodriver.setPullupMode(_settings.gpio_powerdown, RPIGPIO_PUD_OFF);
  writeln('Done');

  write('tdaemon: Reset pin: ');
  if _settings.gpio_useresetbutton then begin
    gpiodriver.setPinMode(_settings.gpio_resetbutton, RPIGPIO_INPUT);
    gpiodriver.setPullupMode(_settings.gpio_resetbutton, RPIGPIO_PUD_UP);
    writeln('Done');
  end else begin
    writeln('Not in use');
  end;

  write('tdaemon: Notifying the microcontroller that we have booted: ');
  gpiodriver.setPin(_settings.gpio_powerup);
  writeln('Done');

  writeln('tdaemon: Monitoring the shutdown button.');
  if _settings.gpio_useresetbutton then begin
    writeln('tdaemon: Monitoring the reset button.');
  end;

  self.lastConfigCheckTime := unixtimeint;

  // Enable timers
  self.buttonCheckTimer.enabled := true;
  if assigned(self.configCheckTimer) then begin
    self.configCheckTimer.enabled := true;
  end;

  messageloop;

  // Disable timers
  if assigned(self.configCheckTimer) then begin
    self.configCheckTimer.enabled := false;
  end;
  self.buttonCheckTimer.enabled := false;
end;

{ ----------------------------------------------------------------------------
  ---------------------------------------------------------------------------- }
end.
