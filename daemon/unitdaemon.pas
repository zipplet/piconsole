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

// Yes it could be done neater by using a linked list or so, but since we will
// never have many DS4 controllers attached, a static limit and array is fine.
// If we exceed this many controllers, the new ones will just not be monitored.
const
  MAX_DS4_CONTROLLERS = 8;        // Should never need more than this...

type
  rDualShock4 = record
    deviceName: shortstring;      // DS4 device name ("xxxx:xxxx:xxxx.xxxx")
    batteryName: shortstring;     // DS4 battery name ("sony_controller_battery_xx:xx:xx:xx:xx:xx")
    batteryLevel: longint;        // Battery charge in %
    lowBattery: boolean;          // True if low battery
    blinkState: boolean;          // Toggles to alter lightbar colour
    lightbar_red: longint;        // LB colour for non-low battery: red
    lightbar_green: longint;      // LB colour for non-low battery: green
    lightbar_blue: longint;       // LB colour for non-low battery: blue
    attached: boolean;            // True if controller is present
  end;

  tdaemon = class(tobject)
    private
    protected
      gpiodriver: trpiGPIO;
      buttonCheckTimer: tltimer;
      configCheckTimer: tltimer;
      DS4CheckTimer: tltimer;
      DS4BatteryLowTimer: tltimer;
      lastConfigCheckTime: tunixtimeint;
      DS4BatteryPollCounter: longint;

      ds4controller: array[0..MAX_DS4_CONTROLLERS - 1] of rDualShock4;

      // Timer events
      procedure DS4CheckTimerEvent(Sender: TObject);
      procedure ButtonCheckTimerEvent(Sender: TObject);
      procedure ConfigCheckTimerEvent(Sender: TObject);
      procedure DS4BatteryLowTimerEvent(Sender: TObject);

      procedure CheckConfigurationChangesSince(ts: tunixtimeint);
      procedure CloseRetroarch;
      procedure PollDualshock4Controllers;
      procedure SetDualshock4Color(deviceID: longint; red, green, blue: longint);
      function FindDS4ControllerByDeviceName(deviceName: ansistring): longint;
      function GetFreeDS4ControllerID: longint;
      procedure CheckDS4Battery(deviceID: longint);
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
  DS4 battery low blink timer event
  --------------------------------------------------------------------------- }
procedure tdaemon.DS4BatteryLowTimerEvent(Sender: TObject);
var
  i: longint;
begin
  self.DS4BatteryLowTimer.enabled := false;

  for i := 0 to MAX_DS4_CONTROLLERS - 1 do begin
    if self.ds4controller[i].attached then begin
      // Low battery?
      if self.ds4controller[i].lowBattery then begin
        // Yup. Toggle the blink flag
        if self.ds4controller[i].blinkState then begin
          self.ds4controller[i].blinkState := false;
        end else begin
          self.ds4controller[i].blinkState := true;
        end;
        // Now assign the appropriate colour
        if self.ds4controller[i].blinkState then begin
          self.SetDualshock4Color(i,
                                  _settings.dualshock4_battery_low_color_red,
                                  _settings.dualshock4_battery_low_color_green,
                                  _settings.dualshock4_battery_low_color_blue);
        end else begin
          self.SetDualshock4Color(i,
                                  self.ds4controller[i].lightbar_red,
                                  self.ds4controller[i].lightbar_green,
                                  self.ds4controller[i].lightbar_blue);
        end;
      end;
    end;
  end;

  self.DS4BatteryLowTimer.enabled := true;
end;

{ ---------------------------------------------------------------------------
  Check the battery state of the DS4 controller ID passed, and set the low
  battery flag if required (or clear it if the battery is OK).
  --------------------------------------------------------------------------- }
procedure tdaemon.CheckDS4Battery(deviceID: longint);
var
  t: textfile;
  s, fullpath: ansistring;
  batteryCharge: longint;
  wasLowBattery: boolean;
begin
  try
    // Get the battery charge of each controller, plus the real device name
    fullpath := SYSTEM_POWER_PATH + self.ds4controller[deviceID].batteryName + DUALSHOCK4_BATTERY_CHARGE;
    filemode := fmOpenRead;
    assignfile(t, fullpath);
    reset(t);
    readln(t, s);
    closefile(t);
    self.ds4controller[deviceID].batteryLevel := strtoint(s);
    wasLowBattery := self.ds4controller[deviceID].lowBattery;
    self.ds4controller[deviceID].lowBattery := false;
    if _settings.dualshock4_battery_low_warning then begin
      if self.ds4controller[deviceID].batteryLevel <= _settings.dualshock4_battery_warning_below then begin
        self.ds4controller[deviceID].lowBattery := true;
      end else begin
        // Has the battery recovered since we last checked it?
        if wasLowBattery then begin
          // Yes. Make sure the lightbar colour is correct.
          self.SetDualshock4Color(deviceID,
                                  self.ds4controller[deviceID].lightbar_red,
                                  self.ds4controller[deviceID].lightbar_green,
                                  self.ds4controller[deviceID].lightbar_blue);
        end;
      end;
    end;
  except
    on e: exception do begin
      try
        closefile(t);
      except
        on e: exception do begin
          // Swallow
        end;
      end;
      // Swallow the exception. Maybe dump debugging output, but I don't
      // want to fill the RAM disk or wear out the SD card.
    end;
  end;
end;

{ ---------------------------------------------------------------------------
  Find the first free device ID and return it.
  Returns -1 if we cannot find one.
  --------------------------------------------------------------------------- }
function tdaemon.GetFreeDS4ControllerID: longint;
var
  i: longint;
begin
  for i := 0 to MAX_DS4_CONTROLLERS - 1 do begin
    if self.ds4controller[i].attached = false then begin
      result := i;
      exit;
    end;
  end;
  result := -1;
end;

{ ---------------------------------------------------------------------------
  Find the index of a DS4 controller given the device name.
  Returns -1 if we cannot find it.
  --------------------------------------------------------------------------- }
function tdaemon.FindDS4ControllerByDeviceName(deviceName: ansistring): longint;
var
  i: longint;
begin
  for i := 0 to MAX_DS4_CONTROLLERS - 1 do begin
    if self.ds4controller[i].deviceName = deviceName then begin
      result := i;
      exit;
    end;
  end;
  result := -1;
end;

{ ---------------------------------------------------------------------------
  Set the colour of a DualShock 4 lightbar to the given RGB values.
  --------------------------------------------------------------------------- }
procedure tdaemon.SetDualshock4Color(deviceID: longint; red, green, blue: longint);
var
  t: textfile;
  s: ansistring;
begin
  try
    s := SYSTEM_LED_PATH + self.ds4controller[deviceID].deviceName + DUALSHOCK4_RED_LED;
    // Check if controller vanished and bail; will be caught on next poll loop
    if not fileexists(s) then exit;
    filemode := fmOpenWrite;
    assignfile(t, s);
    rewrite(t);
    writeln(t, inttostr(red));
    closefile(t);

    s := SYSTEM_LED_PATH + self.ds4controller[deviceID].deviceName + DUALSHOCK4_GREEN_LED;
    // Check if controller vanished and bail; will be caught on next poll loop
    if not fileexists(s) then exit;
    filemode := fmOpenWrite;
    assignfile(t, s);
    rewrite(t);
    writeln(t, inttostr(green));
    closefile(t);

    s := SYSTEM_LED_PATH + self.ds4controller[deviceID].deviceName + DUALSHOCK4_BLUE_LED;
    // Check if controller vanished and bail; will be caught on next poll loop
    if not fileexists(s) then exit;
    filemode := fmOpenWrite;
    assignfile(t, s);
    rewrite(t);
    writeln(t, inttostr(blue));
    closefile(t);
  except
    on e: exception do begin
      // Controller vanished while accessing it
      try
        // Make sure we don't leak fds
        closefile(t);
      except
        on e: exception do begin
          // Shouldn't happen. Swallow it
        end;
      end;
    end;
  end;
end;

{ ---------------------------------------------------------------------------
  Called to poll DualShock 4 controllers (look for new controllers).
  --------------------------------------------------------------------------- }
procedure tdaemon.PollDualshock4Controllers;
var
  fileinfo: tsearchrec;
  s, fullpath: ansistring;
  realDevice: ansistring;
  i: longint;
  lowBattery: boolean;
  deviceIndex: longint;
begin
  // Look through all DS4 devices attached to the system, and add controllers
  // as necessary to the internal list.
  if FindFirst(SYSTEM_POWER_PATH + DUALSHOCK4_BATTERY_SEARCH_MASK, faDirectory, fileinfo) = 0 then begin
    repeat
      fullpath := SYSTEM_POWER_PATH + fileinfo.name + DUALSHOCK4_REAL_DEVICE;
      // fpReadLink might fail if the controller goes away while checking!
      s := fpReadLink(fullpath);
      realDevice := '';
      if s <> '' then begin
        // We need to hunt backwards for the '/' to get the real device name
        for i := length(s) downto 1 do begin
          if s[i] = '/' then begin
            realDevice := copy(s, i + 1, length(s) - i);
            break;
          end;
        end;
      end;
      // If we have a real device name, then check if we know about it.
      if realDevice <> '' then begin
        // See if we already know about this controller
        deviceIndex := self.FindDS4ControllerByDeviceName(realDevice);
        if deviceIndex = -1 then begin
          // New device!
          deviceIndex := self.GetFreeDS4ControllerID;
          if deviceIndex <> -1 then begin
            // Got a device ID to store information about it under.
            self.ds4controller[deviceIndex].deviceName := realDevice;
            self.ds4controller[deviceIndex].batteryName := fileinfo.name;
            self.ds4controller[deviceIndex].batteryLevel := -1;
            self.ds4controller[deviceIndex].lowBattery := false;
            self.ds4controller[deviceIndex].attached := true;
            // Currently all controllers are assigned the same colour
            self.ds4controller[deviceIndex].lightbar_red := _settings.dualshock4_static_color_red;
            self.ds4controller[deviceIndex].lightbar_green := _settings.dualshock4_static_color_green;
            self.ds4controller[deviceIndex].lightbar_blue := _settings.dualshock4_static_color_blue;
            // Set DS4 colour appropriately
            self.SetDualshock4Color(deviceIndex,
                                    self.ds4controller[deviceIndex].lightbar_red,
                                    self.ds4controller[deviceIndex].lightbar_green,
                                    self.ds4controller[deviceIndex].lightbar_blue);
            // Perform the low battery check immediately as this is a new controller
            self.CheckDS4Battery(deviceIndex);
          end else begin
            // Should never happen, some kind of error log?
          end;
        end;
      end;
    until FindNext(fileinfo) <> 0;
  end;
  FindClose(fileinfo);

  // Now do the inverse, check if all known DS4 controllers still exist.
  for i := 0 to MAX_DS4_CONTROLLERS - 1 do begin
    if self.ds4controller[i].attached then begin
      if not fileexists(SYSTEM_POWER_PATH + self.ds4controller[i].batteryName + DUALSHOCK4_BATTERY_CHARGE) then begin
        // Controller vanished
        self.ds4controller[i].attached := false;
      end;
    end;
  end;

  // Count up towards the next battery check for all attached DS4 controllers
  inc(self.DS4BatteryPollCounter);
  if self.DS4BatteryPollCounter >= _settings.dualshock4_battery_check_interval then begin
    // Check the battery levels of all DS4 controllers
    for i := 0 to MAX_DS4_CONTROLLERS - 1 do begin
      if self.ds4controller[i].attached then begin
        self.CheckDS4Battery(i);
      end;
    end;
    self.DS4BatteryPollCounter := 0;
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
var
  i: longint;
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
    self.DS4BatteryLowTimer := tltimer.Create(nil);
    self.DS4BatteryLowTimer.onTimer := self.DS4BatteryLowTimerEvent;
    self.DS4BatteryLowTimer.interval := _settings.dualshock4_battery_low_blinkrate;
    self.DS4BatteryLowTimer.enabled := false;
  end;

  for i := 0 to MAX_DS4_CONTROLLERS - 1 do begin
    self.ds4controller[i].attached := false;
  end;
  self.DS4BatteryPollCounter := 0;
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
  if assigned(self.DS4BatteryLowTimer) then begin
    self.DS4BatteryLowTimer.enabled := true;
  end;

  // Enter lcore message loop (will not return until the daamon shuts down)
  messageloop;

  // Disable timers
  if assigned(self.DS4BatteryLowTimer) then begin
    self.DS4BatteryLowTimer.onTimer := nil;
    self.DS4BatteryLowTimer.enabled := false;
    self.DS4BatteryLowTimer.release;
    self.DS4BatteryLowTimer := nil;
  end;
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
