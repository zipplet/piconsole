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
      DS4CheckTimer: tltimer;
      lastConfigCheckTime: tunixtimeint;
      DS4BlinkState: boolean;

      // Timer events
      procedure DS4CheckTimerEvent(Sender: TObject);
      procedure ButtonCheckTimerEvent(Sender: TObject);
      procedure ConfigCheckTimerEvent(Sender: TObject);

      procedure CheckConfigurationChangesSince(ts: tunixtimeint);
      procedure CloseRetroarch;
      procedure PollDualshock4Controllers;
      procedure SetDualshock4Color(deviceName: ansistring; red, green, blue: longint);
    public
      procedure FixControllerConfigurationFiles;

      procedure StartShutdown;
      procedure RunDaemon;
      constructor Create;
      destructor Destroy; override;
  end;

implementation

uses process, unitglobal;

{ ---------------------------------------------------------------------------
  Set the colour of a DualShock 4 lightbar to the given RGB values.
  --------------------------------------------------------------------------- }
procedure tdaemon.SetDualshock4Color(deviceName: ansistring; red, green, blue: longint);
var
  t: textfile;
begin
  filemode := fmOpenWrite;
  assignfile(t, SYSTEM_LED_PATH + deviceName + DUALSHOCK4_RED_LED);
  rewrite(t);
  writeln(t, inttostr(red));
  closefile(t);

  filemode := fmOpenWrite;
  assignfile(t, SYSTEM_LED_PATH + deviceName + DUALSHOCK4_GREEN_LED);
  rewrite(t);
  writeln(t, inttostr(green));
  closefile(t);

  filemode := fmOpenWrite;
  assignfile(t, SYSTEM_LED_PATH + deviceName + DUALSHOCK4_BLUE_LED);
  rewrite(t);
  writeln(t, inttostr(blue));
  closefile(t);
end;

{ ---------------------------------------------------------------------------
  Called to poll DualShock 4 controllers.
  We will set the correct lightbar colours on each controller.
  --------------------------------------------------------------------------- }
procedure tdaemon.PollDualshock4Controllers;
var
  fileinfo: tsearchrec;
  s, fullpath: ansistring;
  t: textfile;
  batteryCharge: longint;
  realDevice: ansistring;
  i: longint;
  lowBattery: boolean;
  fastTimer: boolean;
begin
  // Toggle blink state
  if self.DS4BlinkState then begin
    self.DS4BlinkState := false;
  end else begin
    self.DS4BlinkState := true;
  end;

  fastTimer := false;

  if FindFirst(SYSTEM_POWER_PATH + DUALSHOCK4_BATTERY_SEARCH_MASK, faDirectory, fileinfo) = 0 then begin
    repeat
      try
        // Get the battery charge of each controller, plus the real device name
        fullpath := SYSTEM_POWER_PATH + fileinfo.name + DUALSHOCK4_BATTERY_CHARGE;
        filemode := fmOpenRead;
        assignfile(t, fullpath);
        reset(t);
        readln(t, s);
        closefile(t);
        batteryCharge := strtoint(s);
        fullpath := SYSTEM_POWER_PATH + fileinfo.name + DUALSHOCK4_REAL_DEVICE;
        s := fpReadLink(fullpath);
        realDevice := '';
        // We need to hunt backwards for the '/'
        for i := length(s) downto 1 do begin
          if s[i] = '/' then begin
            realDevice := copy(s, i + 1, length(s) - i);
            break;
          end;
        end;
        if realDevice <> '' then begin
          // We have the device name in <realDevice> and charge in <batteryCharge>
          lowBattery := false;
          if _settings.dualshock4_battery_low_warning then begin
            if batteryCharge <= _settings.dualshock4_battery_warning_below then begin
              lowBattery := true;
              fastTimer := true;
            end;
          end;
          if self.DS4BlinkState and lowBattery then begin
            self.SetDualshock4Color(realDevice,
                                    _settings.dualshock4_battery_low_color_red,
                                    _settings.dualshock4_battery_low_color_green,
                                    _settings.dualshock4_battery_low_color_blue);
          end else begin
            self.SetDualshock4Color(realDevice,
                                    _settings.dualshock4_static_color_red,
                                    _settings.dualshock4_static_color_green,
                                    _settings.dualshock4_static_color_blue);
          end;
        end;
      except
        on e: exception do begin
          closefile(t);
          // Swallow the exception. Maybe dump debugging output, but I don't
          // want to fill the RAM disk or wear out the SD card.
        end;
      end;
    until FindNext(fileinfo) <> 0;
  end;
  FindClose(fileinfo);

  if fastTimer then begin
    // Increase timer poll rate temporarily to allow LED flashing
    // Yes I could use more timers, but this works.
    self.DS4CheckTimer.interval := _settings.dualshock4_battery_low_blinkrate;
  end else begin
    // Increase timer poll rate as we have no controllers with a low battery
    self.DS4CheckTimer.interval := _settings.dualshock4_poll_interval * 1000;
  end;
end;

{ ---------------------------------------------------------------------------
  Timer: Check DualShock 4 battery levels and set lightbar colours
  --------------------------------------------------------------------------- }
procedure tdaemon.DS4CheckTimerEvent(Sender: TObject);
begin
  self.DS4CheckTimer.enabled := false;

  self.PollDualshock4Controllers;

  self.DS4CheckTimer.enabled := true;
end;

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
      write('tdaemon: Starting shutdown process.');
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
    process.executable := '/opt/piconsole/mypoweroff.sh';
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

  if _settings.dualshock4_enabled then begin
    self.DS4CheckTimer := tltimer.Create(nil);
    self.DS4CheckTimer.onTimer := self.DS4CheckTimerEvent;
    self.DS4CheckTimer.interval := _settings.dualshock4_poll_interval * 1000;
    self.DS4CheckTimer.enabled := false;
  end;

  self.DS4BlinkState := false;
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
  if _settings.dualshock4_enabled then begin
    writeln('tdaemon: Monitoring DualShock 4 controllers.');
  end;

  // Enable timers
  self.buttonCheckTimer.enabled := true;
  if assigned(self.configCheckTimer) then begin
    self.lastConfigCheckTime := unixtimeint;
    self.configCheckTimer.enabled := true;
  end;
  if assigned(self.DS4CheckTimer) then begin
    self.DS4CheckTimer.enabled := true;
  end;

  // Enter lcore message loop (will not return until the daamon shuts down)
  messageloop;

  // Disable timers
  if assigned(self.DS4CheckTimer) then begin
    self.DS4CheckTimer.onTimer := nil;
    self.DS4CheckTimer.enabled := false;
    self.DS4CheckTimer.release;
    self.DS4CheckTimer := nil;
  end;
  if assigned(self.configCheckTimer) then begin
    self.configCheckTimer.onTimer := nil;
    self.configCheckTimer.enabled := false;
    self.configCheckTimer.release;
    self.configCheckTimer := nil;
  end;
  self.buttonCheckTimer.onTimer := nil;
  self.buttonCheckTimer.enabled := false;
  self.buttonCheckTimer.release;
  self.buttonCheckTimer := nil;
end;

{ ----------------------------------------------------------------------------
  ---------------------------------------------------------------------------- }
end.
