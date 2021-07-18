unit dataWorkUnit;

interface

uses Classes, ZConnection, mainUnit, ZDataset, Windows;

type
  TTempColumnData=record
    field:string;
    FieldData:array of string;
  end;
  TTempColumnDataArr=array of TTempColumnData;

  TSectionTemp=record
    ZQ:TZQuery;
    Columns:TTempColumnDataArr;
  end;

  TDataThread=class(TThread)
  private
    FZC:TZConnection;
    FSecPointer:PTSectionArr;
    FLogEnabled:boolean;
    FLogFileName:string;
    FZQ_timesync:TZQuery;
    FSQLUpdateInterval:integer;

    procedure SQLTimeSync;
    procedure SQLUpdateData;
    procedure SQLClearData;

    procedure Log(mess:string; time:boolean=true);
  public
    DataAccessCritSection:TRTLCriticalSection;
    NewDataReadyEvent:THandle;
    FSectionsTempData:array of TSectionTemp;

    constructor Create(SecPointer:PTSectionArr; SQLHost,SQLDatabase,SQLLogin,SQLPass,LogFileName:string; LogEnabled:boolean; UpdateInterval:integer);
    destructor Destroy; override;

    procedure Execute; override;
  end;

implementation

uses ZCompatibility, SysUtils, DateUtils;

constructor TDataThread.Create(SecPointer:PTSectionArr; SQLHost,SQLDatabase,SQLLogin,SQLPass,LogFileName:string; LogEnabled:boolean; UpdateInterval:integer);
var i,j:integer;
begin
  inherited Create(true);
  //initialization
  setlength(FSectionsTempData,0);
  FSecPointer:=SecPointer;
  FZC:=TZConnection.Create(nil);
  FZC.HostName:=SQLHost;
  FZC.Port:=0;
  FZC.Database:=SQLDatabase;
  FZC.User:=SQLLogin;
  FZC.Password:=SQLPass;
  FZC.Protocol:='mysql-5';
  FZC.ClientCodepage:='cp1251';
  FZC.ControlsCodePage:=cGET_ACP;
  FLogEnabled:=LogEnabled;
  FLogFileName:=LogFileName;
  FSQLUpdateInterval:=UpdateInterval;

  //удаляем старый файл логов
  if FileExists(FLogFileName) then SysUtils.DeleteFile(FLogFileName);

  Log('DataThread object OnCreate after initialize, creating Queryes');
  //загружаем данные из массива секций
  setlength(FSectionsTempData,length(FSecPointer^));
  for i:=0 to length(FSecPointer^)-1 do
  begin
    FSectionsTempData[i].ZQ:=TZQuery.Create(nil);
    FSectionsTempData[i].ZQ.Connection:=FZC;
    FSectionsTempData[i].ZQ.SQL.Clear;
    FSectionsTempData[i].ZQ.SQL.LoadFromFile(FSecPointer^[i].SQLFilePath);
    //заполняем колонки      
    setlength(FSectionsTempData[i].Columns,length(FSecPointer^[i].Columns));
    for j:=0 to length(FSectionsTempData[i].Columns)-1 do
    begin
      setlength(FSectionsTempData[i].Columns[j].FieldData,0);
      FSectionsTempData[i].Columns[j].field:=FSecPointer^[i].Columns[j].Field;
    end;
    //добавляем ещё одну общую колонку
    j:=length(FSectionsTempData[i].Columns);
    setlength(FSectionsTempData[i].Columns,j+1);
    FSectionsTempData[i].Columns[j].field:=FSecPointer^[i].AllRowsField;
    setlength(FSectionsTempData[i].Columns[j].FieldData,0);
  end;

  //создаём скрипт для синхронизации времени
  FZQ_timesync:=TZQuery.Create(nil);
  FZQ_timesync.Connection:=FZC;
  FZQ_timesync.SQL.Clear;
  FZQ_timesync.SQL.Add('select DATE_FORMAT(now(),''%d.%m.%Y %H:%i:%s'') as time_cur;');

  //создаём критическую секцию
  InitializeCriticalSectionAndSpinCount(DataAccessCritSection,$1000);

  //создаём эвент
  NewDataReadyEvent:=CreateEvent(nil,true,false,nil);

  Log('DataThread object create complete');
end;

destructor TDataThread.Destroy;
var i,j:integer;
begin
  Log('DataThread OnDestroy');

  FZQ_timesync.Close;
  FZQ_timesync.Free;
  for i:=0 to length(FSectionsTempData)-1 do
  begin
    FSectionsTempData[i].ZQ.Close;
    FSectionsTempData[i].ZQ.Free;
  end;
  setlength(FSectionsTempData,0);
  FZC.Disconnect;
  FZC.Free;

  //удаляем критическую секцию
  DeleteCriticalSection(DataAccessCritSection);

  //удаляем эвент
  CloseHandle(NewDataReadyEvent);

  Log('DataThread OnDestroy complete');
end;

procedure TDataThread.Log(mess:string; time:boolean=true);
var handl:integer;
temp_mess:string;
begin
  if not(FLogEnabled) then exit;
  temp_mess:=Mess+#13+#10;
  if time=true then temp_mess:=FormatDateTime('dd.mm.yyyy hh:nn:ss.zzz',now)+'  '+temp_mess;

  if FLogFileName<>'' then
  begin
    if FileExists(FLogFileName) then
      handl:=FileOpen(FLogFileName,fmOpenReadWrite or fmShareDenyNone)
    else
      handl:=FileCreate(FLogFileName);

    if handl<0 then exit;
    if FileSeek(handl,0,2)=-1 then exit;
    if FileWrite(handl,temp_mess[1],length(temp_mess))=-1 then exit;
    FileClose(handl);
  end
  else
  begin
    temp_mess:='';
    exit;
  end;

  temp_mess:='';
end;

procedure TDataThread.SQLTimeSync;
var str:string;
dt:TDateTime;
sys_time:TSYSTEMTIME;
b:boolean;
err_code:cardinal;
//hToken:THandle;
//TokenPrivileges:TTokenPrivileges;
//ReturnLength:cardinal;
begin
  Log('TimeSync procedure enter');
  try
    FZQ_timesync.Close;
    FZQ_timesync.Open;

    str:=FZQ_timesync.FieldByName('time_cur').asString;
    dt:=StrToDateTimeDef(str,0);

    if dt<>0 then
    begin
      sys_time.wYear:=YearOf(dt);
      sys_time.wMonth:=MonthOf(dt);
      sys_time.wDay:=DayOf(dt);
      sys_time.wHour:=HourOf(dt);
      sys_time.wMinute:=MinuteOf(dt);
      sys_time.wSecond:=SecondOf(dt);
      sys_time.wMilliseconds:=MillisecondOf(dt);

      str:=inttostr(sys_time.wDay)+'.'+inttostr(sys_time.wMonth)+'.'+inttostr(sys_time.wYear)+' '+inttostr(sys_time.wHour)+':'+inttostr(sys_time.wMinute)+':'+inttostr(sys_time.wSecond)+'.'+inttostr(sys_time.wMilliseconds);
      Log('About to sync time to '+str);
      b:=SetLocalTime(sys_time);
      if b=false then
      begin
        err_code:=GetLastError;
        Log('Last error='+inttostr(err_code));

        {if OpenProcessToken(GetCurrentProcess, TOKEN_ADJUST_PRIVILEGES or TOKEN_QUERY, hToken) then
        begin
          if LookupPrivilegeValue(nil, PChar('SeSystemtimePrivilege'), TokenPrivileges.Privileges[0].Luid) then
          begin
            TokenPrivileges.PrivilegeCount:=1;
            TokenPrivileges.Privileges[0].Attributes:=SE_PRIVILEGE_ENABLED;
            if AdjustTokenPrivileges(hToken,false,TokenPrivileges,0,nil,ReturnLength) then
            begin
              b:=SetLocalTime(sys_time);
              Log('Return of SetLocalTime='+booltostr(b,true));
            end else Log('AdjustTokenPrivileges failed');
          end else Log('LookupPrivilegeValue failed');
        end else Log('OpenProcessToken failed');   }
      end;
      Log('Sync complete, SetLocalTime return='+booltostr(b,true));
    end;

    FZQ_timesync.Close;
  except
    on e:exception do
    begin
      FZQ_timesync.Close;
      exit;
    end;
  end;
end;

procedure TDataThread.SQLUpdateData;
var b:boolean;
i,j,k,z:integer;
data_arr:array of TSectionTemp;
wait_return:cardinal;
str:string;
begin
  Log('SQLUpdateData enter');

  //проверяем, выставлен ли эвент
  wait_return:=WaitForSingleObject(NewDataReadyEvent,0);
  case wait_return of
    WAIT_OBJECT_0:
    begin  //эвент выставлен - ничего не делаем и ждём, пока данные не заберут
      Log('Event is still signaled, exiting');
      exit;
    end;
    WAIT_TIMEOUT:Log('Event is not signaled, working');  //эвент не выставлен, можно действовать
    else
    begin  //тут что-то ещё, значит ошибка
      Log('ERROR! WaitForSingleObject returned unknown result='+inttostr(wait_return));
      exit;
    end;
  end;

  b:=false;  //признак обновления данных

  //приводим временный массив к той же структуре, что и реальный
  setlength(data_arr,length(FSectionsTempData));
  for i:=0 to length(data_arr)-1 do
  begin
    setlength(data_arr[i].Columns,length(FSectionsTempData[i].Columns));
    for j:=0 to length(data_arr[i].Columns)-1 do
    begin
      setlength(data_arr[i].Columns[j].FieldData,0);
      data_arr[i].Columns[j].field:=FSectionsTempData[i].Columns[j].field;
    end;
  end;

  //заполняем временный массив данными
  for i:=0 to length(data_arr)-1 do
  begin
    //выполняем SQL
    if FSectionsTempData[i].ZQ.Active then FSectionsTempData[i].ZQ.Close;
    FSectionsTempData[i].ZQ.Open;

    //если запрос пустой, то очищаем данную секцию
    if FSectionsTempData[i].ZQ.RecordCount=0 then
    begin
      for j:=0 to length(data_arr[i].Columns)-1 do
        setlength(data_arr[i].Columns[j].FieldData,0);
    end;

    //идём по всем записям и добавляем информацию в колонки
    FSectionsTempData[i].ZQ.First;
    while not(FSectionsTempData[i].ZQ.Eof) do
    begin
      for j:=0 to length(data_arr[i].Columns)-1 do
      begin
        k:=length(data_arr[i].Columns[j].FieldData);
        setlength(data_arr[i].Columns[j].FieldData,k+1);
        if FSectionsTempData[i].ZQ.FindField(data_arr[i].Columns[j].field)<>nil then
          data_arr[i].Columns[j].FieldData[k]:=FSectionsTempData[i].ZQ.FieldByName(data_arr[i].Columns[j].field).AsString
        else
          data_arr[i].Columns[j].FieldData[k]:=' ';
      end;

      FSectionsTempData[i].ZQ.Next;
    end;

    //сравниваем записи в массиве класса с тем, что получили сейчас от SQL
    //сравниваем записи, которые мы получили от SQL, с записями в массиве
    for j:=0 to length(FSectionsTempData[i].Columns)-1 do
    begin
      k:=-1;
      //находим поле в SQL массиве
      for z:=0 to length(data_arr[i].Columns)-1 do
        if data_arr[i].Columns[z].field=FSectionsTempData[i].Columns[j].Field then
        begin
          k:=z;
          break;
        end;
      //если не нашли, пропускаем
      if k=-1 then continue;
      //если нашли, то сравниваем длины масивов
      if length(FSectionsTempData[i].Columns[j].FieldData)<>length(data_arr[i].Columns[k].FieldData) then
      begin  //если длины не совпадают
        b:=true;  //выставляем признак
      end
      else
      begin  //если длины совпадают, то ищем несовпадение в данных
        for z:=0 to length(data_arr[i].Columns[k].FieldData)-1 do
          if FSectionsTempData[i].Columns[j].FieldData[z]<>data_arr[i].Columns[k].FieldData[z] then
          begin  //если какое то значение не совпадает, то
            b:=true;  //выставляем признак
          end;
      end;
    end;
  end;

  Log('SQL needs update='+booltostr(b,true));

  if b then
  begin
    EnterCriticalSection(DataAccessCritSection);
    Log('Entered critical section');

    //обновляем все данные в массиве объекта
    for i:=0 to length(FSectionsTempData)-1 do
      for j:=0 to length(FSectionsTempData[i].Columns)-1 do
      begin
        k:=-1;
        //находим поле во временных данных
        for z:=0 to length(data_arr[i].Columns)-1 do
          if FSectionsTempData[i].Columns[j].field=data_arr[i].Columns[z].field then
          begin
            k:=z;
            break;
          end;
        //если не нашли, пропускаем
        if k=-1 then continue;
        //переносим данные
        setlength(FSectionsTempData[i].Columns[j].FieldData,length(data_arr[i].Columns[k].FieldData));
        for z:=0 to length(FSectionsTempData[i].Columns[j].FieldData)-1 do
          FSectionsTempData[i].Columns[j].FieldData[z]:=data_arr[i].Columns[k].FieldData[z];
      end;
    Log('Data transfered');

    //выставляем эвент, чтобы было видно что есть новые данные
    SetEvent(NewDataReadyEvent);
    Log('Event set');

    //выводим всю информацию для отладки
    Log('Data:',false);
    for i:=0 to length(FSectionsTempData)-1 do
    begin
      Log('Section#'+inttostr(i),false);
      str:='';
      for j:=0 to length(FSectionsTempData[i].Columns)-1 do
        str:=str+'    '+FSectionsTempData[i].Columns[j].field;
      Log(str,false);

      for k:=0 to length(FSectionsTempData[i].Columns[0].FieldData)-1 do
      begin
        str:='';
        for j:=0 to length(FSectionsTempData[i].Columns)-1 do
          str:=str+'    '+FSectionsTempData[i].Columns[j].FieldData[k];
        Log(str,false);
      end;
    end;

    LeaveCriticalSection(DataAccessCritSection);
    Log('Left critical section');
  end;

  for i:=0 to length(data_arr)-1 do
  begin
    for j:=0 to length(data_arr[i].Columns)-1 do
      setlength(data_arr[i].Columns[j].FieldData,0);
    setlength(data_arr[i].Columns,0);
  end;
  setlength(data_arr,0);
end;

procedure TDataThread.SQLClearData;
var wait_return:cardinal;
i,j:integer;
b:boolean;
begin
  Log('SQLClearData enter');

  //проверяем, выставлен ли эвент
  wait_return:=WaitForSingleObject(NewDataReadyEvent,0);
  case wait_return of
    WAIT_OBJECT_0:
    begin  //эвент выставлен - ничего не делаем и ждём, пока данные не заберут
      Log('Event is still signaled, exiting');
      exit;
    end;
    WAIT_TIMEOUT:Log('Event is not signaled, working');  //эвент не выставлен, можно действовать
    else
    begin  //тут что-то ещё, значит ошибка
      Log('ERROR! WaitForSingleObject returned unknown result='+inttostr(wait_return));
      exit;
    end;
  end;

  Log('Checking if data already empty');
  b:=false;
  for i:=0 to length(FSectionsTempData)-1 do
    for j:=0 to length(FSectionsTempData[i].Columns)-1 do
      if length(FSectionsTempData[i].Columns[j].FieldData)<>0 then
      begin
        b:=true;
        break;
      end;

  if b then
  begin
    EnterCriticalSection(DataAccessCritSection);
    Log('Entered critical section');

    //очищаем все данные в массиве объекта
    for i:=0 to length(FSectionsTempData)-1 do
      for j:=0 to length(FSectionsTempData[i].Columns)-1 do
        setlength(FSectionsTempData[i].Columns[j].FieldData,0);

    //выставляем эвент, чтобы было видно что есть новые данные
    SetEvent(NewDataReadyEvent);
    Log('Event set');

    LeaveCriticalSection(DataAccessCritSection);
    Log('Left critical section');
  end
  else Log('Don''t need to clear, data already empty');
end;

procedure TDataThread.Execute;
var SQLDataUpdate_time,SQLTimeSync_time:int64;
curtime,TimeFreq:int64;
SQLDataUpdate_time_interval,SQLTimeSync_time_interval:int64;
wait_result:cardinal;
begin
  Log('DataThread execute enter');

  //как можно скорее делаем обновление данных и синхронизацию времени
  SQLDataUpdate_time:=0;
  SQLTimeSync_time:=0;
  //вычисляем интервалы
  QueryPerformanceFrequency(TimeFreq);
  SQLDataUpdate_time_interval:=(FSQLUpdateInterval*TimeFreq) div 1000;  //интервал в милисекундах, умножаем сначала на частоту чтобы не потерять точность
  SQLTimeSync_time_interval:=300*TimeFreq;  //обновляем раз в 300 секунд (раз в 5 минут)

  while not(Terminated) do
  begin
    Log('---------Cycle start----------');
    QueryPerformanceCounter(curtime);
    wait_result:=WaitForSingleObject(NewDataReadyEvent,0);
    case wait_result of
      WAIT_OBJECT_0:Log('Event object is signaled on start of the cycle');
      WAIT_TIMEOUT:Log('Event object is not signaled on start of the cycle');
      else Log('Unknown state of the object on start of the cycle, wait result='+inttostr(wait_result));
    end;

    try
      if FZC.Connected=false then
      begin  //если мы отсоеденены, то пытаемся подсоединится
        Log('DataThread work when disconnected');
        SQLClearData;
        SQLDataUpdate_time:=0;  //чтобы данные обновились сразу после восстановления соединения
        FZC.Connect;
        sleep(2000);
      end
      else
      begin  //если мы уже подсоеденены, то смотрим на таймеры
        Log('DataThread work when connected');

        if (SQLDataUpdate_time+SQLDataUpdate_time_interval)<curtime then
        begin
          SQLUpdateData;
          SQLDataUpdate_time:=curtime;
        end;

        if (SQLTimeSync_time+SQLTimeSync_time_interval)<curtime then
        begin
          Log('Timesync time enter');
          SQLTimeSync;
          SQLTimeSync_time:=curtime;
        end;

        sleep(1000);
      end;
    except
      on e:exception do
      begin
        Log('Exception in DataThread main cycle with message:'+e.Message);
        FZC.Disconnect;
        sleep(1000);
      end;
    end;

    sleep(100);
  end;
end;

end.
