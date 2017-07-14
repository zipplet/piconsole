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
  unitconfig in 'unitconfig.pas';

var
  gpiodriver: trpiGPIO;
  i: longint;
  lasttime: tunixtimeint;

{ ---------------------------------------------------------------------------
  Fixup controller configurations saved by RetroPie to disable unwanted
  hotkeys that the user does not desire.
  --------------------------------------------------------------------------- }
procedure FixControllerConfigurations;
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
  writeln('Scanning for and fixing controller configuration files in ' + _settings.controller_configdir + '...');
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
        writeln('Exception processing controller configuration: ' + e.message);
        closefile(infile);
        if assigned(sl) then begin
          freeandnil(sl);
        end;
      end;
    end;
  end;

  freeandnil(sl);
end;

{ ---------------------------------------------------------------------------
  Check if any controller configuration files have been modified since <ts>,
  and if they have fix them.
  --------------------------------------------------------------------------- }
procedure CheckConfigurationChangesSince(ts: tunixtimeint);
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
    writeln('Found changed controller configuration files.');
    FixControllerConfigurations;
  end;
end;

{ ---------------------------------------------------------------------------
  Close Retroarch nicely if running
  --------------------------------------------------------------------------- }
procedure CloseRetroarch;
var
  process: tprocess;
begin
  writeln('Trying to kill retroarch nicely if it is running');
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
      writeln('Exception while trying to stop retroarch: ' + e.message);
      end;
  end;
end;

{ --------------------------------------------------------------------------- 
  Begin system shutdown
  --------------------------------------------------------------------------- }
procedure StartShutdown;
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
      writeln('Exception while trying to shutdown: ' + e.message);
    end;
  end;
end;

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
        writeln('15. Disclaimer of Warranty.');
        writeln;
        writeln('  THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY');
        writeln('APPLICABLE LAW.  EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT');
        writeln('HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM "AS IS" WITHOUT WARRANTY');
        writeln('OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO,');
        writeln('THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR');
        writeln('PURPOSE.  THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM');
        writeln('IS WITH YOU.  SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF');
        writeln('ALL NECESSARY SERVICING, REPAIR OR CORRECTION.');
        writeln;
        writeln('Type --license to view the entire license.');
        exit;
      end else if lowercase(paramstr(1)) = '--license' then begin
        writeln('                    GNU GENERAL PUBLIC LICENSE');
        writeln('                       Version 3, 29 June 2007');
        writeln;
        writeln(' Copyright (C) 2007 Free Software Foundation, Inc. <http://fsf.org/>');
        writeln(' Everyone is permitted to copy and distribute verbatim copies');
        writeln(' of this license document, but changing it is not allowed.');
        writeln;
        writeln('                            Preamble');
        writeln;
        writeln('  The GNU General Public License is a free, copyleft license for');
        writeln('software and other kinds of works.');
        writeln;
        writeln('  The licenses for most software and other practical works are designed');
        writeln('to take away your freedom to share and change the works.  By contrast,');
        writeln('the GNU General Public License is intended to guarantee your freedom to');
        writeln('share and change all versions of a program--to make sure it remains free');
        writeln('software for all its users.  We, the Free Software Foundation, use the');
        writeln('GNU General Public License for most of our software; it applies also to');
        writeln('any other work released this way by its authors.  You can apply it to');
        writeln('your programs, too.');
        writeln;
        writeln('  When we speak of free software, we are referring to freedom, not');
        writeln('price.  Our General Public Licenses are designed to make sure that you');
        writeln('have the freedom to distribute copies of free software (and charge for');
        writeln('them if you wish), that you receive source code or can get it if you');
        writeln('want it, that you can change the software or use pieces of it in new');
        writeln('free programs, and that you know you can do these things.');
        writeln;
        writeln('  To protect your rights, we need to prevent others from denying you');
        writeln('these rights or asking you to surrender the rights.  Therefore, you have');
        writeln('certain responsibilities if you distribute copies of the software, or if');
        writeln('you modify it: responsibilities to respect the freedom of others.');
        writeln;
        writeln('  For example, if you distribute copies of such a program, whether');
        writeln('gratis or for a fee, you must pass on to the recipients the same');
        writeln('freedoms that you received.  You must make sure that they, too, receive');
        writeln('or can get the source code.  And you must show them these terms so they');
        writeln('know their rights.');
        writeln;
        writeln('  Developers that use the GNU GPL protect your rights with two steps:');
        writeln('(1) assert copyright on the software, and (2) offer you this License');
        writeln('giving you legal permission to copy, distribute and/or modify it.');
        writeln;
        writeln('  For the developers'' and authors'' protection, the GPL clearly explains');
        writeln('that there is no warranty for this free software.  For both users'' and');
        writeln('authors'' sake, the GPL requires that modified versions be marked as');
        writeln('changed, so that their problems will not be attributed erroneously to');
        writeln('authors of previous versions.');
        writeln;
        writeln('  Some devices are designed to deny users access to install or run');
        writeln('modified versions of the software inside them, although the manufacturer');
        writeln('can do so.  This is fundamentally incompatible with the aim of');
        writeln('protecting users'' freedom to change the software.  The systematic');
        writeln('pattern of such abuse occurs in the area of products for individuals to');
        writeln('use, which is precisely where it is most unacceptable.  Therefore, we');
        writeln('have designed this version of the GPL to prohibit the practice for those');
        writeln('products.  If such problems arise substantially in other domains, we');
        writeln('stand ready to extend this provision to those domains in future versions');
        writeln('of the GPL, as needed to protect the freedom of users.');
        writeln;
        writeln('  Finally, every program is threatened constantly by software patents.');
        writeln('States should not allow patents to restrict development and use of');
        writeln('software on general-purpose computers, but in those that do, we wish to');
        writeln('avoid the special danger that patents applied to a free program could');
        writeln('make it effectively proprietary.  To prevent this, the GPL assures that');
        writeln('patents cannot be used to render the program non-free.');
        writeln;
        writeln('  The precise terms and conditions for copying, distribution and');
        writeln('modification follow.');
        writeln;
        writeln('                       TERMS AND CONDITIONS');
        writeln;
        writeln('  0. Definitions.');
        writeln;
        writeln('  "This License" refers to version 3 of the GNU General Public License.');
        writeln;
        writeln('  "Copyright" also means copyright-like laws that apply to other kinds of');
        writeln('works, such as semiconductor masks.');
        writeln;
        writeln('  "The Program" refers to any copyrightable work licensed under this');
        writeln('License.  Each licensee is addressed as "you".  "Licensees" and');
        writeln('"recipients" may be individuals or organizations.');
        writeln;
        writeln('  To "modify" a work means to copy from or adapt all or part of the work');
        writeln('in a fashion requiring copyright permission, other than the making of an');
        writeln('exact copy.  The resulting work is called a "modified version" of the');
        writeln('earlier work or a work "based on" the earlier work.');
        writeln;
        writeln('  A "covered work" means either the unmodified Program or a work based');
        writeln('on the Program.');
        writeln;
        writeln('  To "propagate" a work means to do anything with it that, without');
        writeln('permission, would make you directly or secondarily liable for');
        writeln('infringement under applicable copyright law, except executing it on a');
        writeln('computer or modifying a private copy.  Propagation includes copying,');
        writeln('distribution (with or without modification), making available to the');
        writeln('public, and in some countries other activities as well.');
        writeln;
        writeln('  To "convey" a work means any kind of propagation that enables other');
        writeln('parties to make or receive copies.  Mere interaction with a user through');
        writeln('a computer network, with no transfer of a copy, is not conveying.');
        writeln;
        writeln('  An interactive user interface displays "Appropriate Legal Notices"');
        writeln('to the extent that it includes a convenient and prominently visible');
        writeln('feature that (1) displays an appropriate copyright notice, and (2)');
        writeln('tells the user that there is no warranty for the work (except to the');
        writeln('extent that warranties are provided), that licensees may convey the');
        writeln('work under this License, and how to view a copy of this License.  If');
        writeln('the interface presents a list of user commands or options, such as a');
        writeln('menu, a prominent item in the list meets this criterion.');
        writeln;
        writeln('  1. Source Code.');
        writeln;
        writeln('  The "source code" for a work means the preferred form of the work');
        writeln('for making modifications to it.  "Object code" means any non-source');
        writeln('form of a work.');
        writeln;
        writeln('  A "Standard Interface" means an interface that either is an official');
        writeln('standard defined by a recognized standards body, or, in the case of');
        writeln('interfaces specified for a particular programming language, one that');
        writeln('is widely used among developers working in that language.');
        writeln;
        writeln('  The "System Libraries" of an executable work include anything, other');
        writeln('than the work as a whole, that (a) is included in the normal form of');
        writeln('packaging a Major Component, but which is not part of that Major');
        writeln('Component, and (b) serves only to enable use of the work with that');
        writeln('Major Component, or to implement a Standard Interface for which an');
        writeln('implementation is available to the public in source code form.  A');
        writeln('"Major Component", in this context, means a major essential component');
        writeln('(kernel, window system, and so on) of the specific operating system');
        writeln('(if any) on which the executable work runs, or a compiler used to');
        writeln('produce the work, or an object code interpreter used to run it.');
        writeln;
        writeln('  The "Corresponding Source" for a work in object code form means all');
        writeln('the source code needed to generate, install, and (for an executable');
        writeln('work) run the object code and to modify the work, including scripts to');
        writeln('control those activities.  However, it does not include the work''s');
        writeln('System Libraries, or general-purpose tools or generally available free');
        writeln('programs which are used unmodified in performing those activities but');
        writeln('which are not part of the work.  For example, Corresponding Source');
        writeln('includes interface definition files associated with source files for');
        writeln('the work, and the source code for shared libraries and dynamically');
        writeln('linked subprograms that the work is specifically designed to require,');
        writeln('such as by intimate data communication or control flow between those');
        writeln('subprograms and other parts of the work.');
        writeln;
        writeln('  The Corresponding Source need not include anything that users');
        writeln('can regenerate automatically from other parts of the Corresponding');
        writeln('Source.');
        writeln;
        writeln('  The Corresponding Source for a work in source code form is that');
        writeln('same work.');
        writeln;
        writeln('  2. Basic Permissions.');
        writeln;
        writeln('  All rights granted under this License are granted for the term of');
        writeln('copyright on the Program, and are irrevocable provided the stated');
        writeln('conditions are met.  This License explicitly affirms your unlimited');
        writeln('permission to run the unmodified Program.  The output from running a');
        writeln('covered work is covered by this License only if the output, given its');
        writeln('content, constitutes a covered work.  This License acknowledges your');
        writeln('rights of fair use or other equivalent, as provided by copyright law.');
        writeln;
        writeln('  You may make, run and propagate covered works that you do not');
        writeln('convey, without conditions so long as your license otherwise remains');
        writeln('in force.  You may convey covered works to others for the sole purpose');
        writeln('of having them make modifications exclusively for you, or provide you');
        writeln('with facilities for running those works, provided that you comply with');
        writeln('the terms of this License in conveying all material for which you do');
        writeln('not control copyright.  Those thus making or running the covered works');
        writeln('for you must do so exclusively on your behalf, under your direction');
        writeln('and control, on terms that prohibit them from making any copies of');
        writeln('your copyrighted material outside their relationship with you.');
        writeln;
        writeln('  Conveying under any other circumstances is permitted solely under');
        writeln('the conditions stated below.  Sublicensing is not allowed; section 10');
        writeln('makes it unnecessary.');
        writeln;
        writeln('  3. Protecting Users'' Legal Rights From Anti-Circumvention Law.');
        writeln;
        writeln('  No covered work shall be deemed part of an effective technological');
        writeln('measure under any applicable law fulfilling obligations under article');
        writeln('11 of the WIPO copyright treaty adopted on 20 December 1996, or');
        writeln('similar laws prohibiting or restricting circumvention of such');
        writeln('measures.');
        writeln;
        writeln('  When you convey a covered work, you waive any legal power to forbid');
        writeln('circumvention of technological measures to the extent such circumvention');
        writeln('is effected by exercising rights under this License with respect to');
        writeln('the covered work, and you disclaim any intention to limit operation or');
        writeln('modification of the work as a means of enforcing, against the work''s');
        writeln('users, your or third parties'' legal rights to forbid circumvention of');
        writeln('technological measures.');
        writeln;
        writeln('  4. Conveying Verbatim Copies.');
        writeln;
        writeln('  You may convey verbatim copies of the Program''s source code as you');
        writeln('receive it, in any medium, provided that you conspicuously and');
        writeln('appropriately publish on each copy an appropriate copyright notice;');
        writeln('keep intact all notices stating that this License and any');
        writeln('non-permissive terms added in accord with section 7 apply to the code;');
        writeln('keep intact all notices of the absence of any warranty; and give all');
        writeln('recipients a copy of this License along with the Program.');
        writeln;
        writeln('  You may charge any price or no price for each copy that you convey,');
        writeln('and you may offer support or warranty protection for a fee.');
        writeln;
        writeln('  5. Conveying Modified Source Versions.');
        writeln;
        writeln('  You may convey a work based on the Program, or the modifications to');
        writeln('produce it from the Program, in the form of source code under the');
        writeln('terms of section 4, provided that you also meet all of these conditions:');
        writeln;
        writeln('    a) The work must carry prominent notices stating that you modified');
        writeln('    it, and giving a relevant date.');
        writeln;
        writeln('    b) The work must carry prominent notices stating that it is');
        writeln('    released under this License and any conditions added under section');
        writeln('    7.  This requirement modifies the requirement in section 4 to');
        writeln('    "keep intact all notices".');
        writeln;
        writeln('    c) You must license the entire work, as a whole, under this');
        writeln('    License to anyone who comes into possession of a copy.  This');
        writeln('    License will therefore apply, along with any applicable section 7');
        writeln('    additional terms, to the whole of the work, and all its parts,');
        writeln('    regardless of how they are packaged.  This License gives no');
        writeln('    permission to license the work in any other way, but it does not');
        writeln('    invalidate such permission if you have separately received it.');
        writeln;
        writeln('    d) If the work has interactive user interfaces, each must display');
        writeln('    Appropriate Legal Notices; however, if the Program has interactive');
        writeln('    interfaces that do not display Appropriate Legal Notices, your');
        writeln('    work need not make them do so.');
        writeln;
        writeln('  A compilation of a covered work with other separate and independent');
        writeln('works, which are not by their nature extensions of the covered work,');
        writeln('and which are not combined with it such as to form a larger program,');
        writeln('in or on a volume of a storage or distribution medium, is called an');
        writeln('"aggregate" if the compilation and its resulting copyright are not');
        writeln('used to limit the access or legal rights of the compilation''s users');
        writeln('beyond what the individual works permit.  Inclusion of a covered work');
        writeln('in an aggregate does not cause this License to apply to the other');
        writeln('parts of the aggregate.');
        writeln;
        writeln('  6. Conveying Non-Source Forms.');
        writeln;
        writeln('  You may convey a covered work in object code form under the terms');
        writeln('of sections 4 and 5, provided that you also convey the');
        writeln('machine-readable Corresponding Source under the terms of this License,');
        writeln('in one of these ways:');
        writeln;
        writeln('    a) Convey the object code in, or embodied in, a physical product');
        writeln('    (including a physical distribution medium), accompanied by the');
        writeln('    Corresponding Source fixed on a durable physical medium');
        writeln('    customarily used for software interchange.');
        writeln;
        writeln('    b) Convey the object code in, or embodied in, a physical product');
        writeln('    (including a physical distribution medium), accompanied by a');
        writeln('    written offer, valid for at least three years and valid for as');
        writeln('    long as you offer spare parts or customer support for that product');
        writeln('    model, to give anyone who possesses the object code either (1) a');
        writeln('    copy of the Corresponding Source for all the software in the');
        writeln('    product that is covered by this License, on a durable physical');
        writeln('    medium customarily used for software interchange, for a price no');
        writeln('    more than your reasonable cost of physically performing this');
        writeln('    conveying of source, or (2) access to copy the');
        writeln('    Corresponding Source from a network server at no charge.');
        writeln;
        writeln('    c) Convey individual copies of the object code with a copy of the');
        writeln('    written offer to provide the Corresponding Source.  This');
        writeln('    alternative is allowed only occasionally and noncommercially, and');
        writeln('    only if you received the object code with such an offer, in accord');
        writeln('    with subsection 6b.');
        writeln;
        writeln('    d) Convey the object code by offering access from a designated');
        writeln('    place (gratis or for a charge), and offer equivalent access to the');
        writeln('    Corresponding Source in the same way through the same place at no');
        writeln('    further charge.  You need not require recipients to copy the');
        writeln('    Corresponding Source along with the object code.  If the place to');
        writeln('    copy the object code is a network server, the Corresponding Source');
        writeln('    may be on a different server (operated by you or a third party)');
        writeln('    that supports equivalent copying facilities, provided you maintain');
        writeln('    clear directions next to the object code saying where to find the');
        writeln('    Corresponding Source.  Regardless of what server hosts the');
        writeln('    Corresponding Source, you remain obligated to ensure that it is');
        writeln('    available for as long as needed to satisfy these requirements.');
        writeln;
        writeln('    e) Convey the object code using peer-to-peer transmission, provided');
        writeln('    you inform other peers where the object code and Corresponding');
        writeln('    Source of the work are being offered to the general public at no');
        writeln('    charge under subsection 6d.');
        writeln;
        writeln('  A separable portion of the object code, whose source code is excluded');
        writeln('from the Corresponding Source as a System Library, need not be');
        writeln('included in conveying the object code work.');
        writeln;
        writeln('  A "User Product" is either (1) a "consumer product", which means any');
        writeln('tangible personal property which is normally used for personal, family,');
        writeln('or household purposes, or (2) anything designed or sold for incorporation');
        writeln('into a dwelling.  In determining whether a product is a consumer product,');
        writeln('doubtful cases shall be resolved in favor of coverage.  For a particular');
        writeln('product received by a particular user, "normally used" refers to a');
        writeln('typical or common use of that class of product, regardless of the status');
        writeln('of the particular user or of the way in which the particular user');
        writeln('actually uses, or expects or is expected to use, the product.  A product');
        writeln('is a consumer product regardless of whether the product has substantial');
        writeln('commercial, industrial or non-consumer uses, unless such uses represent');
        writeln('the only significant mode of use of the product.');
        writeln;
        writeln('  "Installation Information" for a User Product means any methods,');
        writeln('procedures, authorization keys, or other information required to install');
        writeln('and execute modified versions of a covered work in that User Product from');
        writeln('a modified version of its Corresponding Source.  The information must');
        writeln('suffice to ensure that the continued functioning of the modified object');
        writeln('code is in no case prevented or interfered with solely because');
        writeln('modification has been made.');
        writeln;
        writeln('  If you convey an object code work under this section in, or with, or');
        writeln('specifically for use in, a User Product, and the conveying occurs as');
        writeln('part of a transaction in which the right of possession and use of the');
        writeln('User Product is transferred to the recipient in perpetuity or for a');
        writeln('fixed term (regardless of how the transaction is characterized), the');
        writeln('Corresponding Source conveyed under this section must be accompanied');
        writeln('by the Installation Information.  But this requirement does not apply');
        writeln('if neither you nor any third party retains the ability to install');
        writeln('modified object code on the User Product (for example, the work has');
        writeln('been installed in ROM).');
        writeln;
        writeln('  The requirement to provide Installation Information does not include a');
        writeln('requirement to continue to provide support service, warranty, or updates');
        writeln('for a work that has been modified or installed by the recipient, or for');
        writeln('the User Product in which it has been modified or installed.  Access to a');
        writeln('network may be denied when the modification itself materially and');
        writeln('adversely affects the operation of the network or violates the rules and');
        writeln('protocols for communication across the network.');
        writeln;
        writeln('  Corresponding Source conveyed, and Installation Information provided,');
        writeln('in accord with this section must be in a format that is publicly');
        writeln('documented (and with an implementation available to the public in');
        writeln('source code form), and must require no special password or key for');
        writeln('unpacking, reading or copying.');
        writeln;
        writeln('  7. Additional Terms.');
        writeln;
        writeln('  "Additional permissions" are terms that supplement the terms of this');
        writeln('License by making exceptions from one or more of its conditions.');
        writeln('Additional permissions that are applicable to the entire Program shall');
        writeln('be treated as though they were included in this License, to the extent');
        writeln('that they are valid under applicable law.  If additional permissions');
        writeln('apply only to part of the Program, that part may be used separately');
        writeln('under those permissions, but the entire Program remains governed by');
        writeln('this License without regard to the additional permissions.');
        writeln;
        writeln('  When you convey a copy of a covered work, you may at your option');
        writeln('remove any additional permissions from that copy, or from any part of');
        writeln('it.  (Additional permissions may be written to require their own');
        writeln('removal in certain cases when you modify the work.)  You may place');
        writeln('additional permissions on material, added by you to a covered work,');
        writeln('for which you have or can give appropriate copyright permission.');
        writeln;
        writeln('  Notwithstanding any other provision of this License, for material you');
        writeln('add to a covered work, you may (if authorized by the copyright holders of');
        writeln('that material) supplement the terms of this License with terms:');
        writeln;
        writeln('    a) Disclaiming warranty or limiting liability differently from the');
        writeln('    terms of sections 15 and 16 of this License; or');
        writeln;
        writeln('    b) Requiring preservation of specified reasonable legal notices or');
        writeln('    author attributions in that material or in the Appropriate Legal');
        writeln('    Notices displayed by works containing it; or');
        writeln;
        writeln('    c) Prohibiting misrepresentation of the origin of that material, or');
        writeln('    requiring that modified versions of such material be marked in');
        writeln('    reasonable ways as different from the original version; or');
        writeln;
        writeln('    d) Limiting the use for publicity purposes of names of licensors or');
        writeln('    authors of the material; or');
        writeln;
        writeln('    e) Declining to grant rights under trademark law for use of some');
        writeln('    trade names, trademarks, or service marks; or');
        writeln;
        writeln('    f) Requiring indemnification of licensors and authors of that');
        writeln('    material by anyone who conveys the material (or modified versions of');
        writeln('    it) with contractual assumptions of liability to the recipient, for');
        writeln('    any liability that these contractual assumptions directly impose on');
        writeln('    those licensors and authors.');
        writeln;
        writeln('  All other non-permissive additional terms are considered "further');
        writeln('restrictions" within the meaning of section 10.  If the Program as you');
        writeln('received it, or any part of it, contains a notice stating that it is');
        writeln('governed by this License along with a term that is a further');
        writeln('restriction, you may remove that term.  If a license document contains');
        writeln('a further restriction but permits relicensing or conveying under this');
        writeln('License, you may add to a covered work material governed by the terms');
        writeln('of that license document, provided that the further restriction does');
        writeln('not survive such relicensing or conveying.');
        writeln;
        writeln('  If you add terms to a covered work in accord with this section, you');
        writeln('must place, in the relevant source files, a statement of the');
        writeln('additional terms that apply to those files, or a notice indicating');
        writeln('where to find the applicable terms.');
        writeln;
        writeln('  Additional terms, permissive or non-permissive, may be stated in the');
        writeln('form of a separately written license, or stated as exceptions;');
        writeln('the above requirements apply either way.');
        writeln;
        writeln('  8. Termination.');
        writeln;
        writeln('  You may not propagate or modify a covered work except as expressly');
        writeln('provided under this License.  Any attempt otherwise to propagate or');
        writeln('modify it is void, and will automatically terminate your rights under');
        writeln('this License (including any patent licenses granted under the third');
        writeln('paragraph of section 11).');
        writeln;
        writeln('  However, if you cease all violation of this License, then your');
        writeln('license from a particular copyright holder is reinstated (a)');
        writeln('provisionally, unless and until the copyright holder explicitly and');
        writeln('finally terminates your license, and (b) permanently, if the copyright');
        writeln('holder fails to notify you of the violation by some reasonable means');
        writeln('prior to 60 days after the cessation.');
        writeln;
        writeln('  Moreover, your license from a particular copyright holder is');
        writeln('reinstated permanently if the copyright holder notifies you of the');
        writeln('violation by some reasonable means, this is the first time you have');
        writeln('received notice of violation of this License (for any work) from that');
        writeln('copyright holder, and you cure the violation prior to 30 days after');
        writeln('your receipt of the notice.');
        writeln;
        writeln('  Termination of your rights under this section does not terminate the');
        writeln('licenses of parties who have received copies or rights from you under');
        writeln('this License.  If your rights have been terminated and not permanently');
        writeln('reinstated, you do not qualify to receive new licenses for the same');
        writeln('material under section 10.');
        writeln;
        writeln('  9. Acceptance Not Required for Having Copies.');
        writeln;
        writeln('  You are not required to accept this License in order to receive or');
        writeln('run a copy of the Program.  Ancillary propagation of a covered work');
        writeln('occurring solely as a consequence of using peer-to-peer transmission');
        writeln('to receive a copy likewise does not require acceptance.  However,');
        writeln('nothing other than this License grants you permission to propagate or');
        writeln('modify any covered work.  These actions infringe copyright if you do');
        writeln('not accept this License.  Therefore, by modifying or propagating a');
        writeln('covered work, you indicate your acceptance of this License to do so.');
        writeln;
        writeln('  10. Automatic Licensing of Downstream Recipients.');
        writeln;
        writeln('  Each time you convey a covered work, the recipient automatically');
        writeln('receives a license from the original licensors, to run, modify and');
        writeln('propagate that work, subject to this License.  You are not responsible');
        writeln('for enforcing compliance by third parties with this License.');
        writeln;
        writeln('  An "entity transaction" is a transaction transferring control of an');
        writeln('organization, or substantially all assets of one, or subdividing an');
        writeln('organization, or merging organizations.  If propagation of a covered');
        writeln('work results from an entity transaction, each party to that');
        writeln('transaction who receives a copy of the work also receives whatever');
        writeln('licenses to the work the party''s predecessor in interest had or could');
        writeln('give under the previous paragraph, plus a right to possession of the');
        writeln('Corresponding Source of the work from the predecessor in interest, if');
        writeln('the predecessor has it or can get it with reasonable efforts.');
        writeln;
        writeln('  You may not impose any further restrictions on the exercise of the');
        writeln('rights granted or affirmed under this License.  For example, you may');
        writeln('not impose a license fee, royalty, or other charge for exercise of');
        writeln('rights granted under this License, and you may not initiate litigation');
        writeln('(including a cross-claim or counterclaim in a lawsuit) alleging that');
        writeln('any patent claim is infringed by making, using, selling, offering for');
        writeln('sale, or importing the Program or any portion of it.');
        writeln;
        writeln('  11. Patents.');
        writeln;
        writeln('  A "contributor" is a copyright holder who authorizes use under this');
        writeln('License of the Program or a work on which the Program is based.  The');
        writeln('work thus licensed is called the contributor''s "contributor version".');
        writeln;
        writeln('  A contributor''s "essential patent claims" are all patent claims');
        writeln('owned or controlled by the contributor, whether already acquired or');
        writeln('hereafter acquired, that would be infringed by some manner, permitted');
        writeln('by this License, of making, using, or selling its contributor version,');
        writeln('but do not include claims that would be infringed only as a');
        writeln('consequence of further modification of the contributor version.  For');
        writeln('purposes of this definition, "control" includes the right to grant');
        writeln('patent sublicenses in a manner consistent with the requirements of');
        writeln('this License.');
        writeln;
        writeln('  Each contributor grants you a non-exclusive, worldwide, royalty-free');
        writeln('patent license under the contributor''s essential patent claims, to');
        writeln('make, use, sell, offer for sale, import and otherwise run, modify and');
        writeln('propagate the contents of its contributor version.');
        writeln;
        writeln('  In the following three paragraphs, a "patent license" is any express');
        writeln('agreement or commitment, however denominated, not to enforce a patent');
        writeln('(such as an express permission to practice a patent or covenant not to');
        writeln('sue for patent infringement).  To "grant" such a patent license to a');
        writeln('party means to make such an agreement or commitment not to enforce a');
        writeln('patent against the party.');
        writeln;
        writeln('  If you convey a covered work, knowingly relying on a patent license,');
        writeln('and the Corresponding Source of the work is not available for anyone');
        writeln('to copy, free of charge and under the terms of this License, through a');
        writeln('publicly available network server or other readily accessible means,');
        writeln('then you must either (1) cause the Corresponding Source to be so');
        writeln('available, or (2) arrange to deprive yourself of the benefit of the');
        writeln('patent license for this particular work, or (3) arrange, in a manner');
        writeln('consistent with the requirements of this License, to extend the patent');
        writeln('license to downstream recipients.  "Knowingly relying" means you have');
        writeln('actual knowledge that, but for the patent license, your conveying the');
        writeln('covered work in a country, or your recipient''s use of the covered work');
        writeln('in a country, would infringe one or more identifiable patents in that');
        writeln('country that you have reason to believe are valid.');
        writeln;
        writeln('  If, pursuant to or in connection with a single transaction or');
        writeln('arrangement, you convey, or propagate by procuring conveyance of, a');
        writeln('covered work, and grant a patent license to some of the parties');
        writeln('receiving the covered work authorizing them to use, propagate, modify');
        writeln('or convey a specific copy of the covered work, then the patent license');
        writeln('you grant is automatically extended to all recipients of the covered');
        writeln('work and works based on it.');
        writeln;
        writeln('  A patent license is "discriminatory" if it does not include within');
        writeln('the scope of its coverage, prohibits the exercise of, or is');
        writeln('conditioned on the non-exercise of one or more of the rights that are');
        writeln('specifically granted under this License.  You may not convey a covered');
        writeln('work if you are a party to an arrangement with a third party that is');
        writeln('in the business of distributing software, under which you make payment');
        writeln('to the third party based on the extent of your activity of conveying');
        writeln('the work, and under which the third party grants, to any of the');
        writeln('parties who would receive the covered work from you, a discriminatory');
        writeln('patent license (a) in connection with copies of the covered work');
        writeln('conveyed by you (or copies made from those copies), or (b) primarily');
        writeln('for and in connection with specific products or compilations that');
        writeln('contain the covered work, unless you entered into that arrangement,');
        writeln('or that patent license was granted, prior to 28 March 2007.');
        writeln;
        writeln('  Nothing in this License shall be construed as excluding or limiting');
        writeln('any implied license or other defenses to infringement that may');
        writeln('otherwise be available to you under applicable patent law.');
        writeln;
        writeln('  12. No Surrender of Others'' Freedom.');
        writeln;
        writeln('  If conditions are imposed on you (whether by court order, agreement or');
        writeln('otherwise) that contradict the conditions of this License, they do not');
        writeln('excuse you from the conditions of this License.  If you cannot convey a');
        writeln('covered work so as to satisfy simultaneously your obligations under this');
        writeln('License and any other pertinent obligations, then as a consequence you may');
        writeln('not convey it at all.  For example, if you agree to terms that obligate you');
        writeln('to collect a royalty for further conveying from those to whom you convey');
        writeln('the Program, the only way you could satisfy both those terms and this');
        writeln('License would be to refrain entirely from conveying the Program.');
        writeln;
        writeln('  13. Use with the GNU Affero General Public License.');
        writeln;
        writeln('  Notwithstanding any other provision of this License, you have');
        writeln('permission to link or combine any covered work with a work licensed');
        writeln('under version 3 of the GNU Affero General Public License into a single');
        writeln('combined work, and to convey the resulting work.  The terms of this');
        writeln('License will continue to apply to the part which is the covered work,');
        writeln('but the special requirements of the GNU Affero General Public License,');
        writeln('section 13, concerning interaction through a network will apply to the');
        writeln('combination as such.');
        writeln;
        writeln('  14. Revised Versions of this License.');
        writeln;
        writeln('  The Free Software Foundation may publish revised and/or new versions of');
        writeln('the GNU General Public License from time to time.  Such new versions will');
        writeln('be similar in spirit to the present version, but may differ in detail to');
        writeln('address new problems or concerns.');
        writeln;
        writeln('  Each version is given a distinguishing version number.  If the');
        writeln('Program specifies that a certain numbered version of the GNU General');
        writeln('Public License "or any later version" applies to it, you have the');
        writeln('option of following the terms and conditions either of that numbered');
        writeln('version or of any later version published by the Free Software');
        writeln('Foundation.  If the Program does not specify a version number of the');
        writeln('GNU General Public License, you may choose any version ever published');
        writeln('by the Free Software Foundation.');
        writeln;
        writeln('  If the Program specifies that a proxy can decide which future');
        writeln('versions of the GNU General Public License can be used, that proxy''s');
        writeln('public statement of acceptance of a version permanently authorizes you');
        writeln('to choose that version for the Program.');
        writeln;
        writeln('  Later license versions may give you additional or different');
        writeln('permissions.  However, no additional obligations are imposed on any');
        writeln('author or copyright holder as a result of your choosing to follow a');
        writeln('later version.');
        writeln;
        writeln('  15. Disclaimer of Warranty.');
        writeln;
        writeln('  THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY');
        writeln('APPLICABLE LAW.  EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT');
        writeln('HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM "AS IS" WITHOUT WARRANTY');
        writeln('OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO,');
        writeln('THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR');
        writeln('PURPOSE.  THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM');
        writeln('IS WITH YOU.  SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF');
        writeln('ALL NECESSARY SERVICING, REPAIR OR CORRECTION.');
        writeln;
        writeln('  16. Limitation of Liability.');
        writeln;
        writeln('  IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING');
        writeln('WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MODIFIES AND/OR CONVEYS');
        writeln('THE PROGRAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY');
        writeln('GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE');
        writeln('USE OR INABILITY TO USE THE PROGRAM (INCLUDING BUT NOT LIMITED TO LOSS OF');
        writeln('DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD');
        writeln('PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE WITH ANY OTHER PROGRAMS),');
        writeln('EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF');
        writeln('SUCH DAMAGES.');
        writeln;
        writeln('  17. Interpretation of Sections 15 and 16.');
        writeln;
        writeln('  If the disclaimer of warranty and limitation of liability provided');
        writeln('above cannot be given local legal effect according to their terms,');
        writeln('reviewing courts shall apply local law that most closely approximates');
        writeln('an absolute waiver of all civil liability in connection with the');
        writeln('Program, unless a warranty or assumption of liability accompanies a');
        writeln('copy of the Program in return for a fee.');
        writeln;
        writeln('                     END OF TERMS AND CONDITIONS');
        writeln;
        writeln('            How to Apply These Terms to Your New Programs');
        writeln;
        writeln('  If you develop a new program, and you want it to be of the greatest');
        writeln('possible use to the public, the best way to achieve this is to make it');
        writeln('free software which everyone can redistribute and change under these terms.');
        writeln;
        writeln('  To do so, attach the following notices to the program.  It is safest');
        writeln('to attach them to the start of each source file to most effectively');
        writeln('state the exclusion of warranty; and each file should have at least');
        writeln('the "copyright" line and a pointer to where the full notice is found.');
        writeln;
        writeln('    {one line to give the program''s name and a brief idea of what it does.}');
        writeln('    Copyright (C) {year}  {name of author}');
        writeln;
        writeln('    This program is free software: you can redistribute it and/or modify');
        writeln('    it under the terms of the GNU General Public License as published by');
        writeln('    the Free Software Foundation, either version 3 of the License, or');
        writeln('    (at your option) any later version.');
        writeln;
        writeln('    This program is distributed in the hope that it will be useful,');
        writeln('    but WITHOUT ANY WARRANTY; without even the implied warranty of');
        writeln('    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the');
        writeln('    GNU General Public License for more details.');
        writeln;
        writeln('    You should have received a copy of the GNU General Public License');
        writeln('    along with this program.  If not, see <http://www.gnu.org/licenses/>.');
        writeln;
        writeln('Also add information on how to contact you by electronic and paper mail.');
        writeln;
        writeln('  If the program does terminal interaction, make it output a short');
        writeln('notice like this when it starts in an interactive mode:');
        writeln;
        writeln('    {project}  Copyright (C) {year}  {fullname}');
        writeln('    This program comes with ABSOLUTELY NO WARRANTY; for details type `show w''.');
        writeln('    This is free software, and you are welcome to redistribute it');
        writeln('    under certain conditions; type `show c'' for details.');
        writeln;
        writeln('The hypothetical commands `show w'' and `show c'' should show the appropriate');
        writeln('parts of the General Public License.  Of course, your program''s commands');
        writeln('might be different; for a GUI interface, you would use an "about box".');
        writeln;
        writeln('  You should also get your employer (if you work as a programmer) or school,');
        writeln('if any, to sign a "copyright disclaimer" for the program, if necessary.');
        writeln('For more information on this, and how to apply and follow the GNU GPL, see');
        writeln('<http://www.gnu.org/licenses/>.');
        writeln;
        writeln('  The GNU General Public License does not permit incorporating your program');
        writeln('into proprietary programs.  If your program is a subroutine library, you');
        writeln('may consider it more useful to permit linking proprietary applications with');
        writeln('the library.  If this is what you want to do, use the GNU Lesser General');
        writeln('Public License instead of this License.  But first, please read');
        writeln('<http://www.gnu.org/philosophy/why-not-lgpl.html>.');
        exit;
      end else begin
        _settings.configfile := paramstr(1);
      end;
    end;
    if not ReadSettings then begin
      writeln('Failed to load settings.');
      exit;
    end;

    // Fixup controller configurations at boot if requested
    if _settings.controller_disablehotkeys and _settings.controller_fix_at_boot then begin
      FixControllerConfigurations;
    end;

    // Initialise GPIO driver
    gpiodriver := trpiGPIO.Create;
    if not gpiodriver.initialise(_settings.system_newpi) then begin
      freeandnil(gpiodriver);
      writeln('Failed to initialise GPIO driver.');
      exit;
    end;

    write('Waiting (ondelay): ');
    sleep(_settings.system_ondelay * 1000);
    writeln('Done');

    writeln('Setting up GPIO pins...');

    write('Power-up pin: ');
    gpiodriver.setPinMode(_settings.gpio_powerup, RPIGPIO_OUTPUT);
    writeln('Done');

    write('Power-down pin: ');
    gpiodriver.setPinMode(_settings.gpio_powerdown, RPIGPIO_INPUT);
    gpiodriver.setPullupMode(_settings.gpio_powerdown, RPIGPIO_PUD_OFF);
    writeln('Done');

    write('Reset pin: ');
    if _settings.gpio_useresetbutton then begin
      gpiodriver.setPinMode(_settings.gpio_resetbutton, RPIGPIO_INPUT);
      gpiodriver.setPullupMode(_settings.gpio_resetbutton, RPIGPIO_PUD_UP);
      writeln('Done');
    end else begin
      writeln('Not in use');
    end;

    write('Notifying the microcontroller that we have booted: ');
    gpiodriver.setPin(_settings.gpio_powerup);
    writeln('Done');

    writeln('Monitoring for shutdown request.');
    if _settings.gpio_useresetbutton then begin
      writeln('Monitoring the reset button.');
    end;

    lasttime := unixtimeint;

    repeat
      sleep(50);
      // Are we regularly checking for configuration changes?
      if _settings.controller_disablehotkeys then begin
        if _settings.controller_fix_regularly then begin
          if (unixtimeint - lasttime) >= _settings.controller_check_interval then begin
            // A check is due
            CheckConfigurationChangesSince(lasttime);
            lasttime := unixtimeint;
          end;
        end;
      end;
      // Shutdown request?
      if gpiodriver.readPin(_settings.gpio_powerdown) then begin
        // Wait for another 10ms and read again to be certain
        sleep(10);
        if gpiodriver.readPin(_settings.gpio_powerdown) then begin
          // Yep, shutdown request.
          writeln('*** Shutdown request received ***');
          write('Shutting down GPIO driver: ');
          gpiodriver.shutdown;
          freeandnil(gpiodriver);
          writeln('Done');
          CloseRetroarch;
          writeln('Waiting...');
          sleep(5000);
          // Fixup controller configurations at shutdown if requested
          if _settings.controller_disablehotkeys and _settings.controller_fix_at_shutdown then begin
            FixControllerConfigurations;
          end;
          write('Starting shutdown process: ');
          StartShutdown;
          writeln('Done');
          exit;
        end;
      end;
      // Reset button request?
      if _settings.gpio_useresetbutton then begin
        if not gpiodriver.readPin(_settings.gpio_resetbutton) then begin
          // Wait for 10ms and read again to debounce
          sleep(10);
          if not gpiodriver.readPin(_settings.gpio_resetbutton) then begin
            // Reset button - try to kill retroarch nicely so it saves SRAM/etc
            CloseRetroarch;
            // Now wait for it to be released
            i := 10;
            while (i > 0) do begin
              sleep(10);
              dec(i);
              if not gpiodriver.readPin(_settings.gpio_resetbutton) then begin
                i := 10;
              end;
            end;
          end;
        end;
      end;
    until false;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
