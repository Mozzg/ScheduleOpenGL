unit mainUnit;

interface

uses Windows, Classes, fontsUnit;

type
  TRunningData = record
    TextRunning:boolean;
    TextOffset:double;
    TextPixelWidth:integer;
  end;

  TColumn = record
    Width:integer;
    DataFont:string;
    DataSize:integer;
    DataColor:TColor;
    DataFontObj:TFontObj;
    CaptionText:string;
    CaptionTextFont:string;
    CaptionTextSize:integer;
    CaptionTextColor:TColor;
    CaptionTextFontObj:TFontObj;
    CaptionTextEng:string;
    CaptionTextEngFont:string;
    CaptionTextEngSize:integer;
    CaptionTextEngColor:TColor;
    CaptionTextEngFontObj:TFontObj;
    Field:string;
    Align:TAlignment;
    CalculatedRect:TRect;
    Data:array of string;
    DataRunning: array of TRunningData;
  end;


  TSection = record
    LogoImageObj:TImageObj;
    DisplayOnlyLogo:boolean;
    LogoFilePath:string;
    LogoEnabled:boolean;
    LogoHasAlpha:boolean;
    SQLFilePath:string;
    HeaderIndent:integer;
    Header2Indent:integer;
    WordWrap:boolean;
    TextBGColor:TColor;
    TextAltBGColor:TColor;
    TextBGBeginOdd:boolean;
    AllRowsField:string;
    AllRowsFieldTextColor:TColor;
    AllRowsFieldOptionalRunning:integer;
    Caption:string;
    CaptionEng:string;
    MainBGColor:TColor;
    HeaderBGColor:TColor;
    CaptionFont:string;
    CaptionSize:integer;
    CaptionColor:TColor;
    CaptionFontObj:TFontObj;
    CaptionEngFont:string;
    CaptionEngSize:integer;
    CaptionEngColor:TColor;
    CaptionEngFontObj:TFontObj;
    DateText:string;
    DateTextEng:string;
    TimeText:string;
    TimeTextEng:string;
    DateTimeFont:string;
    DateTimeSize:integer;
    DateTimeColor:TColor;
    DateTimeFontObj:TFontObj;
    DateTimeEngFont:string;
    DateTimeEngSize:integer;
    DateTimeEngColor:TColor;
    DateTimeEngFontObj:TFontObj;
    DateTimeBGColor:TColor;
    DateTimeNumbersFont:string;
    DateTimeNumbersSize:integer;
    DateTimeNumbersColor:TColor;
    DateTimeNumbersFontObj:TFontObj;
    TimeFormat:string;
    DateFormat:string;
    TimeString:string;
    DateString:string;
    TimeEnabled:boolean;
    DateEnabled:boolean;
    DateTimeDelta:integer;
    //ZQ:TZQuery;
    Area:TRect;
    HeaderMainRect:TRect;
    HeaderCaptionRect:TRect;
    DataRowsRect:TRect;
    DateRect:TRect;
    TimeRect:TRect;
    NeedsRepaint:boolean;
    UseAlpha:boolean;
    AlphaTruncate:double;
    LineSeparatorEnabled:boolean;
    LineSeparatorAllRowsFieldEnabled:boolean;
    LineSeparatorHeight:integer;
    LineSeparatorColor:TColor;
    Columns:array of TColumn;
  end;

  TSectionArr=array of TSection;
  PTSectionArr=^TSectionArr;

var h_Wnd: HWND;
    h_Dc: HDC;
    h_Rc: HGLRC;
    WndWidth,WndHeight:integer;
    RealWndWidth,RealWndHeight:integer;

function WinMain(hInstance: HINST; hPrevInstance: HINST; lpCmdLine: PChar; nCmdShow: integer):integer; stdcall;

procedure Log(mess:string; time:boolean=true);

implementation

uses dglOpengl, Messages, SysUtils, INIFiles, dataWorkUnit;

const DateTimeRecsDelta=5;
Timer1ID=100;

var LogFileName:string='';
    INIFileName:string='';

    //объект потока, для загрузки данных из SQL
    SQLDataThread:TDataThread;

    TimeFreq:int64;  //частота процеррорных тактов

    FontsList:TStringList=nil;

    WindowActive:boolean;

    //настройки секций
    Sections:TSectionArr;

    //настройки
    SQLHost:string;
    SQLDatabase:string;
    SQLLogin:string;
    SQLPass:string;
    ColumnsWidthType:string;
    SectionsWidthCount:integer;
    SectionsHeightCount:integer;
    SectionSwapEnabled:boolean;
    SectionSwapInterval:integer;
    ScreenCopyEnabled:boolean;
    ScreenCopyWidthCount:integer;
    ScreenCopyHeightCount:integer;
    FallBackImagePath:string;
    //FallBackImage:TPicture;
    FallBackEnabled:boolean;
    FallBackImageObj:TImageObj;
    ScreenCopyImageObj:TImageObj;
    SQLUpdateInterval:integer;
    TargetFPS:integer;
    UseVSync:boolean=false;
    LogEnabled:boolean=true;

    //бегущая строка
    RunningEnabled:boolean;
    RunningSpeed:integer;
    RunningText:string;
    RunningFont:string;
    RunningColor:TColor;
    RunningSize:integer;
    RunningFontObj:TFontObj;
    RunningRect:TRect;
    RunningPosReal:double;
    RunningPos:integer;
    RunningTimestamp:int64;
    RunningPixelWidth:integer;

    OverallScreenRect:TRect;
    OverallScreenRectForCopy:TRect;
    TimerHNDL:cardinal;

    //переменные для смены секции
    CurrentSection:integer;

//========================================
//--------------functions-----------------
//========================================
function GetModuleFileNameStr(Instance: THandle): string;
var
  buffer: array [0..MAX_PATH] of Char;
begin
  GetModuleFileName( Instance, buffer, MAX_PATH);
  Result := buffer;
end;

procedure Log(mess:string; time:boolean=true);
var handl:integer;
temp_mess:string;
begin
  if not(LogEnabled) then exit;
  temp_mess:=Mess+#13+#10;
  if time=true then temp_mess:=FormatDateTime('dd.mm.yyyy hh:nn:ss.zzz',now)+'  '+temp_mess;

  if LogFileName<>'' then
  begin
    if FileExists(LogFileName) then
      handl:=FileOpen(LogFileName,fmOpenReadWrite or fmShareDenyNone)
    else
      handl:=FileCreate(LogFileName);

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

procedure CopyScreenToTexture(x, y, width, height: integer; Texture: GLuint);
begin
  glLoadIdentity;
  glBindTexture(GL_TEXTURE_2D, Texture);
  glCopyTexImage2D(GL_TEXTURE_2D,0,GL_RGBA,x,y,width,height,0);
end;

function GetRectOfMonitorContainingRect(const R: TRect; out res:TRect): boolean;
{ Returns bounding rectangle of monitor containing or nearest to R }
type
  HMONITOR = type THandle;
  TMonitorInfo = record
    cbSize: DWORD;
    rcMonitor: TRect;
    rcWork: TRect;
    dwFlags: DWORD;
  end;
const
  MONITOR_DEFAULTTONEAREST = $00000002;
var
  Module: HMODULE;
  MonitorFromRect: function(const lprc: TRect; dwFlags: DWORD): HMONITOR; stdcall;
  GetMonitorInfo: function(hMonitor: HMONITOR; var lpmi: TMonitorInfo): BOOL; stdcall;
  M: HMONITOR;
  Info: TMonitorInfo;
begin
  result:=false;
  Module := GetModuleHandle(user32);
  MonitorFromRect := GetProcAddress(Module, 'MonitorFromRect');
  GetMonitorInfo := GetProcAddress(Module, 'GetMonitorInfoA');
  if Assigned(MonitorFromRect) and Assigned(GetMonitorInfo) then
  begin
    M := MonitorFromRect(R, MONITOR_DEFAULTTONEAREST);
    Info.cbSize := SizeOf(Info);
    if GetMonitorInfo(M, Info) then
    begin
      res:=Info.rcMonitor;
      result:=true;
    end;
  end
  else exit;
end;

{procedure CalculateTextDimensions(FontObj:TFontObj; text:string; out Width:integer; out Height:integer); overload;
begin
  Width:=FontObj.TextWidth(text);
  Height:=FontObj.TextHeight(text);
end;

procedure CalculateTextDimensions(FontObj:TFontObj; text:string; var BorderRect:TRect; out Height:integer; WordWrap:boolean=false); overload;
var i,j:integer;
begin
  if WordWrap=false then
  begin
    i:=FontObj.TextWidth(text);
    j:=FontObj.TextHeight(text); 
    Height:=j;
    BorderRect.Right:=BorderRect.Left+i;
    BorderRect.Bottom:=BorderRect.Top+j;
  end
  else
  begin
    j:=FontObj.TextDimensions(text,BorderRect.Right-BorderRect.Left,i);
    Height:=j;
    if BorderRect.Right<(BorderRect.Left+i) then BorderRect.Right:=BorderRect.Left+i;
    if BorderRect.Bottom<(BorderRect.Top+j) then BorderRect.Bottom:=BorderRect.Top+j;
  end;
end; }

function IncMinute(const AValue: TDateTime;
  const ANumberOfMinutes: Int64): TDateTime;
begin
  Result := ((AValue * MinsPerDay) + ANumberOfMinutes) / MinsPerDay;
end;

function Initialize:boolean;
var dc:HDC;
LFont:TLogFont;
INIFile:TINIFile;
i,j,k,z,k1,z1:integer;
str,str1,str2:string;
r,WindowRect:TRect;

  function EnumFontsCallback(var LogFont: TLogFont; var TextMetric: TTextMetric;
  FontType: Integer; Data: Pointer): Integer; stdcall;
  var S: TStrings;
  Temp: string;
  begin
    S := TStrings(Data);
    Temp := LogFont.lfFaceName;
    if (S.Count = 0) or (AnsiCompareText(S[S.Count-1], Temp) <> 0) then
      S.Add(Temp);
    Result := 1;
  end;

begin
  result:=false;
  Log('Initialization function enter');

  //создаём список шрифтов
  FontsList:=TStringList.Create;
  dc:=GetDC(0);
  try
    FontsList.Add('Default');
    FillChar(LFont, sizeof(LFont), 0);
    LFont.lfCharset := DEFAULT_CHARSET;
    EnumFontFamiliesEx(DC, LFont, @EnumFontsCallback, LongInt(FontsList), 0);
    FontsList.Sorted:=true;
  finally
    ReleaseDC(0, DC);
  end;
  Log('Fonts enumirated, font count='+inttostr(FontsList.Count));

  //читаем INI-файл
  if FileExists(INIFileName)=false then
  begin
    Log('ERROR! INIFile not found');
    exit;
  end;
  INIFile:=TINIFile.Create(INIFileName);
  try
    //читаем SQL настройки и заносим
    SQLHost:=INIFile.ReadString('Main','Host','localhost');
    SQLDatabase:=INIFile.ReadString('Main','Database','');
    SQLLogin:=INIFile.ReadString('Main','Login','root');
    SQLPass:=INIFile.ReadString('Main','Pass','1');

    //читаем бегущую строку
    RunningEnabled:=INIFIle.ReadBool('Running','Enabled',false);
    RunningSpeed:=INIFile.ReadInteger('Running','Speed',80);
    RunningText:=INIFile.ReadString('Running','Text','   ');
    RunningFont:=INIFile.ReadString('Running','Font','');
    RunningColor:=INIFile.ReadInteger('Running','TextColor',0);
    RunningSize:=INIFile.ReadInteger('Running','TextSize',20);
    if FontsList.IndexOf(RunningFont)=-1 then
    begin
      Log('ERROR! Running font not found');
      exit;
    end;
    //все шрифты создаём потом
    RunningPosReal:=0;
    RunningPos:=0;

    //читаем тип ширины колонок
    ColumnsWidthType:=AnsiLowerCase(INIFile.ReadString('Main','ColumnsWidthType','percent'));
    if ColumnsWidthType<>'percent' then
      if ColumnsWidthType<>'pixel' then
      begin
        Log('ERROR! Unknown value in ColumnsWidthType');
        exit;
      end;

    //читаем кол-во секций по ширине и высоте
    SectionsWidthCount:=INIFile.ReadInteger('Main','SectionsWidthCount',1);
    SectionsHeightCount:=INIFile.ReadInteger('Main','SectionsHeightCount',1);
    if (SectionsWidthCount<1)or(SectionsHeightCount<1) then
    begin
      Log('ERROR! SectionsWidthCount or SectionsHeightCount is less then 1');
      exit;
    end;

    //читаем настройки смены секции
    SectionSwapEnabled:=INIFile.ReadBool('Main','SectionSwapEnabled',false);
    SectionSwapInterval:=INIFile.ReadInteger('Main','SectionSwapInterval',10000);
    CurrentSection:=0;

    //читаем fallback картинку
    FallBackEnabled:=INIFile.ReadBool('Main','FallBackEnabled',true);
    FallBackImagePath:=INIFile.ReadString('Main','FallBackImage','');
    if FileExists(FallBackImagePath)=false then
    begin
      Log('ERROR! Can''t find fallback image');
      exit;
    end;

    //читаем интервал обновления данных
    SQLUpdateInterval:=INIFile.ReadInteger('Main','SQLUpdateInterval',5000);

    //читаем настройки FPS
    TargetFPS:=INIFile.ReadInteger('Main','TargetFPS',30); 

    //читаем настройки лога
    LogEnabled:=INIFile.ReadBool('Main','Log',false);

    //читаем настройки всех секций и колонок для секций
    k:=1;  //номер секции
    setlength(Sections,0);
    for i:=1 to SectionsHeightCount do  //номер строки
    begin
      for j:=1 to SectionsWidthCount do  //номер колонки
      begin
        //ищем секцию
        str:='Section'+inttostr(k);
        inc(k);
        if INIFile.SectionExists(str) then  //если нашли секцию, то читаем
        begin
          z:=length(Sections);
          setlength(Sections,z+1);

          Sections[z].LogoEnabled:=INIFile.ReadBool(str,'LogoEnabled',false);
          Sections[z].LogoHasAlpha:=INIFile.ReadBool(str,'LogoHasAlpha',true);
          Sections[z].LogoFilePath:=INIFile.ReadString(str,'Logo','');
          Sections[z].DisplayOnlyLogo:=INIFile.ReadBool(str,'DisplayOnlyLogo',false);
          if Sections[z].LogoFilePath<>'' then
            if FileExists(Sections[z].LogoFilePath)=false then
            begin
              Sections[z].LogoEnabled:=false;
              Sections[z].DisplayOnlyLogo:=false;
            end;
          //загружаем лого позже
          Sections[z].SQLFilePath:=INIFile.ReadString(str,'SQL','');
          Sections[z].HeaderIndent:=INIFile.ReadInteger(str,'HeaderIndent',5);
          Sections[z].Header2Indent:=INIFile.ReadInteger(str,'Header2Indent',3);
          Sections[z].WordWrap:=INIFile.ReadBool(str,'WordWrap',true);
          Sections[z].TextBGColor:=INIFile.ReadInteger(str,'TextBGColor',0);
          Sections[z].TextAltBGColor:=INIFile.ReadInteger(str,'TextAltBGColor',0);
          Sections[z].TextBGBeginOdd:=INIFile.ReadBool(str,'TextBGBeginOdd',true);
          Sections[z].AllRowsField:=INIFile.ReadString(str,'AllRowsField','');
          Sections[z].AllRowsFieldTextColor:=INIFile.ReadInteger(str,'AllRowsFieldTextColor',0);
          Sections[z].AllRowsFieldOptionalRunning:=INIFile.ReadInteger(str,'AllRowsFieldOptionalRunning',0);
          Sections[z].Caption:=INIFile.ReadString(str,'Caption',' ');
          Sections[z].CaptionEng:=INIFile.ReadString(str,'CaptionEng',' ');
          Sections[z].MainBGColor:=INIFile.ReadInteger(str,'MainBGColor',0);
          Sections[z].HeaderBGColor:=INIFile.ReadInteger(str,'HeaderBGColor',0);
          Sections[z].CaptionFont:=INIFile.ReadString(str,'CaptionFont','');
          Sections[z].CaptionSize:=INIFile.ReadInteger(str,'CaptionSize',12);
          Sections[z].CaptionColor:=INIFile.ReadInteger(str,'CaptionColor',0);
          Sections[z].CaptionEngFont:=INIFile.ReadString(str,'CaptionEngFont','');
          Sections[z].CaptionEngSize:=INIFile.ReadInteger(str,'CaptionEngSize',10);
          Sections[z].CaptionEngColor:=INIFile.ReadInteger(str,'CaptionEngColor',0);
          Sections[z].DateText:=INIFile.ReadString(str,'DateText','  ');
          Sections[z].DateTextEng:=INIFile.ReadString(str,'DateTextEng','  ');
          Sections[z].TimeText:=INIFile.ReadString(str,'TimeText','  ');
          Sections[z].TimeTextEng:=INIFile.ReadString(str,'TimeTextEng','  ');
          Sections[z].DateTimeFont:=INIFile.ReadString(str,'DateTimeFont','');
          Sections[z].DateTimeSize:=INIFile.ReadInteger(str,'DateTimeSize',12);
          Sections[z].DateTimeColor:=INIFile.ReadInteger(str,'DateTimeColor',0);
          Sections[z].DateTimeEngFont:=INIFile.ReadString(str,'DateTimeEngFont','');
          Sections[z].DateTimeEngSize:=INIFile.ReadInteger(str,'DateTimeEngSize',11);
          Sections[z].DateTimeEngColor:=INIFile.ReadInteger(str,'DateTimeEngColor',0);
          Sections[z].DateTimeBGColor:=INIFIle.ReadInteger(str,'DateTimeBGColor',0);
          Sections[z].DateTimeNumbersFont:=INIFile.ReadString(str,'DateTimeNumbersFont','');
          Sections[z].DateTimeNumbersSize:=INIFile.ReadInteger(str,'DateTimeNumbersSize',10);
          Sections[z].DateTimeNumbersColor:=INIFile.ReadInteger(str,'DateTimeNumbersColor',0);
          Sections[z].TimeFormat:=INIFile.ReadString(str,'TimeFormat','hh:nn');
          Sections[z].DateFormat:=INIFile.ReadString(str,'DateFormat','dd.mm');
          Sections[z].TimeString:=FormatDateTime(Sections[z].TimeFormat,now);
          Sections[z].DateString:=FormatDateTime(Sections[z].DateFormat,now);
          Sections[z].TimeEnabled:=INIFile.ReadBool(str,'TimeEnabled',true);
          Sections[z].DateEnabled:=INIFile.ReadBool(str,'DateEnabled',true);
          Sections[z].DateTimeDelta:=INIFile.ReadInteger(str,'DateTimeDelta',0);
          Sections[z].UseAlpha:=INIFile.ReadBool(str,'UseAlpha',false);
          k1:=INIFile.ReadInteger(str,'AlphaTruncate',750);
          if k1<0 then k1:=0;
          if k1>1000 then k1:=1000;
          Sections[z].AlphaTruncate:=k1/1000;
          Sections[z].LineSeparatorEnabled:=INIFile.ReadBool(str,'LineSeparatorEnabled',false);
          Sections[z].LineSeparatorAllRowsFieldEnabled:=INIFile.ReadBool(str,'LineSeparatorAllRowsFieldEnabled',false);
          Sections[z].LineSeparatorHeight:=INIFile.ReadInteger(str,'LineSeparatorHeight',1);
          Sections[z].LineSeparatorColor:=INIFile.ReadInteger(str,'LineSeparatorColor',0);
          Sections[z].Area:=Rect(0,0,0,0);
          Sections[z].NeedsRepaint:=false;
          setlength(Sections[z].Columns,0);
          //ищем колонки
          k1:=1;
          str1:=str+'Column'+inttostr(k1);
          while (INIFile.SectionExists(str1)=true) do
          begin
            z1:=length(Sections[z].Columns);
            setlength(Sections[z].Columns,z1+1);
            Sections[z].Columns[z1].Width:=INIFile.ReadInteger(str1,'Width',0);
            Sections[z].Columns[z1].DataFont:=INIFile.ReadString(str1,'DataFont','');
            Sections[z].Columns[z1].DataSize:=INIFile.ReadInteger(str1,'DataSize',12);
            Sections[z].Columns[z1].DataColor:=INIFIle.ReadInteger(str1,'DataColor',16777215);
            //все шрифты создаём потом
            Sections[z].Columns[z1].CaptionText:=INIFile.ReadString(str1,'CaptionText',' ');
            Sections[z].Columns[z1].CaptionTextFont:=INIFile.ReadString(str1,'CaptionTextFont','');
            Sections[z].Columns[z1].CaptionTextSize:=INIFile.ReadInteger(str1,'CaptionTextSize',10);
            Sections[z].Columns[z1].CaptionTextColor:=INIFile.ReadInteger(str1,'CaptionTextColor',0);
            //все шрифты создаём потом
            Sections[z].Columns[z1].CaptionTextEng:=INIFile.ReadString(str1,'CaptionTextEng',' ');
            Sections[z].Columns[z1].CaptionTextEngFont:=INIFile.ReadString(str1,'CaptionTextEngFont','');
            Sections[z].Columns[z1].CaptionTextEngSize:=INIFile.ReadInteger(str1,'CaptionTextEngSize',10);
            Sections[z].Columns[z1].CaptionTextEngColor:=INIFile.ReadInteger(str1,'CaptionTextEngColor',0);
            Sections[z].Columns[z1].Field:=INiFile.ReadString(str1,'Field','');
            str2:=ANSILowerCase(INIFile.ReadString(str1,'Align','left'));
            if str2='center' then Sections[z].Columns[z1].Align:=taCenter
            else if str2='right' then Sections[z].Columns[z1].Align:=taRightJustify
            else Sections[z].Columns[z1].Align:=taLeftJustify;
            inc(k1);
            str1:=str+'Column'+inttostr(k1);
          end;
          //добавляем ещё одну колонку на всю строку, если надо
          if Sections[z].AllRowsField<>'' then
          begin
            z1:=length(Sections[z].Columns);
            setlength(Sections[z].Columns,z1+1);
            Sections[z].Columns[z1].Width:=0;
            Sections[z].Columns[z1].DataFont:=INIFile.ReadString(str,'AllRowsFieldTextFont','');;
            Sections[z].Columns[z1].DataSize:=INIFile.ReadInteger(str,'AllRowsFieldTextSize',12);;
            Sections[z].Columns[z1].DataColor:=Sections[z].AllRowsFieldTextColor;
            //все шрифты создаём потом
            Sections[z].Columns[z1].CaptionText:='';
            Sections[z].Columns[z1].CaptionTextFont:=Sections[z].Columns[z1].DataFont;
            Sections[z].Columns[z1].CaptionTextSize:=10;
            Sections[z].Columns[z1].CaptionTextColor:=0;
            //все шрифты создаём потом
            Sections[z].Columns[z1].CaptionTextEng:='';
            Sections[z].Columns[z1].CaptionTextEngFont:=Sections[z].Columns[z1].DataFont;
            Sections[z].Columns[z1].CaptionTextEngSize:=10;
            Sections[z].Columns[z1].CaptionTextEngColor:=0;
            Sections[z].Columns[z1].Field:=Sections[z].AllRowsField;
            Sections[z].Columns[z1].Align:=taLeftJustify;       
          end;
        end
        else
        begin  //не нашли секцию, значит что-то не так и выходим
          Log('ERROR! Expected section is not found, section='+str);
          exit;  
        end;
      end;
    end;

    //проверяем, правильно ли заполнены поля
    for i:=0 to length(Sections)-1 do
    begin
      if Sections[i].SQLFilePath='' then
      begin
        Log('ERROR! SQL file path is empty in section#'+inttostr(i));
        exit;
      end
      else if FileExists(Sections[i].SQLFilePath)=false then
      begin
        Log('ERROR! SQL file is not found in section#'+inttostr(i));
        exit;
      end;
      if (FontsList.IndexOf(Sections[i].CaptionFont)=-1)or
      (FontsList.IndexOf(Sections[i].CaptionEngFont)=-1)or
      (FontsList.IndexOf(Sections[i].DateTimeFont)=-1)or
      (FontsList.IndexOf(Sections[i].DateTimeEngFont)=-1)or
      (FontsList.IndexOf(Sections[i].DateTimeNumbersFont)=-1) then
      begin
        Log('ERROR! Font not found');
        exit;
      end;
    
      if length(Sections[i].Columns)=0 then
      begin
        Log('ERROR! Section #'+inttostr(i)+' column length=0');
        exit;
      end;
      for j:=0 to length(Sections[i].Columns)-1 do
      begin
        //шрифт текста колонки
        if (FontsList.IndexOf(Sections[i].Columns[j].CaptionTextFont)=-1)or
        (FontsList.IndexOf(Sections[i].Columns[j].CaptionTextEngFont)=-1)or
        (FontsList.IndexOf(Sections[i].Columns[j].DataFont)=-1) then
        begin
          Log('ERROR! Fonts not found, CaptionTextFont='+inttostr(FontsList.IndexOf(Sections[i].Columns[j].CaptionTextFont))+', CaptionTextEngFont='+inttostr(FontsList.IndexOf(Sections[i].Columns[j].CaptionTextEngFont))+', DataFont='+inttostr(FontsList.IndexOf(Sections[i].Columns[j].DataFont)));
          exit;
        end;
        if Sections[i].Columns[j].Field='' then
        begin
          Log('ERROR! Column/Field font not found');
          exit;
        end;
      end;
    end;

    Log('SectionCount='+inttostr(length(Sections)));
    for i:=0 to length(Sections)-1 do
      Log('  Section#'+inttostr(i)+'   ColumnCount='+inttostr(length(Sections[i].Columns)));

    if length(Sections)=0 then
    begin
      Log('ERROR! Sections cound is 0');
      exit;
    end;
  finally
    INIFile.Free;
  end;
  Log('INI file read complete');

  //загружаем текстуру для fallback
  FallBackImageObj:=FindOrCreateImageObj(FallBackImagePath,false);
  if FallBackImageObj.Texture=0 then
  begin
    Log('ERROR! Fallback texture is 0');
    exit;
  end;

  r.Left:=10;
  r.Top:=10;
  r.Right:=300;
  r.Bottom:=300;
  GetRectOfMonitorContainingRect(r,WindowRect);

  //ScreenCopyImageObj:=FindOrCreateImageObj(FallBackImagePath,false);
  //ScreenCopyImageObj:=FindOrCreateImageObj(ExtractFileDir(FallBackImagePath)+'fallback2.jpg',false);
  ScreenCopyImageObj:=CreateEmptyImageObj(WindowRect.Right-WindowRect.Left,WindowRect.Bottom-WindowRect.Top,false);

  Log('Initialization function complete');

  result:=true;
end;

function InitializeFontsAndImages:boolean;
var i,j:integer;
begin
  result:=false;
  Log('FontAndImages Initialization function enter');

  //шрифт для бегущей строки
  RunningFontObj:=FindOrCreateFontObj(RunningFont,RunningSize,RunningColor);

  //идём по секциям
  for i:=0 to length(Sections)-1 do
  begin
    //создаём лого для каждой секции если надо
    if (Sections[i].LogoEnabled=true)or(Sections[i].DisplayOnlyLogo=true) then
      Sections[i].LogoImageObj:=FindOrCreateImageObj(Sections[i].LogoFilePath,Sections[i].LogoHasAlpha);
    //создаём шрифты для заголовков секций
    Sections[i].CaptionFontObj:=FindOrCreateFontObj(Sections[i].CaptionFont,Sections[i].CaptionSize,Sections[i].CaptionColor);
    Sections[i].CaptionEngFontObj:=FindOrCreateFontObj(Sections[i].CaptionEngFont,Sections[i].CaptionEngSize,Sections[i].CaptionEngColor);
    //создаём шрифт для надписей рядом с часами
    Sections[i].DateTimeFontObj:=FindOrCreateFontObj(Sections[i].DateTimeFont,Sections[i].DateTimeSize,Sections[i].DateTimeColor);
    Sections[i].DateTimeEngFontObj:=FindOrCreateFontObj(Sections[i].DateTimeEngFont,Sections[i].DateTimeEngSize,Sections[i].DateTimeEngColor);
    //создаём шрифт для самих цыфр даты и времени
    Sections[i].DateTimeNumbersFontObj:=FindOrCreateFontObj(Sections[i].DateTimeNumbersFont,Sections[i].DateTimeNumbersSize,Sections[i].DateTimeNumbersColor);

    //идём по колонкам
    for j:=0 to length(Sections[i].Columns)-1 do
    begin
      //создаём шрифт для данных
      Sections[i].Columns[j].DataFontObj:=FindOrCreateFontObj(Sections[i].Columns[j].DataFont,Sections[i].Columns[j].DataSize,Sections[i].Columns[j].DataColor);
      //создаём шрифты для заголовка колонки
      Sections[i].Columns[j].CaptionTextFontObj:=FindOrCreateFontObj(Sections[i].Columns[j].CaptionTextFont,Sections[i].Columns[j].CaptionTextSize,Sections[i].Columns[j].CaptionTextColor);
      Sections[i].Columns[j].CaptionTextEngFontObj:=FindOrCreateFontObj(Sections[i].Columns[j].CaptionTextEngFont,Sections[i].Columns[j].CaptionTextEngSize,Sections[i].Columns[j].CaptionTextEngColor);
    end;
  end;

  Log('FontAndImages Initialization function complete');
  Log('List of image objects, object number='+inttostr(length(ImageElementsArr)));
  for i:=0 to length(ImageElementsArr)-1 do
    Log('ImageObj#'+inttostr(i)+'  ImageName='+ImageElementsArr[i].ImageName+', Transparent='+booltostr(ImageElementsArr[i].ImageTransparent,true),false);

  Log('List of font objects, object number='+inttostr(length(FontsElementsArr)));
  for i:=0 to length(FontsElementsArr)-1 do
    Log('FontObj#'+inttostr(i)+'  FontName='+FontsElementsArr[i].FontName+', FontSize='+inttostr(FontsElementsArr[i].FontSize)+', FontColor='+inttostr(FontsElementsArr[i].FontObj.FontColor),false);

  result:=true;
end;

function InitializeRecs:boolean;
var i,j,k,z,i1,z1:integer;
header1:integer;
mul:double;
begin
  result:=false;
  Log('Recs Initialization function enter');

  //определяем координаты всех секций и колонок
  OverallScreenRect:=Rect(0,0,WndWidth,WndHeight);
  OverallScreenRectForCopy:=OverallScreenRect;
  if RunningEnabled then
  begin
    RunningText:='    '+RunningText+'    ';
    //CalculateTextDimensions(RunningFontObj,RunningText,i,j);
    RunningFontObj.CalcTextDimensions(RunningText,OverallScreenRect,i,j);
    OverallScreenRect.Bottom:=OverallScreenRect.Bottom-j;
    RunningRect:=Rect(OverallScreenRect.Left,OverallScreenRect.Bottom,OverallScreenRect.Right,OverallScreenRect.Bottom+j);
    RunningPixelWidth:=i;
  end;
  for i:=0 to length(Sections)-1 do
  begin   
    if SectionSwapEnabled=true then
    begin
      Sections[i].Area:=OverallScreenRect;
    end
    else
    begin
      //определяем номер колонки и строки секции
      z:=i+1;
      k:=(z mod SectionsWidthCount);  //номер столбца
      if k=0 then
      begin
        j:=z div SectionsWidthCount;  //номер строки
        k:=SectionsWidthCount;
      end
      else
        j:=(z div SectionsWidthCount)+1;  //номер строки

      //определяем сначала правильную ширину области
      z:=OverallScreenRect.Right div SectionsWidthCount;
      //определяем, насколько надо сдвигать вправо
      if k=SectionsWidthCount then Sections[i].Area.Right:=OverallScreenRect.Right
      else Sections[i].Area.Right:=z*k;
      Sections[i].Area.Left:=z*(k-1);

      //определяем правильную высоту
      z:=OverallScreenRect.Bottom div SectionsHeightCount;
      if j=SectionsHeightCount then Sections[i].Area.Bottom:=OverallScreenRect.Bottom
      else Sections[i].Area.Bottom:=z*j;
      Sections[i].Area.Top:=z*(j-1);
    end;

    //определяем высоту первой рамки заголовка по высоте главного текста (2 строк, русской и английской)
    //CalculateTextDimensions(Sections[i].CaptionFontObj,Sections[i].Caption,j,k);
    Sections[i].CaptionFontObj.CalcTextDimensions(Sections[i].Caption,OverallScreenRect,j,k);
    z:=k;
    //CalculateTextDimensions(Sections[i].CaptionEngFontObj,Sections[i].CaptionEng,j,k);
    Sections[i].CaptionEngFontObj.CalcTextDimensions(Sections[i].CaptionEng,OverallScreenRect,j,k);
    z:=z+k;
    Sections[i].HeaderMainRect:=Rect(Sections[i].Area.Left,Sections[i].Area.Top,Sections[i].Area.Right,Sections[i].Area.Top+z+Sections[i].HeaderIndent*2);
    header1:=Sections[i].HeaderMainRect.Bottom-Sections[i].HeaderMainRect.Top;

    //определям координаты колонок в каждой секции
    //определяем соотношение каждого пункта ширины колонки к пикселям
    //также вычисляем максимум высоты в заголовке
    z1:=0;  //максимум
    if ColumnsWidthType='percent' then mul:=(Sections[i].Area.Right-Sections[i].Area.Left)/100  //один пункт это один процент, т.е. мы должны ширину поделить на 100%
    else mul:=1;  //тут мы определяем по пикселям, т.е. один пункт это один пиксель
    for j:=0 to length(Sections[i].Columns)-1 do
    begin
      //смотрим, может это специальное поле на всю длинну
      if (Sections[i].Columns[j].Field=Sections[i].AllRowsField)and(Sections[i].AllRowsField<>'') then
      begin
        //вычисляем ширину
        z:=Sections[i].Area.Right-Sections[i].Area.Left;
        Sections[i].Columns[j].CalculatedRect:=Rect(Sections[i].Area.Left+5,0,Sections[i].Area.Right,0);
      end
      else
      begin
        //вычисляем ширину
        z:=trunc(Sections[i].Columns[j].Width*mul);
        if j=0 then Sections[i].Columns[j].CalculatedRect:=Rect(Sections[i].Area.Left,0,Sections[i].Area.Left+z,0)
        else Sections[i].Columns[j].CalculatedRect:=Rect(Sections[i].Columns[j-1].CalculatedRect.Right,0,Sections[i].Columns[j-1].CalculatedRect.Right+z,0);
        //Sections[i].Columns[j].CalculatedRect:=Rect(Sections[i].Area.Left+j*z,0,Sections[i].Area.Left+(j+1)*z,0);

        //убираем не помещающиеся
        if Sections[i].Columns[j].CalculatedRect.Right>Sections[i].Area.Right then Sections[i].Columns[j].CalculatedRect:=Rect(0,0,0,0)
        else if (j=(length(Sections[i].Columns)-1))and(Sections[i].Columns[j].CalculatedRect.Right<Sections[i].Area.Right) then Sections[i].Columns[j].CalculatedRect.Right:=Sections[i].Area.Right;
        //смотрим максимум для заголовка
        //CalculateTextDimensions(Sections[i].Columns[j].CaptionTextFontObj,Sections[i].Columns[j].CaptionText,k,z);
        //Sections[i].Columns[j].CaptionTextFontObj.CalcTextDimensions(Sections[i].Columns[j].CaptionText,OverallScreenRect,k,z,Sections[i].WordWrap);
        Sections[i].Columns[j].CaptionTextFontObj.CalcTextDimensions(Sections[i].Columns[j].CaptionText,Sections[i].Columns[j].CalculatedRect,k,z,Sections[i].WordWrap);
        i1:=z;
        //CalculateTextDimensions(Sections[i].Columns[j].CaptionTextEngFontObj,Sections[i].Columns[j].CaptionTextEng,k,z);
        //Sections[i].Columns[j].CaptionTextEngFontObj.CalcTextDimensions(Sections[i].Columns[j].CaptionTextEng,OverallScreenRect,k,z,Sections[i].WordWrap);
        Sections[i].Columns[j].CaptionTextEngFontObj.CalcTextDimensions(Sections[i].Columns[j].CaptionTextEng,Sections[i].Columns[j].CalculatedRect,k,z,Sections[i].WordWrap);
        i1:=i1+z;
        if i1>z1 then z1:=i1;
      end;
    end;
    Sections[i].HeaderCaptionRect:=Rect(Sections[i].Area.Left,Sections[i].Area.Top+header1,Sections[i].Area.Right,Sections[i].Area.Top+header1+z1+Sections[i].Header2Indent);

    //определяем координаты поля времени
    Sections[i].TimeString:=FormatDateTime(Sections[i].TimeFormat,now);
    //CalculateTextDimensions(Sections[i].DateTimeNumbersFontObj,Sections[i].TimeString,j,k);
    Sections[i].DateTimeNumbersFontObj.CalcTextDimensions(Sections[i].TimeString,OverallScreenRect,j,k);
    Sections[i].TimeRect:=Rect(Sections[i].Area.Right-DateTimeRecsDelta*2-j-DateTimeRecsDelta,Sections[i].Area.Top+((Sections[i].HeaderMainRect.Bottom-Sections[i].HeaderMainRect.Top) div 2)-(k div 2),Sections[i].Area.Right-DateTimeRecsDelta,Sections[i].Area.Top+((Sections[i].HeaderMainRect.Bottom-Sections[i].HeaderMainRect.Top) div 2)+(k div 2));

    //определяем координаты поля даты
    //CalculateTextDimensions(Sections[i].DateTimeFontObj,Sections[i].TimeText,j,k);
    Sections[i].DateTimeFontObj.CalcTextDimensions(Sections[i].TimeText,OverallScreenRect,j,k);
    i1:=j;
    //CalculateTextDimensions(Sections[i].DateTimeEngFontObj,Sections[i].TimeTextEng,j,k);
    Sections[i].DateTimeEngFontObj.CalcTextDimensions(Sections[i].TimeTextEng,OverallScreenRect,j,k);
    if i1<j then i1:=j;
    z:=Sections[i].TimeRect.Left-DateTimeRecsDelta-i1-DateTimeRecsDelta*2;
    Sections[i].DateString:=FormatDateTime(Sections[i].DateFormat,now);
    //CalculateTextDimensions(Sections[i].DateTimeNumbersFontObj,Sections[i].DateString,j,k);
    Sections[i].DateTimeNumbersFontObj.CalcTextDimensions(Sections[i].DateString,OverallScreenRect,j,k);
    Sections[i].DateRect:=Rect(z-DateTimeRecsDelta-j,Sections[i].Area.Top+((Sections[i].HeaderMainRect.Bottom-Sections[i].HeaderMainRect.Top) div 2)-(k div 2),z,Sections[i].Area.Top+((Sections[i].HeaderMainRect.Bottom-Sections[i].HeaderMainRect.Top) div 2)+(k div 2));
  end;

  Log('Recs Initialization function complete');
  result:=true;
end;    

procedure DrawGLRunning;
begin
  RunningFontObj.DrawText(RunningPosReal,RunningRect.Top,RunningText);
end;

procedure CalculateGLRunning;
var Ticks:int64;
d:extended;
begin
  QueryPerformanceCounter(Ticks);
  d:=((Ticks-RunningTimestamp)/TimeFreq)*(RunningSpeed);
  RunningTimestamp:=Ticks;

  RunningPosReal:=RunningPosReal-d;
  if RunningPosReal<(-RunningPixelWidth) then RunningPosReal:=RunningRect.Right;
end;

procedure KillGLWindow;
var i,j:integer;
begin
  //удаляем таймер
  if TimerHNDL<>0 then
  begin
    if KillTimer(h_Wnd,Timer1ID)=false then
      Log('SHUTDOWN ERROR! KillTimer failed');
  end;

  //удаляем поток SQL
  if Assigned(SQLDataThread) then
  begin
    SQLDataThread.Terminate;
    SQLDataThread.WaitFor;
    SQLDataThread.Free;
    SQLDataThread:=nil;
  end;

  if h_rc<> 0 then
  begin
    if (not wglMakeCurrent(h_Dc,0)) then
      Log('SHUTDOWN ERROR! Release of DC and RC failed');
    if (not wglDeleteContext(h_Rc)) then
    begin
      Log('SHUTDOWN ERROR! Release of Rendering Context failed');
      h_Rc:=0;
    end;
  end;
  if (h_Dc=1) and (releaseDC(h_Wnd,h_Dc)<>0) then
  begin
    Log('SHUTDOWN ERROR! Release of Device Context failed');
    h_Dc:=0;
  end;
  if (h_Wnd<>0) and (not destroywindow(h_Wnd)) then
  begin
    Log('SHUTDOWN ERROR! Could not release hWnd');
    h_Wnd:=0;
  end;
  if (not Windows.UnregisterClass('VideoOpenGl',hInstance)) then
    Log('SHUTDOWN ERROR! Could Not Unregister Class');

  if FontsList<>nil then FontsList.Free;

  //смотрим, нужно ли удалять секции
  if length(Sections)<>0 then
  begin
    for i:=0 to length(Sections)-1 do
    begin
      for j:=0 to length(Sections[i].Columns)-1 do
      begin
        Setlength(Sections[i].Columns[j].Data,0);
        setlength(Sections[i].Columns[j].DataRunning,0);
      end;
      setlength(Sections[i].Columns,0);
    end;
    setlength(Sections,0);
  end;

  ShowCursor(true);

  //KillFont;                                             //Smazбnн fontu
end;

function WndProc(hWnd:HWND; message:UINT; wParam:WPARAM; lParam:LPARAM):LRESULT; stdcall;
var i:integer;
temp_time:TDateTime;
begin
  if message=WM_SYSCOMMAND then
  begin
    case wParam of
      SC_SCREENSAVE,SC_MONITORPOWER:
      begin
        result:=0;
        exit;
      end;
    end;
  end;

  case message of                                       // Vмtvenн podle pшнchozн zprбvy
    WM_ACTIVATE:                                        // Zmмna aktivity okna
    begin
      if (Hiword(wParam)=0) then                      // Zkontroluje zda nenн minimalizovanй
      begin
        WindowActive:=true;                                  // Program je aktivnн
        //Log('Window becomes active');
      end
      else
      begin
        WindowActive:=false;                                // Program nenн aktivnн
        //Log('Window becomes inactive');
      end;
      Result:=0;                                      // Nбvrat do hlavnнho cyklu programu
    end;
    WM_CLOSE:                                           // Povel k ukonиenн programu
    Begin
      PostQuitMessage(0);                             // Poљle zprбvu o ukonиenн
      result:=0                                       // Nбvrat do hlavnнho cyklu programu
    end;
    WM_KEYDOWN:                                         // Stisk klбvesy
    begin
      //keys[wParam] := TRUE;                           // Oznбmн to programu
      result:=0;                                      // Nбvrat do hlavnнho cyklu programu
    end;
    WM_KEYUP:                                           // Uvolnмnн klбvesy
    begin
      //keys[wParam] := FALSE;                            // Oznбmн to programu
      result:=0;                                      // Nбvrat do hlavnнho cyklu programu
    end;
    WM_SIZE:                                            // Zmмna velikosti okna
    begin
      //ReSizeGLScene(LOWORD(lParam),HIWORD(lParam));     // LoWord=Љншka, HiWord=Vэљka
      result:=0;                                      // Nбvrat do hlavnнho cyklu programu
    end;
    WM_SETCURSOR:
    begin
      ShowCursor(false);
    end;
    WM_TIMER:
    begin
      temp_time:=now;
      if wParam=Timer1ID then  //таймер для обновления строк времени и даты
      begin
        for i:=0 to length(Sections)-1 do
        begin
          Sections[i].TimeString:=FormatDateTime(Sections[i].TimeFormat,IncMinute(temp_time,Sections[i].DateTimeDelta));
          Sections[i].DateString:=FormatDateTime(Sections[i].DateFormat,IncMinute(temp_time,Sections[i].DateTimeDelta));
        end;
      end;
    end;
    else
    begin
      Result := DefWindowProc(hWnd, message, wParam, lParam);
    end;
  end;
end;

function CreateGlWindow:boolean stdcall;
var
  wc:TWndclass;
  dwExStyle:dword;
  dwStyle:dword;
  //h_Instance:hinst;
  R,WindowRect: TRect;
  str:string;
  INIFile:TINIFile;
  CustomEnabled:boolean;
  CustLeft,CustTop,CustWid,CustHei:integer;
begin
  result:=false;
  r.Left:=10;
  r.Top:=10;
  r.Right:=300;
  r.Bottom:=300;
  if GetRectOfMonitorContainingRect(r,WindowRect)=false then
  begin
    Log('ERROR! GetMonitorInfo returned false, exiting');
    exit;
  end;

  //читаем настройки для нестандартного окна
  if FileExists(INIFileName)=false then
  begin
    Log('ERROR! INIFile not found');
    exit;
  end;
  INIFile:=TINIFile.Create(INIFileName);
  try
    CustomEnabled:=INIFile.ReadBool('Main','CustomWindowEnabled',false);
    UseVSync:=INIFile.ReadBool('Main','UseVSync',false);
    ScreenCopyEnabled:=INIFile.ReadBool('Main','ScreenCopyEnabled',false);
    ScreenCopyWidthCount:=INIFile.ReadInteger('Main','ScreenCopyWidthCount',1);
    ScreenCopyHeightCount:=INIFile.ReadInteger('Main','ScreenCopyHeightCount',1);

    if ScreenCopyEnabled=true then
      if (ScreenCopyWidthCount=1)and(ScreenCopyHeightCount=1) then ScreenCopyEnabled:=false;

    if CustomEnabled then
    begin
      CustLeft:=INIFile.ReadInteger('Main','CustomWindowLeft',0);
      CustTop:=INIFile.ReadInteger('Main','CustomWindowTop',0);
      CustWid:=INIFile.ReadInteger('Main','CustomWindowWidth',600);
      CustHei:=INIFile.ReadInteger('Main','CustomWindowHeight',400);

      if (CustWid<=0)or(CustHei<=0)or(CustLeft<0)or(CustTop<0) then
      begin
        Log('ERROR! Wrong coordinates for custom window');
        exit;
      end;

      WindowRect.Left:=CustLeft;
      WindowRect.Top:=CustTop;
      WindowRect.Right:=CustLeft+CustWid;
      WindowRect.Bottom:=CustTop+CustHei;
    end;
  finally
    INIFile.Free;
  end;

  {WindowRect.Left:=WindowRect.Left+10;
  WindowRect.Right:=WindowRect.Right-10;
  WindowRect.Top:=WindowRect.Top+10;
  WindowRect.Bottom:=WindowRect.Bottom-10; }
  //WindowRect.Right:=WindowRect.Right div 2;

  //WindowRect.Left:=WindowRect.Left+100;
  //WindowRect.Bottom:=WindowRect.Bottom+100;

  with wc do
  begin
    style:=CS_HREDRAW or CS_VREDRAW or CS_OWNDC;
    lpfnWndProc:=@WndProc;
    cbClsExtra:=0;
    cbWndExtra:=0;
    hInstance:=GetModuleHandle(nil);
    //hIcon:=LoadIcon(0,IDI_WINLOGO);
    hIcon:=0;
    //hCursor:=LoadCursor(0,IDC_ARROW);
    //hCursor:=LoadCursor(0,IDC_UPARROW);
    hCursor:=0;
    hbrBackground:=0;
    lpszMenuName:=nil;
    lpszClassName:='VideoOpenGl';
  end;

  if Windows.RegisterClass(wc)=0 then
  begin
    Log('ERROR! Failed To Register The Window Class, exiting');
    exit;
  end;

  dwExStyle:=WS_EX_TOOLWINDOW;   
  dwStyle:=WS_CLIPCHILDREN or WS_CLIPSIBLINGS or WS_POPUP or WS_VISIBLE;
  //dwStyle:=WS_CLIPCHILDREN or WS_CLIPSIBLINGS or WS_VISIBLE;

  AdjustWindowRectEx(WindowRect,dwStyle,false,dwExStyle);

  WndWidth:=WindowRect.Right-WindowRect.Left;
  WndHeight:=WindowRect.Bottom-WindowRect.Top;

  if ScreenCopyEnabled=true then
  begin
    RealWndWidth:=WndWidth*ScreenCopyWidthCount;
    RealWndHeight:=WndHeight*ScreenCopyHeightCount;
  end
  else
  begin
    RealWndWidth:=WndWidth;
    RealWndHeight:=WndHeight;
  end;

  H_wnd:=CreateWindowEx(dwExStyle,
                               'VideoOpenGl',
                               'Videowall client',
                               dwStyle,
                               WindowRect.Left,
                               WindowRect.Top,
                               RealWndWidth,
                               RealWndHeight,
                               0,
                               0,
                               hinstance,
                               nil);

  if h_Wnd=0 then
  begin
    KillGlWindow;
    MessageBox(0,'Window creation error.','Error',MB_OK or MB_ICONEXCLAMATION);
    exit;
  end;

  h_Dc:=GetDC(h_Wnd);
  if h_Dc=0 then
  begin
    KillGLWindow;
    Log('ERROR! Cant''t create a GL device context, exiting');
    exit;
  end;

  h_Rc:=CreateRenderingContext(h_Dc,[opDoubleBuffered],32,24,8,0,0,0);
  ActivateRenderingContext(h_Dc,h_Rc);

  ShowWindow(h_Wnd,SW_SHOW);
  SetForegroundWindow(h_Wnd);
  SetFocus(h_Wnd);
  SetCursorPos(WindowRect.Left,WndHeight);

  if Assigned(wglSwapIntervalEXT) then
  begin
    Log('Current swap interval='+inttostr(wglGetSwapIntervalEXT));
    str:=glGetString(GL_EXTENSIONS);
    Log('Extensions:'+str);
    str:=wglGetExtensionsStringARB(wglGetCurrentDC);
    Log('wglExtensions:'+str);
    Log('wglSwapIntervalEXT assigned, executing');
    Log('Settings UseVSync='+booltostr(UseVSync,true));
    if UseVSync=true then wglSwapIntervalEXT(1)
    else wglSwapIntervalEXT(0);
  end
  else Log('wglSwapIntervalEXT is not assigned');

  //настраиваем viewport
  glViewport(0, 0, WndWidth, WndHeight);
  //glViewport(0, 0, RealWndWidth, RealWndHeight);
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity;
  glOrtho(0, WndWidth, WndHeight, 0,-1,1);
  //glOrtho(0, RealWndWidth, RealWndHeight, 0,-1,1);
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity;

  glClearColor (0, 0, 0, 1);
  //glDepthFunc(GL_NEVER);
  glDisable(GL_DEPTH_TEST);
  glShadeModel(GL_SMOOTH);
  glEnable(GL_TEXTURE_2D);
  glBindTexture(GL_TEXTURE_2D,0);
  glBlendFunc(GL_SRC_ALPHA, GL_DST_ALPHA);
  glEnable(GL_BLEND);

  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);
  SwapBuffers(h_Dc);

  Result:=true;
end;

procedure DrawGLFillRect(R:TRect; Col:TColor; DisableBlend:boolean=false);
begin
  //выставляем цвет
  if DisableBlend then glDisable(GL_BLEND);
  glBindTexture(GL_TEXTURE_2D,0);
  glColor4f(GetRValue(Col)/255,GetGValue(Col)/255,GetBValue(Col)/255,1);
  glLoadIdentity;
  glBegin(GL_QUADS);
    glVertex2i(R.Left,R.Top);
    glVertex2i(R.Right,R.Top);
    glVertex2i(R.Right,R.Bottom);
    glVertex2i(R.Left,R.Bottom);
  glEnd;
  if DisableBlend then glEnable(GL_BLEND);
end;

procedure DrawHeaders;
var sec_i:integer;
r:TRect;
i,j,k,z,i1,k1,z1:integer;
height1,temp1:integer;
begin
  //сначала рисуем все прямоугольники
  glDisable(GL_BLEND);
  for sec_i:=0 to length(Sections)-1 do
  begin
    if SectionSwapEnabled then
      if sec_i<>CurrentSection then continue;

    //окрашиваем главный заголовок
    DrawGLFillRect(Sections[sec_i].HeaderMainRect,Sections[sec_i].MainBGColor);
    //закраштваем второй заголовок
    DrawGLFillRect(Sections[sec_i].HeaderCaptionRect,Sections[sec_i].HeaderBGColor);

    if Sections[sec_i].TimeEnabled then
    begin
      //выводим время
      DrawGLFillRect(Sections[sec_i].TimeRect,Sections[sec_i].DateTimeBGColor);
    end;

    if Sections[sec_i].DateEnabled then
    begin
      //выводим дату
      DrawGLFillRect(Sections[sec_i].DateRect,Sections[sec_i].DateTimeBGColor);
    end;
  end;
  glEnable(GL_BLEND);

  //идём по всем секциям
  for sec_i:=0 to length(Sections)-1 do
  begin    
    if SectionSwapEnabled then
      if sec_i<>CurrentSection then continue;

    height1:=Sections[sec_i].HeaderMainRect.Bottom-Sections[sec_i].HeaderMainRect.Top-Sections[sec_i].HeaderIndent*2;
    temp1:=height1;

    //выводим лого
    if Sections[sec_i].LogoEnabled then Sections[sec_i].LogoImageObj.Draw(Sections[sec_i].Area.Left+Sections[sec_i].HeaderIndent,Sections[sec_i].Area.Top+Sections[sec_i].HeaderIndent,height1,height1)
    else temp1:=0;
    //выводим главный заголовок
    r:=Rect(Sections[sec_i].Area.Left+temp1+Sections[sec_i].HeaderIndent*2,Sections[sec_i].Area.Top+Sections[sec_i].HeaderIndent,Sections[sec_i].Area.Right,Sections[sec_i].Area.Top+height1+Sections[sec_i].HeaderIndent*2);

    i:=Sections[sec_i].CaptionFontObj.DrawTextFunc(r,0,0,Sections[sec_i].Caption);
    r:=Rect(Sections[sec_i].Area.Left+temp1+Sections[sec_i].HeaderIndent*2,Sections[sec_i].Area.Top+Sections[sec_i].HeaderIndent+i,Sections[sec_i].Area.Right,Sections[sec_i].Area.Top+height1+Sections[sec_i].HeaderIndent*2);

    Sections[sec_i].CaptionEngFontObj.DrawText(r.Left,r.Top,Sections[sec_i].CaptionEng);


    //изменяем поле для вывода информации
    Sections[sec_i].DataRowsRect:=Rect(Sections[sec_i].Area.Left,Sections[sec_i].HeaderCaptionRect.Bottom,Sections[sec_i].Area.Right,Sections[sec_i].Area.Bottom);
    //выводим тексты заголовка
    for i:=0 to length(Sections[sec_i].Columns)-1 do
    begin
      //пропускаем специальные заголовки на всю ширину
      if (Sections[sec_i].Columns[i].Field=Sections[sec_i].AllRowsField)and(Sections[sec_i].AllRowsField<>'') then
      begin
      end
      else
      begin
        r:=Rect(Sections[sec_i].Columns[i].CalculatedRect.Left,Sections[sec_i].HeaderCaptionRect.Top,Sections[sec_i].Columns[i].CalculatedRect.Right,Sections[sec_i].HeaderCaptionRect.Bottom);
        Sections[sec_i].Columns[i].CaptionTextFontObj.CalcTextDimensions(Sections[sec_i].Columns[i].CaptionText,r,k,z,Sections[i].WordWrap);
        Sections[sec_i].Columns[i].CaptionTextEngFontObj.CalcTextDimensions(Sections[sec_i].Columns[i].CaptionTextEng,r,k1,z1,Sections[i].WordWrap);
        k:=r.Bottom-r.Top;
        k:=(k-(z+z1))div 2;

        r:=Rect(Sections[sec_i].Columns[i].CalculatedRect.Left,Sections[sec_i].HeaderCaptionRect.Top+k,Sections[sec_i].Columns[i].CalculatedRect.Right,Sections[sec_i].HeaderCaptionRect.Top+k+z);
        //z:=DrawText(form1.Image1.Canvas.Handle,PChar(Sections[sec_i].Columns[i].CaptionText),-1,r,j);
        z:=Sections[sec_i].Columns[i].CaptionTextFontObj.DrawTextFunc(r,Sections[sec_i].Columns[i].CaptionText,Sections[sec_i].Columns[i].Align,Sections[sec_i].WordWrap);
        r.Top:=r.Top+z;
        r.Bottom:=r.Bottom+z;
        Sections[sec_i].Columns[i].CaptionTextEngFontObj.DrawTextFunc(r,Sections[sec_i].Columns[i].CaptionTextEng,Sections[sec_i].Columns[i].Align,Sections[sec_i].WordWrap);
      end;
    end;

    if Sections[sec_i].TimeEnabled then
    begin
      i:=Sections[sec_i].DateTimeNumbersFontObj.DrawTextFunc(Sections[sec_i].TimeRect,0,0,Sections[sec_i].TimeString,taCenter);

      //выводим текст времени
      Sections[sec_i].DateTimeFontObj.CalcTextDimensions(Sections[sec_i].TimeText,OverallScreenRect,i,j);
      k:=j;
      i1:=i;
      Sections[sec_i].DateTimeEngFontObj.CalcTextDimensions(Sections[sec_i].TimeTextEng,OverallScreenRect,i,j);
      k:=k+j;
      if i1<i then i1:=i;
      z:=(Sections[sec_i].HeaderMainRect.Bottom-Sections[sec_i].HeaderMainRect.Top) div 2;
      r:=Rect(Sections[sec_i].TimeRect.Left-DateTimeRecsDelta-i1,Sections[sec_i].Area.Top+z-(k div 2),Sections[sec_i].TimeRect.Left-DateTimeRecsDelta,Sections[sec_i].Area.Top+z+(k div 2));

      i1:=Sections[sec_i].DateTimeFontObj.DrawTextFunc(r,0,0,Sections[sec_i].TimeText);
      r.Top:=r.Top+i1;

      Sections[sec_i].DateTimeEngFontObj.DrawTextFunc(r,0,0,Sections[sec_i].TimeTextEng);
    end;

    if Sections[sec_i].DateEnabled then
    begin
      i:=Sections[sec_i].DateTimeNumbersFontObj.DrawTextFunc(Sections[sec_i].DateRect,0,0,Sections[sec_i].DateString,taCenter);

      //выводим текст даты
      Sections[sec_i].DateTimeFontObj.CalcTextDimensions(Sections[sec_i].DateText,OverallScreenRect,i,j);
      k:=j;
      i1:=i;

      Sections[sec_i].DateTimeEngFontObj.CalcTextDimensions(Sections[sec_i].DateTextEng,OverallScreenRect,i,j);
      k:=k+j;
      if i1<i then i1:=i;
      z:=(Sections[sec_i].HeaderMainRect.Bottom-Sections[sec_i].HeaderMainRect.Top) div 2;
      r:=Rect(Sections[sec_i].DateRect.Left-DateTimeRecsDelta-i1,Sections[sec_i].Area.Top+z-(k div 2),Sections[sec_i].DateRect.Left-DateTimeRecsDelta,Sections[sec_i].Area.Top+z+(k div 2));

      i1:=Sections[sec_i].DateTimeFontObj.DrawTextFunc(r,0,0,Sections[sec_i].DateText);
      r.Top:=r.Top+i1;

      Sections[sec_i].DateTimeEngFontObj.DrawTextFunc(r,0,0,Sections[sec_i].DateTextEng);
    end;
  end;
end;

procedure DrawData(elapsed:double);
var i,j,i_max,k,z,z1,SQLUpdateSection:integer;
h_max,h_cur,h_spec,h_separator:integer;
r:TRect;
elapsedTextOffset,offsetTemp:double;
begin
  elapsedTextOffset:=elapsed*RunningSpeed;

  for SQLUpdateSection:=0 to length(Sections)-1 do
  begin   
    //вычисляем максимальный индекс данных
    if length(Sections[SQLUpdateSection].Columns)=0 then exit;
    i_max:=length(Sections[SQLUpdateSection].Columns[0].Data);

    //пропускаем неотрисовываемые секции
    if SectionSwapEnabled then
      if SQLUpdateSection<>CurrentSection then continue;

    //делаем тукущую координату по высоте
    h_cur:=Sections[SQLUpdateSection].DataRowsRect.Top;

    //считаем разделитель
    if Sections[SQLUpdateSection].LineSeparatorEnabled=true then h_separator:=Sections[SQLUpdateSection].LineSeparatorHeight
    else h_separator:=0;

    //идём по строкам
    for i:=0 to i_max-1 do
    begin
      //вычисляем максимальную высоту в столбце
      h_max:=0;
      h_spec:=0;
      for j:=0 to length(Sections[SQLUpdateSection].Columns)-1 do
      begin
        r:=Rect(Sections[SQLUpdateSection].Columns[j].CalculatedRect.Left,h_cur,Sections[SQLUpdateSection].Columns[j].CalculatedRect.Right,h_cur);

        //если это специальный столбец на всю ширину, то другое условие
        if (Sections[SQLUpdateSection].Columns[j].Field=Sections[SQLUpdateSection].AllRowsField)and(Sections[SQLUpdateSection].AllRowsField<>'') then
        begin
          if (Sections[SQLUpdateSection].AllRowsFieldOptionalRunning=1) then
          begin
            Sections[SQLUpdateSection].Columns[j].DataFontObj.CalcTextDimensions(Sections[SQLUpdateSection].Columns[j].Data[i],r,k,z,false);
            if k>(r.Right-r.Left) then
            begin
              Sections[SQLUpdateSection].Columns[j].DataRunning[i].TextRunning:=true;
              Sections[SQLUpdateSection].Columns[j].DataRunning[i].TextPixelWidth:=k;
            end
            else Sections[SQLUpdateSection].Columns[j].DataRunning[i].TextRunning:=false;
          end
          else
            Sections[SQLUpdateSection].Columns[j].DataFontObj.CalcTextDimensions(Sections[SQLUpdateSection].Columns[j].Data[i],r,k,z,Sections[SQLUpdateSection].WordWrap);

          h_spec:=z
        end
        else
        begin
          Sections[SQLUpdateSection].Columns[j].DataFontObj.CalcTextDimensions(Sections[SQLUpdateSection].Columns[j].Data[i],r,k,z,Sections[SQLUpdateSection].WordWrap);

          if h_max<z then h_max:=z;
        end;
      end;  
      //окрашиваем столбец
      if Sections[SQLUpdateSection].TextBGBeginOdd then
      begin  //начинаем с нечётного
        if ((i+1) mod 2)=1 then k:=Sections[SQLUpdateSection].TextAltBGColor
        else k:=Sections[SQLUpdateSection].TextBGColor;
      end
      else
      begin  //начинаем с чётного
        if ((i+1) mod 2)=1 then k:=Sections[SQLUpdateSection].TextBGColor
        else k:=Sections[SQLUpdateSection].TextAltBGColor;
      end;
      if (h_cur+h_max+h_spec)>Sections[SQLUpdateSection].DataRowsRect.Bottom then
      begin  //если не помещается, то надо окрасить в предыдущий цвет и выйти
        r:=Rect(Sections[SQLUpdateSection].DataRowsRect.Left,h_cur,Sections[SQLUpdateSection].DataRowsRect.Right,Sections[SQLUpdateSection].DataRowsRect.Bottom);
        j:=i-1;
        if j<0 then j:=0;
        if Sections[SQLUpdateSection].TextBGBeginOdd then
        begin  //начинаем с нечётного
          if ((j+1) mod 2)=1 then k:=Sections[SQLUpdateSection].TextAltBGColor
          else k:=Sections[SQLUpdateSection].TextBGColor;
        end
        else
        begin  //начинаем с чётного
          if ((j+1) mod 2)=1 then k:=Sections[SQLUpdateSection].TextBGColor
          else k:=Sections[SQLUpdateSection].TextAltBGColor;
        end;
        DrawGLFillRect(r,k);
        break;
      end
      else if i<>0 then //выводим разделитель для предыдущей строки
      begin
        r:=Rect(Sections[SQLUpdateSection].DataRowsRect.Left,h_cur,Sections[SQLUpdateSection].DataRowsRect.Right,h_cur+h_separator);
        j:=Sections[SQLUpdateSection].LineSeparatorColor;
        DrawGLFillRect(r,j);
        h_cur:=h_cur+h_separator;
      end;
      r:=Rect(Sections[SQLUpdateSection].DataRowsRect.Left,h_cur,Sections[SQLUpdateSection].DataRowsRect.Right,h_cur+h_max+h_spec);

      DrawGLFillRect(r,k);
      h_cur:=h_cur+h_max;
      //выводим текст
      if Sections[SQLUpdateSection].UseAlpha then
      begin
        glDisable(GL_BLEND);
        glEnable(GL_ALPHA_TEST);
        glAlphaFunc(GL_GREATER,Sections[SQLUpdateSection].AlphaTruncate);
      end;
      for j:=0 to length(Sections[SQLUpdateSection].Columns)-1 do
      begin
        //если это специальный столбец на всю ширину, то другой вывод
        if (Sections[SQLUpdateSection].Columns[j].Field=Sections[SQLUpdateSection].AllRowsField)and(Sections[SQLUpdateSection].AllRowsField<>'') then
        begin
          if (Sections[SQLUpdateSection].LineSeparatorAllRowsFieldEnabled=true)and(Sections[SQLUpdateSection].Columns[j].Data[i]<>'') then
          begin
            h_spec:=h_spec+h_separator;
            r:=Rect(Sections[SQLUpdateSection].DataRowsRect.Left,h_cur,Sections[SQLUpdateSection].DataRowsRect.Right,h_cur+h_separator);
            z1:=Sections[SQLUpdateSection].LineSeparatorColor;
            DrawGLFillRect(r,z1);
          end;

          r:=Rect(Sections[SQLUpdateSection].Columns[j].CalculatedRect.Left,h_cur+h_separator,Sections[SQLUpdateSection].Columns[j].CalculatedRect.Right,h_cur+h_spec);
          if (Sections[SQLUpdateSection].AllRowsFieldOptionalRunning=1) then
          begin
            if Sections[SQLUpdateSection].Columns[j].DataRunning[i].TextRunning=true then
            begin
              offsetTemp:=Sections[SQLUpdateSection].Columns[j].DataRunning[i].TextOffset-elapsedTextOffset;
              if (offsetTemp < -Sections[SQLUpdateSection].Columns[j].DataRunning[i].TextPixelWidth) then
                Sections[SQLUpdateSection].Columns[j].DataRunning[i].TextOffset:=Sections[SQLUpdateSection].Columns[j].CalculatedRect.Right
              else Sections[SQLUpdateSection].Columns[j].DataRunning[i].TextOffset:=offsetTemp;
              Sections[SQLUpdateSection].Columns[j].DataFontObj.DrawTextFunc(r,Sections[SQLUpdateSection].Columns[j].Data[i],taRunning,false,Sections[SQLUpdateSection].Columns[j].DataRunning[i].TextOffset);
            end
            else
              Sections[SQLUpdateSection].Columns[j].DataFontObj.DrawTextFunc(r,Sections[SQLUpdateSection].Columns[j].Data[i],Sections[SQLUpdateSection].Columns[j].Align,false);
          end
          else
            Sections[SQLUpdateSection].Columns[j].DataFontObj.DrawTextFunc(r,Sections[SQLUpdateSection].Columns[j].Data[i],Sections[SQLUpdateSection].Columns[j].Align,Sections[SQLUpdateSection].WordWrap);
          //DrawGLFillRect(r,Sections[SQLUpdateSection].Columns[j].DataFontObj.FontColor);
        end
        else
        begin
          r:=Rect(Sections[SQLUpdateSection].Columns[j].CalculatedRect.Left,h_cur-h_max,Sections[SQLUpdateSection].Columns[j].CalculatedRect.Right,h_cur);
          //if Sections[SQLUpdateSection].Columns[j].Field='time_otpr' then
          Sections[SQLUpdateSection].Columns[j].DataFontObj.DrawTextFunc(r,Sections[SQLUpdateSection].Columns[j].Data[i],Sections[SQLUpdateSection].Columns[j].Align,Sections[SQLUpdateSection].WordWrap);
        end;
      end;
      h_cur:=h_cur+h_spec;
      if Sections[SQLUpdateSection].UseAlpha then
      begin
        glDisable(GL_ALPHA_TEST);
        glEnable(GL_BLEND);
      end;
    end;
  end;
end;

procedure UpdateSQLData;
var wait_return:cardinal;
i,j,k,z:integer;
begin
  //проверяем, просигнализирован ли эвент
  wait_return:=WaitForSingleObject(SQLDataThread.NewDataReadyEvent,0);
  if wait_return<>WAIT_OBJECT_0 then exit;

  //Log('Signaled, try to enter');

  if TryEnterCriticalSection(SQLDataThread.DataAccessCritSection) then
  begin
    Log('Critical section enter sucsessfuly, start to transfer data');
    //переносим данные
    for i:=0 to length(Sections)-1 do
      for j:=0 to length(Sections[i].Columns)-1 do
      begin
        k:=-1;
        for z:=0 to length(SQLDataThread.FSectionsTempData[i].Columns)-1 do
          if SQLDataThread.FSectionsTempData[i].Columns[z].field=Sections[i].Columns[j].Field then
          begin
            k:=z;
            break;
          end;
        if k=-1 then
        begin
          Log('ERROR! Unable to locate field column for field='+Sections[i].Columns[j].Field);
          LeaveCriticalSection(SQLDataThread.DataAccessCritSection);
          exit;
        end;
        //переносим данные
        setlength(Sections[i].Columns[j].Data,length(SQLDataThread.FSectionsTempData[i].Columns[k].FieldData));
        setlength(Sections[i].Columns[j].DataRunning,length(SQLDataThread.FSectionsTempData[i].Columns[k].FieldData));
        for z:=0 to length(Sections[i].Columns[j].Data)-1 do
          Sections[i].Columns[j].Data[z]:=SQLDataThread.FSectionsTempData[i].Columns[k].FieldData[z];
      end;

    Log('Data transfer complete sucsessfully');

    //убираем эвент
    ResetEvent(SQLDataThread.NewDataReadyEvent);

    LeaveCriticalSection(SQLDataThread.DataAccessCritSection);
  end;
end;

procedure DrawGLCopies;
var x,y,wid,hei,i,j:integer;
begin
  glViewport(0, 0, WndWidth, WndHeight);
  glLoadIdentity;

  wid:=OverallScreenRectForCopy.Right-OverallScreenRectForCopy.Left;
  hei:=OverallScreenRectForCopy.Bottom-OverallScreenRectForCopy.Top;
  CopyScreenToTexture(OverallScreenRectForCopy.Left, OverallScreenRectForCopy.Top, wid, hei, ScreenCopyImageObj.Texture);

  for i:=0 to ScreenCopyWidthCount-1 do
    for j:=0 to ScreenCopyHeightCount-1 do
    begin
      if (i=0)and(j=0) then continue;

      x:=wid*i;
      y:=hei*j;

      glViewport(x, y, wid, hei);
      glLoadIdentity;

      //ScreenCopyImageObj.Draw(x,y,wid,hei);
      ScreenCopyImageObj.Draw(0,0,wid,hei);
    end;

  glViewport(0, 0, WndWidth, WndHeight);
  glLoadIdentity;
end;

procedure DrawGLFallback;
begin
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);

  glLoadIdentity;
  FallBackImageObj.Draw(0,0,WndWidth,WndHeight);

  //glFlush;
  glFinish;
end;

procedure DrawGLLogo;
begin
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);

  glLoadIdentity;
  Sections[CurrentSection].LogoImageObj.Draw(0,0,WndWidth,WndHeight);

  glFinish;
end;

procedure DrawGLNormal(elapsed:double);
begin
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);

  //DrawGLFillRect(Sections[0].HeaderMainRect,Sections[0].MainBGColor);

  DrawHeaders;
  DrawData(elapsed);
  if RunningEnabled then DrawGLRunning;

  //glFlush;
  glFinish;
end;

procedure DrawGL(elapsed:double);
var b:boolean;
i,j:integer;
begin
  b:=false;

  for i:=0 to length(Sections)-1 do
    for j:=0 to length(Sections[i].Columns)-1 do
      if length(Sections[i].Columns[j].Data)=0 then
      begin
        b:=true;
        break;
      end;

  if (b=true)and(FallBackEnabled=true) then DrawGLFallback
  else
  begin
    if Sections[CurrentSection].DisplayOnlyLogo=true then
      DrawGLLogo
    else
      DrawGLNormal(elapsed);
  end;

  if ScreenCopyEnabled=true then
    DrawGLCopies;
end;

function WinMain(hInstance: HINST; hPrevInstance: HINST; lpCmdLine: PChar; nCmdShow: integer):integer; stdcall;
var ModuleName:string;
msg:TMsg;
done:bool;
Time1,Time2,TimeInterval:int64;
Time1Running,Time2Running:int64;
TimeElapsed:double;
SecSwapTime1,SecSwapTime2,SecSwapTimeInterval:int64;
TimeFPS1,TimeFPS2,FPSCounter:int64;
SleepInterval:integer;
tempExt:Extended;
oglSync:GLsync;
SyncRet:GLenum;
useSync:boolean;
FPSArr:array[0..1] of array[0..3] of extended;
FPSArrInd:integer;
counter:integer;
begin
  done:=false;
  WindowActive:=false;
  TimerHNDL:=0;
  SQLDataThread:=nil;
  ModuleName:=GetModuleFileNameStr(0);
  //меняем текущую папку
  SetCurrentDirectory(PChar(ExtractFilePath(ModuleName)));
  //делаем имя для лог файла
  LogFileName:=ChangeFileExt(ModuleName, '.log');
  //стираем файл логов если он есть
  if FileExists(LogFileName) then DeleteFile(LogFileName);
  Log('===Starting program===');
  //делаем имя для файла настроек
  INIFileName:=ChangeFileExt(ModuleName, '.ini');

  //создаём окно
  if CreateGLWindow=false then
  begin
    Log('ERROR! Window creation failed, exiting');
    result:=0;
    exit;
  end;

  //инициализация
  if Initialize=false then
  begin
    Log('ERROR! Initialize function returned false, exiting');
    KillGLwindow;
    result:=0;
    exit;
  end;

  //выводим fallback изображение
  DrawGLFallback;
  SwapBuffers(h_Dc);

  //формируем шрифты
  if InitializeFontsAndImages=false then
  begin
    Log('ERROR! InitializeFonts function returned false, exiting');
    KillGLwindow;
    result:=0;
    exit;
  end;

  //вычисляем области
  if InitializeRecs=false then
  begin
    Log('ERROR! InitializeRecs function returned false, exiting');
    KillGLwindow;
    result:=0;
    exit;
  end;

  //задаём таймер для изменения даты и времени
  TimerHNDL:=SetTimer(H_wnd,Timer1ID,150,nil);
  if TimerHNDL=0 then
  begin
    Log('ERROR! Timer initialization returned 0, exiting');
    KillGLwindow;
    result:=0;
    exit;
  end;

  //создаём отдельный поток для загрузки данных из SQL
  try
    Log('Trying to create SQL data thread');
    SQLDataThread:=TDataThread.Create(@Sections,SQLHost,SQLDatabase,SQLLogin,SQLPass,ChangeFileExt(ModuleName, '.log2'),LogEnabled,SQLUpdateInterval);
    SQLDataThread.FreeOnTerminate:=false;
    SQLDataThread.Resume;
  except
    on e:exception do
    begin
      Log('ERROR! Exception on creating SQLDataThread, exiting. Message='+e.Message);
      KillGLwindow;
      result:=0;
      exit;
    end;
  end;
  Log('SQL data thread create complete');

  //расчитываем задержки исходя из нужного FPS
  if (QueryPerformanceFrequency(TimeFreq)=false)or
  (QueryPerformanceCounter(Time1)=false) then
  begin
    Log('ERROR! Time functions returned false, exiting');
    KillGLwindow;
    result:=0;
    exit;
  end;
  if TargetFPS>120 then TargetFPS:=120;
  if TargetFPS<1 then TargetFPS:=1;
  Log('TargetFPS='+inttostr(TargetFPS));
  //TimeInterval:=round((1/TargetFPS)*TimeFreq);  //кол-во тиков на каждый кадр
  //Log('Target tick count='+inttostr(TimeInterval));
  TimeInterval:=60*TimeFreq;  //кол-во тиков на 60 секунд (вывод окна на передний план)
  Log('Time interval for 60 seconds='+inttostr(TimeInterval));
  SecSwapTimeInterval:=(SectionSwapInterval div 1000)*TimeFreq;
  Log('Time interval for '+inttostr(SectionSwapInterval)+' miliseconds for section swap='+inttostr(SecSwapTimeInterval));
  Log('Tick frequency='+inttostr(TimeFreq));

  //расчитываем сколько нужно спать, для экономии времени процесора
  SleepInterval:=round((1000/TargetFPS)/4);
  if SleepInterval<2 then SleepInterval:=2;
  Log('Sleep interval='+inttostr(SleepInterval));

  if Assigned(glFenceSync)and
  Assigned(glClientWaitSync)and
  Assigned(glDeleteSync) then
  begin
  QueryPerformanceCounter(Time1);
  TimeFPS1:=Time1;
  RunningTimestamp:=Time1;
  FPSCounter:=0;
  useSync:=true;
  //useSync:=false;
  FPSArrInd:=0;
  ShowCursor(false);

  //проверка работоспособности Sync
  while not done do
  begin
    if (PeekMessage(msg, 0, 0, 0, PM_REMOVE)) then
    begin
      if msg.message=WM_QUIT then
      begin
        KillGLwindow;
        //done:=true
        exit;
      end
      else
      begin
        TranslateMessage(msg);
        DispatchMessage(msg);
      end;
    end
    else
    begin
      //рисование
      DrawGLFallback;
      if ScreenCopyEnabled then DrawGLCopies;
      SwapBuffers(h_Dc);

      //синхронизация с GPU
      if useSync then
      begin
        oglSync:=nil;
        oglSync:=glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE,0);
        if oglSync=nil then
        begin
          Log('Synch object is nil');
          exit;
        end;

        repeat
          sleep(2);
          SyncRet:=glClientWaitSync(oglSync,GL_SYNC_FLUSH_COMMANDS_BIT,0);  //не ждём, функция возвращается сразу и даёт нам информацию по состоянию объекта
        until SyncRet<>GL_TIMEOUT_EXPIRED;
        glDeleteSync(oglSync);
      end;

      //вычисление FPS
      QueryPerformanceCounter(TimeFPS2);
      inc(FPSCounter);
      tempExt:=(TimeFPS2-TimeFPS1)/TimeFreq;
      if tempExt>1 then
      begin
        tempExt:=FPSCounter/tempExt;
        //Log('Current test without sync fps='+floattostrf(tempExt,ffFixed,15,15));
        //заносим в массив
        if useSync then FPSArr[0][FPSArrInd]:=tempExt
        else FPSArr[1][FPSArrInd]:=tempExt;
        inc(FPSArrInd);
        if FPSArrInd>length(FPSArr[0]) then
        begin
          if not(useSync) then done:=true
          else
          begin
            useSync:=not(useSync);
            FPSArrInd:=0;
          end;
        end;
        TimeFPS1:=TimeFPS2;
        FPSCounter:=0;
      end;
      if not(UseSync) then sleep(SleepInterval);
    end;
  end;

  //вывод результата
  Log('Sync test complete');
  Log('With sync FPS=');
  tempExt:=FPSArr[0][1];
  for FPSArrInd:=0 to length(FPSArr[0])-1 do
  begin
    Log('#'+inttostr(FPSArrInd)+'='+floattostrf(FPSArr[0][FPSArrInd],ffFixed,15,15));
    if FPSArrInd>1 then tempExt:=(tempExt+FPSArr[0][FPSArrInd])/2;
  end;
  FPSArr[0][0]:=tempExt;
  Log('With sync avg='+floattostrf(FPSArr[0][0],ffFixed,15,15));
  Log('Without sync FPS=');
  tempExt:=FPSArr[1][1];
  for FPSArrInd:=0 to length(FPSArr[0])-1 do
  begin
    Log('#'+inttostr(FPSArrInd)+'='+floattostrf(FPSArr[1][FPSArrInd],ffFixed,15,15));
    if FPSArrInd>1 then tempExt:=(tempExt+FPSArr[1][FPSArrInd])/2;
  end;
  FPSArr[1][0]:=tempExt;
  Log('Without sync avg='+floattostrf(FPSArr[1][0],ffFixed,15,15));

  //если оба фпс в пределах 2 от нужного, то прироритет с синхронизацией
  if (abs(TargetFPS-FPSArr[0][0])<2)and(abs(TargetFPS-FPSArr[1][0])<2) then FPSArr[0][0]:=TargetFPS;
  //проверяем, у какого способа лучше фпс
  if abs(TargetFPS-FPSArr[1][0])<abs(TargetFPS-FPSArr[0][0]) then useSync:=false
  else useSync:=true;  

  end   //if Assigned(glFenceSync)andAssigned(glClientWaitSync)andAssigned(glDeleteSync) then
  else
  begin   //если нет функций синхронизации, то не используем их
    useSync:=false;
    Log('Sync functions not found, not using sync objects');
  end;
  
  Log('Sync='+booltostr(useSync,true));
  QueryPerformanceCounter(Time1);
  TimeFPS1:=Time1;
  RunningTimestamp:=Time1;
  SecSwapTime1:=Time1;
  Time1Running:=Time1;
  Time2Running:=Time1;
  FPSCounter:=0;
  FPSArrInd:=0;
  done:=false;
  //основной цикл программы
  while not done do
  begin
    if (PeekMessage(msg, 0, 0, 0, PM_REMOVE)) then
    begin
      if msg.message=WM_QUIT then
      begin
        //done:=true
        KillGLwindow;
        exit;
      end
      else
      begin
        TranslateMessage(msg);
        DispatchMessage(msg);
      end;
    end
    else
    begin
      QueryPerformanceCounter(Time2Running);
      TimeElapsed:=(Time2Running-Time1Running)/TimeFreq;
      Time1Running:=Time2Running;

      //вычисление бегущей строки
      if RunningEnabled then CalculateGLRunning;

      //смотрим обновление данных
      UpdateSQLData;

      //рисование
      DrawGL(TimeElapsed);
      SwapBuffers(h_Dc);

      //синхронизация с GPU
      if (useSync=true)and(UseVSync=true) then
      begin
        oglSync:=nil;
        oglSync:=glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE,0);
        if oglSync=nil then
        begin
          Log('Synch object is nil');
          break;
        end;
        counter:=0;
        repeat
          inc(counter);
          sleep(1);
          SyncRet:=glClientWaitSync(oglSync,GL_SYNC_FLUSH_COMMANDS_BIT,0);  //не ждём, функция возвращается сразу и даёт нам информацию по состоянию объекта
        until SyncRet<>GL_TIMEOUT_EXPIRED;
        glDeleteSync(oglSync);
      end;

      //вычисление FPS
      QueryPerformanceCounter(TimeFPS2);
      Time2:=TimeFPS2;
      SecSwapTime2:=TimeFPS2;
      inc(FPSCounter);
      tempExt:=(TimeFPS2-TimeFPS1)/TimeFreq;
      if tempExt>1 then
      begin
        Log('Current fps='+floattostrf(FPSCounter/tempExt,ffFixed,15,15));
        //Log('Time1='+inttostr(Time1));
        //Log('Time2='+inttostr(Time2));
        //Log('Counter='+inttostr(counter));
        TimeFPS1:=TimeFPS2;
        FPSCounter:=0;
      end;

      if not(UseSync) then
        if UseVSync=true then sleep(SleepInterval);

      if (Time1+TimeInterval)<Time2 then
      begin  //выводим окно на передний план
        Log('Topmost activated');
        //SetWindowPos(h_Wnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE);
        //SetForegroundWindow(h_Wnd);
        //SetFocus(h_Wnd);
        SetWindowPos(h_Wnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_SHOWWINDOW or SWP_NOMOVE or SWP_NOSIZE);
        SetForegroundWindow(h_Wnd);
        SetActiveWindow(h_Wnd);
        RedrawWindow(h_Wnd,nil,0,RDW_FRAME or RDW_INVALIDATE or RDW_ALLCHILDREN);
        Time1:=Time2;
      end;

      //смена секции
      if (SecSwapTime1+SecSwapTimeInterval)<SecSwapTime2 then
      begin
        Log('Section swap activated');
        if SectionSwapEnabled then
        begin
          inc(CurrentSection);
          if CurrentSection>(length(sections)-1) then CurrentSection:=0;
        end;
        SecSwapTime1:=SecSwapTime2;
      end;
    end;
  end;
  KillGLwindow;
  result:=msg.wParam;
end;

end.
