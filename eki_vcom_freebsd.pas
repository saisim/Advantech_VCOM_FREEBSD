program eki_vcom_freebsd;

{$mode objfpc}{$H+}

uses
  EventLog, BaseUnix, Unix, Sockets, SysUtils, Classes, systemlog, CTypes;

const
  CONF_FILE = '/etc/advttyd.conf';
  BUF_SIZE  = 2048;
  RECONNECT_DELAY = 5; // Seconds between reconnection attempts

var
  DrvExeName : string;
  {$IFDEF EventLog}EvtLog: TEventLog;{$ENDIF}
  //KeepRunning: Boolean = True;

//// --- Signal Handler ---
//procedure SignalHandler(Sig: Integer); cdecl;
//begin
//  case Sig of
//    SIGINT, SIGTERM:
//    begin
//      WriteLn(#10'Termination signal received. Shutting down all instances...');
//      KeepRunning := False;
//    end;
//  end;
//end;

// --- C Library Imports ---
function openpty(var amaster: Integer; var aslave: Integer; name: PChar; 
                 termp: Pointer; winp: Pointer): Integer; cdecl; external 'util';
function ttyname(fd: Integer): PChar; cdecl; external 'c';

procedure RunVCOM(TTYIndex: Integer; IP: string; Port: Integer);
var
  master_fd, slave_fd, sock_fd: Integer;
  server_addr: TInetSockAddr;
  buffer: array[0..BUF_SIZE-1] of Byte;
  read_fds: TFDSet;
  n_bytes, max_fd: Integer;
  DevLinkName: string;
  ActualPtyName: PChar;

  sInfo : string;
begin
  // 1. Setup Virtual TTY (Persistent)
  if openpty(master_fd, slave_fd, nil, nil, nil) = -1 then 
  begin
    //sInfo := Format('[Advantech VCOM (%s): %s. ttyADV%d] Error: openpty failed', [DrvExeName, FormatDateTime('DD.MM.YYYY hh:nn:ss', Now), TTYIndex]);
    sInfo := Format('[ttyADV%d] Error: openpty failed', [TTYIndex]);
    //WriteLn(Format('[ttyADV%d] Error: openpty failed', [TTYIndex]));
    WriteLn(sInfo);
    {$IFDEF EventLog}EvtLog.Error(sInfo);{$ENDIF}
    {$IFDEF Syslog}syslog(LOG_ERR, PChar(sInfo), []);{$ENDIF}
    Halt(1);
  end;
  
  ActualPtyName := ttyname(slave_fd);
  DevLinkName := '/dev/ttyADV' + IntToStr(TTYIndex);
  
  // Create symbolic link from /dev/ttyADVX to the actual PTY
  Fpunlink(PChar(DevLinkName));
  if fpsymlink(ActualPtyName, PChar(DevLinkName)) <> 0 then
    //WriteLn(Format('[ttyADV%d] Warning: Could not create symlink %s', [TTYIndex, DevLinkName]));
    //sInfo := Format('[Advantech VCOM (%s): %s. ttyADV%d] Warning: Could not create symlink %s', [DrvExeName, FormatDateTime('DD.MM.YYYY hh:nn:ss', Now), TTYIndex, DevLinkName]);
    sInfo := Format('[ttyADV%d] Warning: Could not create symlink %s', [TTYIndex, DevLinkName]);
    WriteLn(sInfo);
    {$IFDEF EventLog}EvtLog.Warning(sInfo);{$ENDIF}
    {$IFDEF Syslog}syslog(LOG_WARNING, PChar(sInfo), []);{$ENDIF}

  //WriteLn(Format('[ttyADV%d] Virtual device %s -> %s ready.', [TTYIndex, DevLinkName, ActualPtyName]));
  //sInfo := Format('[Advantech VCOM (%s): %s. ttyADV%d] Virtual device %s -> %s ready.', [DrvExeName, FormatDateTime('DD.MM.YYYY hh:nn:ss', Now), TTYIndex, DevLinkName, ActualPtyName]);
  sInfo := Format('[ttyADV%d] Virtual device %s -> %s ready.', [TTYIndex, DevLinkName, ActualPtyName]);
  WriteLn(sInfo);
  {$IFDEF EventLog}EvtLog.Info(sInfo);{$ENDIF}
  {$IFDEF Syslog}syslog(LOG_NOTICE, PChar(sInfo), []);{$ENDIF}

  // 2. Main Persistence Loop
  while True do
  begin
    sock_fd := fpsocket(AF_INET, SOCK_STREAM, 0);
    if sock_fd < 0 then 
    begin
      Sleep(RECONNECT_DELAY * 1000);
      Continue;
    end;

    server_addr.sin_family := AF_INET;
    server_addr.sin_port := htons(Port);
    server_addr.sin_addr.s_addr := LongWord(StrToNetAddr(IP));

    //WriteLn(Format('[ttyADV%d] Connecting to %s:%d...', [TTYIndex, IP, Port]));
    //sInfo := Format('[Advantech VCOM (%s): %s. ttyADV%d] Connecting to %s:%d...', [DrvExeName, FormatDateTime('DD.MM.YYYY hh:nn:ss', Now), TTYIndex, IP, Port]);
    sInfo := Format('[ttyADV%d] Connecting to %s:%d...', [TTYIndex, IP, Port]);
    WriteLn(sInfo);
    {$IFDEF EventLog}EvtLog.Info(sInfo);{$ENDIF}
    {$IFDEF Syslog}syslog(LOG_NOTICE, PChar(sInfo), []);{$ENDIF}

    if fpconnect(sock_fd, @server_addr, sizeof(server_addr)) = 0 then
    begin
      //WriteLn(Format('[ttyADV%d] Connected successfully.', [TTYIndex]));
      //sInfo := Format('[Advantech VCOM (%s): %s. ttyADV%d] Connected successfully', [DrvExeName, FormatDateTime('DD.MM.YYYY hh:nn:ss', Now), TTYIndex]);
      sInfo := Format('[ttyADV%d] Connected successfully', [TTYIndex]);
      WriteLn(sInfo);
      {$IFDEF EventLog}EvtLog.Info(sInfo);{$ENDIF}
      {$IFDEF Syslog}syslog(LOG_NOTICE, PChar(sInfo), []);{$ENDIF}

      max_fd := master_fd;
      if sock_fd > max_fd then max_fd := sock_fd;

      // 3. Data Bridging Loop
      while True do
      begin
        fpFD_ZERO(read_fds);
        fpFD_SET(master_fd, read_fds);
        fpFD_SET(sock_fd, read_fds);

        if fpSelect(max_fd + 1, @read_fds, nil, nil, nil) > 0 then
        begin
          // Application -> EKI Device
          if fpFD_ISSET(master_fd, read_fds) <> 0 then
          begin
            n_bytes := fpread(master_fd, buffer, BUF_SIZE);
            if (n_bytes > 0) then
            begin
              if fpwrite(sock_fd, buffer, n_bytes) < 0 then break; 
            end;
          end;

          // EKI Device -> Application
          if fpFD_ISSET(sock_fd, read_fds) <> 0 then
          begin
            n_bytes := fpread(sock_fd, buffer, BUF_SIZE);
            if n_bytes > 0 then 
              fpwrite(master_fd, buffer, n_bytes)
            else 
              break; // Socket closed or error
          end;
        end;
      end;
      //WriteLn(Format('[ttyADV%d] Connection lost.', [TTYIndex]));
      //sInfo := Format('[Advantech VCOM (%s): %s. ttyADV%d] Connection lost.', [DrvExeName, FormatDateTime('DD.MM.YYYY hh:nn:ss', Now), TTYIndex]);
      sInfo := Format('[ttyADV%d] Connection lost.', [TTYIndex]);
      WriteLn(sInfo);
      {$IFDEF EventLog}EvtLog.Info(sInfo);{$ENDIF}
      {$IFDEF Syslog}syslog(LOG_NOTICE, PChar(sInfo), []);{$ENDIF}
    end
    else
      //WriteLn(Format('[ttyADV%d] Connection failed. Retrying in %d seconds...', [TTYIndex, RECONNECT_DELAY]));
      //sInfo := Format('[Advantech VCOM (%s): %s. ttyADV%d] Connection failed. Retrying in %d seconds...', [DrvExeName, FormatDateTime('DD.MM.YYYY hh:nn:ss', Now), TTYIndex, RECONNECT_DELAY]);
      sInfo := Format('[ttyADV%d] Connection failed. Retrying in %d seconds...', [TTYIndex, RECONNECT_DELAY]);
      WriteLn(sInfo);
      {$IFDEF EventLog}EvtLog.Info(sInfo);{$ENDIF}
      {$IFDEF Syslog}syslog(LOG_NOTICE, PChar(sInfo), []);{$ENDIF}

    fpshutdown(sock_fd, 2);
    fpclose(sock_fd);
    Sleep(RECONNECT_DELAY * 1000);
  end;
end;

procedure ParseConfigAndStart;
var
  List: TStringList;
  i: Integer;
  Line: string;
  Parts: TStringList;
  PID: TPid;

  sInfo : string;
begin
  {$IFDEF EventLog}
  // Open the syslog connection using TEventLog.
  try
    EvtLog := TEventLog.Create(nil);
    EvtLog.LogType := ltFile;
    EvtLog.FileName := 'adv_eki.log';
    EvtLog.Identification := Format('Advantech VCOM (%s).', [DrvExeName]);
    EvtLog.Active := true;
    EvtLog.Info('Advantech EKI VCOM Daemon for FreeBSD started.');
  finally
  end;
  {$ENDIF}

  {$IFDEF Syslog}
  // Open the syslog connection
  setlogmask(LOG_UPTO(LOG_NOTICE or LOG_ERR));
  openlog('Advantech-VCOM (eki_vcom_freebsd)', LOG_CONS or LOG_PID or LOG_NDELAY, LOG_LOCAL1);
  syslog(LOG_NOTICE, 'Advantech EKI VCOM Daemon for FreeBSD started.', [GetProcessID]);
  {$ENDIF}

  if not FileExists(CONF_FILE) then
  begin
    //WriteLn('Error: Configuration file ', CONF_FILE, ' not found.');
    //sInfo := Format('Advantech VCOM (%s): %s. Error: Configuration file %s not found.', [FormatDateTime('DD.MM.YYYY hh:nn:ss', Now), CONF_FILE]);
    sInfo := Format('Error: Configuration file %s not found.', [CONF_FILE]);
    WriteLn(sInfo);
    {$IFDEF EventLog}EvtLog.Error(sInfo);{$ENDIF}
    {$IFDEF Syslog}syslog(LOG_ERR, PChar(sInfo), []);{$ENDIF}
    Halt(1);
  end;

  List := TStringList.Create;
  Parts := TStringList.Create;
  try
    List.LoadFromFile(CONF_FILE);
    for i := 0 to List.Count - 1 do
    begin
      Line := Trim(List[i]);
      if (Line = '') or (Line[1] = '#') then Continue;

      // Parse line into TTYIndex IP Port
      Parts.Delimiter := ' ';
      Parts.StrictDelimiter := False;
      Parts.DelimitedText := Line;
      
      if Parts.Count >= 3 then
      begin
        PID := fpfork;
        if PID = 0 then // Child worker
        begin
          RunVCOM(StrToInt(Parts[0]), Parts[1], StrToInt(Parts[2]));
          Halt(0);
        end;
      end;
    end;
  finally
    List.Free;
    Parts.Free;

    // Close the EventLog connection
    {$IFDEF EventLog}EvtLog.Free;{$ENDIF}

    // Close the syslog connection
    {$IFDEF Syslog}closelog;{$ENDIF}
  end;
end;

//var
begin
  //Get driver executable name.
  DrvExeName := ExtractFileName(ParamStr(0));

  // Daemonize
  if fpfork <> 0 then Halt(0);
  fpsetsid;
  
  ParseConfigAndStart;

  // Keep manager alive
  while True do fpPause();
end.
