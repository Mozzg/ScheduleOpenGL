unit fontsUnit;

interface

uses dglOpengl, Windows, Classes;

type
  TColor = -$7FFFFFFF-1..$7FFFFFFF;

  TAlignment = (taLeftJustify, taRightJustify, taCenter, taRunning);

  TCharRec=record
    Width:integer;
    Height:integer;
    TextureWidth:integer;
    TextureHeight:integer;
    VertexRect:TRect;
  end;

  TFontObj=class(TObject)
  private
    FFontName:string;
    FFontSize:integer;
    FFontColor:TColor;
    FFontColorRGB:TRGBTriple;
    FFontTexture:GLuint;
    FFontListBase:GLuint;
    FCharCellSize:integer;
    FExtraWidth:integer;
    FMaxHeight:integer;
    FCharArr:array[0..255] of TCharRec;

    FListGenerated:boolean;

    procedure InitTexture_Base_Metrics;
    procedure InitBase_Metrics;

    procedure SetColor(Col:TColor);
  public
    constructor Create(FontName:string; FontSize:integer; FontCol:TColor; Texture:GLuint=0);
    destructor Destroy; override;

    procedure DrawText(X,Y:integer; text:string); overload;
    procedure DrawText(X,Y:double; text:string); overload;
    function DrawTextFunc(R:TRect; Text:string; Align:TAlignment=taLeftJustify; WordWrap:boolean=false; Offset:double=0):integer; overload;
    function DrawTextFunc(R:TRect; X,Y:integer; Text:string; Align:TAlignment=taLeftJustify):integer; overload;
    function TextWidth(text:string):integer;
    function TextHeight(text:string):integer;
    //function TextDimensions(text:string; max_width:integer; out Width:integer):integer;
    procedure CalcTextDimensions(text:string; Rect:TRect; out Width:integer; out Height:integer; WordWrap:boolean=false);

    property FontName:string read FFontName;
    property FontSize:integer read FFontSize;
    property FontColor:TColor read FFontColor write SetColor;
    property Texture:GLuint read FFontTexture;
  end;

  TImageObj=class(TObject)
  private
    FFileName:string;
    FTransparent:boolean;
    FImageTexture:GLuint;
    FImageWidth:integer;
    FImageHeight:integer;

    procedure InitTexture;
  public
    constructor Create(FileName:string; Transparent:boolean); overload;
    constructor Create(Width, Height: integer; Transparent:boolean); overload;
    destructor Destroy; override;

    procedure Draw(X,Y:integer; Width,Height:integer);

    property Texture:GLuint read FImageTexture;
    property Width: integer read FImageWidth;
    property Height: integer read FImageHeight;
  end;

  TTexFontElement=record
    FontName:string;
    FontSize:integer;
    FontObj:TFontObj;
  end;

  TTexImageElement=record
    ImageName:string;
    ImageTransparent:boolean;
    ImageObj:TImageObj;
  end;

var
  FontsElementsArr:array of TTexFontElement;
  ImageElementsArr:array of TTexImageElement;

function FindOrCreateImageObj(FileName:string; Transparent:boolean):TImageObj;
function CreateEmptyImageObj(Width, Height: integer; Transparent:boolean):TImageObj;
function FindOrCreateFontObj(FontName:string; FontSize:integer; FontCol:TColor):TFontObj;

implementation

uses SysUtils, TexturesTest, Graphics, mainUnit;

function Ceil(const X: Extended): Integer;
begin
  Result := Integer(Trunc(X));
  if Frac(X) > 0 then
    Inc(Result);
end;

procedure FinalizationProc;
var i:integer;
begin
  for i:=0 to length(FontsElementsArr)-1 do
    FontsElementsArr[i].FontObj.Free;
  for i:=0 to length(ImageElementsArr)-1 do
    ImageElementsArr[i].ImageObj.Free;
end;

function FindOrCreateImageObj(FileName:string; Transparent:boolean):TImageObj;
var i:integer;
begin
  result:=nil;
  Log('Entered FindOrCreateImageObj with FileName='+FileName+', Transparent='+booltostr(Transparent,true));
  //ищем, есть ли така€ текстура уже создана€
  for i:=0 to length(ImageElementsArr)-1 do
    if (FileName=ImageElementsArr[i].ImageName)and
    (Transparent=ImageElementsArr[i].ImageTransparent) then
    begin
      result:=ImageElementsArr[i].ImageObj;
      Log('Exiting FindOrCreateImageObj, found same image with index='+inttostr(i));
      exit;
    end;

  //если мы дошли сюда, значит текстура ещЄ не создана, создаЄм
  i:=length(ImageElementsArr);
  setlength(ImageElementsArr,i+1);
  ImageElementsArr[i].ImageName:=FileName;
  ImageElementsArr[i].ImageTransparent:=Transparent;
  ImageElementsArr[i].ImageObj:=TImageObj.Create(FileName,Transparent);
  result:=ImageElementsArr[i].ImageObj;
  Log('Exiting FindOrCreateImageObj, created new image object with index='+inttostr(i));
end;

function CreateEmptyImageObj(Width, Height: integer; Transparent:boolean):TImageObj;
var i: integer;
begin
  result:=nil;
  Log('Entered CreateEmptyImageObj with Width and Height='+inttostr(Width)+', '+inttostr(Height)+', Transparent='+booltostr(Transparent,true));
  i:=length(ImageElementsArr);
  setlength(ImageElementsArr,i+1);
  ImageElementsArr[i].ImageName:='';
  ImageElementsArr[i].ImageTransparent:=Transparent;
  ImageElementsArr[i].ImageObj:=TImageObj.Create(Width, Height, Transparent);
  result:=ImageElementsArr[i].ImageObj;
  Log('Exiting FindOrCreateImageObj, created new image object with index='+inttostr(i));
end;

function FindOrCreateFontObj(FontName:string; FontSize:integer; FontCol:TColor):TFontObj;
var i,j:integer;
begin
  result:=nil;
  Log('Entered FindOrCreateFontObj with FontName='+FontName+', FontSize='+inttostr(FontSize)+', FontColor='+inttostr(FontCol));
  //ищем, есть ли такой шрифт уже создан
  j:=-1;
  for i:=0 to length(FontsElementsArr)-1 do
    if (FontsElementsArr[i].FontName=FontName)and
    (FontsElementsArr[i].FontSize=FontSize) then
    begin
      if FontsElementsArr[i].FontObj.FontColor=FontCol then
      begin
        result:=FontsElementsArr[i].FontObj;  //тут мы нашли нужный объект с нужным цветом
        Log('Exiting FindOrCreateFontObj, found same font object with index='+inttostr(i));
        exit;
      end
      else
        j:=i;   //тут объект нужный, но цвет другой, сохран€ем его, чтобы посмотреть, может ещЄ есть нужный объект с нужным цветом
    end;

  //смотрим, если мы нашли нужные параметры, но другой цвет
  if j<>-1 then
  begin
    i:=length(FontsElementsArr);
    setlength(FontsElementsArr,i+1);
    //FontsElementsArr[i].FontObj:=TFontObj.Create(FontName,FontSize,FontCol,FontsElementsArr[j].FontObj.Texture);
    FontsElementsArr[i].FontObj:=TFontObj.Create(FontName,FontSize,FontCol);
    FontsElementsArr[i].FontName:=FontName;
    FontsElementsArr[i].FontSize:=FontSize;
    result:=FontsElementsArr[i].FontObj;
    Log('Exiting FindOrCreateFontObj, found similar font with different color, similar index='+inttostr(j)+', new font object index='+inttostr(i));
    exit;
  end;

  //тут мы не нашли нужный объект, поэтому создаЄм его
  i:=length(FontsElementsArr);
  setlength(FontsElementsArr,i+1);
  FontsElementsArr[i].FontObj:=TFontObj.Create(FontName,FontSize,FontCol);
  FontsElementsArr[i].FontName:=FontName;
  FontsElementsArr[i].FontSize:=FontSize;
  result:=FontsElementsArr[i].FontObj;
  Log('Exiting FindOrCreateFontObj, created new font with index='+inttostr(i));
end;

//============================TFontObj begin===============================
constructor TFontObj.Create(FontName:string; FontSize:integer; FontCol:TColor; Texture:GLuint=0);
begin
  inherited Create;

  //initialization
  FFontName:=FontName;
  FFontSize:=FontSize;
  FontColor:=FontCol;
  FFontTexture:=Texture;
  FFontListBase:=0;
  FListGenerated:=false;
  FCharCellSize:=16;
  FExtraWidth:=0;
  FMaxHeight:=0; 

  if Texture=0 then InitTexture_Base_Metrics
  else InitBase_Metrics;
end;

destructor TFontObj.Destroy;
begin
  if FListGenerated then
    glDeleteLists(FFontListBase,256);

  if FFontTexture<>0 then glDeleteTextures(1,@FFontTexture);
  FFontTexture:=0;

  inherited;
end;

procedure TFontObj.InitTexture_Base_Metrics;
var bit:TBitmap;
max_cell,max_hei:integer;
xcoord,ycoord:integer;
i,j,k1,k2:integer;
str1:string;
DataRec:TRGBImageRec;
PtPerPixel:double;
loop:cardinal;
cx,cy:GLdouble;
w:integer;
begin
  //создаЄм битмап
  bit:=TBitmap.Create;
  try
  bit.Canvas.Font.Name:=FFontName;
  bit.Canvas.Font.Color:=clWhite;
  bit.Canvas.Font.Size:=FFontSize;
  bit.Canvas.Brush.Color:=clBlack;
  bit.Canvas.Brush.Style:=bsSolid;
  bit.Canvas.Pen.Color:=clRed;
  bit.Canvas.Pen.Style:=psSolid;

  //определ€ем максимум дл€ €чейки
  max_cell:=0;
  max_hei:=0;
  for i:=0 to 255 do
  begin
    j:=bit.Canvas.TextHeight(chr(i));
    if max_hei<j then max_hei:=j;
    if max_cell<j then max_cell:=j;
    j:=Ceil(bit.Canvas.TextWidth(chr(i))+j/2);
    if max_cell<j then max_cell:=j;
  end;

  //вычисл€ем каким размером должна быть текстура
  i:=16;
  while (i div 16)<max_cell do
  begin
    i:=i*2;
  end;

  //очищаем битмап
  bit.Width:=i;
  bit.Height:=i;
  bit.Canvas.FillRect(Rect(0,0,i,i));
  i:=i div 16;

  FCharCellSize:=i;
  FExtraWidth:=Ceil(max_hei/2);
  FMaxHeight:=max_hei;

  //рисуем все символы на битмап
  bit.Canvas.Brush.Color:=clBlack;
  bit.Canvas.Brush.Style:=bsClear;
  for j:=0 to 255 do
  begin
    //вычисл€ем координаты €чейки
    xcoord:=j mod 16;
    ycoord:=j div 16;
    //заносим параметры символа
    str1:=chr(j);
    FCharArr[j].Width:=bit.Canvas.TextWidth(str1);
    FCharArr[j].Height:=bit.Canvas.TextHeight(str1);
    FCharArr[j].TextureHeight:=FCharArr[j].Height;
    FCharArr[j].TextureWidth:=Ceil(FCharArr[j].Width+(FCharArr[j].TextureHeight/2));
    if (FCharArr[j].TextureWidth mod 2)<>0 then FCharArr[j].TextureWidth:=FCharArr[j].TextureWidth-1;
    //выводим
    k1:=trunc((i/2)-(FCharArr[j].Width/2));
    k2:=trunc((i/2)-(FCharArr[j].Height/2));
    bit.Canvas.TextOut(trunc(xcoord*i+k1),trunc(ycoord*i+k2),str1);
    FCharArr[j].VertexRect:=Rect(-k1,-k2,-k1+i,-k2+i);
  end;

  bit.PixelFormat:=pf24bit;

  //делаем текстуру
  LoadBMPFontTexture(bit,DataRec);
  glGenTextures(1, @FFontTexture);
  glBindTexture(GL_TEXTURE_2D, FFontTexture);
  glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);  {Texture blends with object background}
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  gluBuild2DMipmaps(GL_TEXTURE_2D, GL_RGBA, DataRec.SizeX, DataRec.SizeY, GL_RGBA, GL_UNSIGNED_BYTE, DataRec.data);

  if (DataRec.SizeX*DataRec.SizeY)<>0 then FreeMem(DataRec.data,DataRec.SizeX*DataRec.SizeY*4);

  //рисуем рамки дл€ отладки
  bit.Canvas.Brush.Style:=bsSolid;
  for j:=0 to 255 do
  begin         
    //вычисл€ем координаты €чейки
    xcoord:=j mod 16;
    ycoord:=j div 16;
    //выводим рамку пол€
    bit.Canvas.Brush.Color:=RGB(255,0,0);
    bit.Canvas.FrameRect(Rect(xcoord*i-1,ycoord*i-1,xcoord*i+i,ycoord*i+i));
    //выводим рамку символа дл€ текстуры
    //bit.Canvas.Brush.Color:=RGB(0,255,0);
    //bit.Canvas.FrameRect(Rect(xcoord*i+(i div 2)-(FCharArr[j].TextureWidth div 2)-2,ycoord*i+(i div 2)-(FCharArr[j].TextureHeight div 2)-2,xcoord*i+(i div 2)+(FCharArr[j].TextureWidth div 2)+2,ycoord*i+(i div 2)+(FCharArr[j].TextureHeight div 2)+2));
    //выводим рамку символа
    //bit.Canvas.Brush.Color:=RGB(255,255,0);
    //bit.Canvas.FrameRect(Rect(xcoord*i+(i div 2)-(FCharArr[j].Width div 2)-1,ycoord*i+(i div 2)-(FCharArr[j].Height div 2)-1,xcoord*i+(i div 2)+(FCharArr[j].Width div 2)+1,ycoord*i+(i div 2)+(FCharArr[j].Height div 2)+1));
  end;

  //bit.SaveToFile(FontName+'_'+inttostr(FontSize)+'_'+inttostr(FontColor)+'.bmp');
  finally
    bit.Free;
  end;

  //создани€ списка построени€
  FFontListBase:=glGenLists(256);
  FListGenerated:=true;
  glBindTexture(GL_TEXTURE_2D,FFontTexture);
  //определ€ем значение точки на 1 пиксель
  //max_cell:=FCharCellSize;
  //PtPerPixel:=1/(max_cell*16);
  PtPerPixel:=1/16;

  Log('Creating base for font '+FFontName+', Size='+inttostr(FFontSize));
  for loop:=0 to 255 do                                   // Vytvбшн 256 display listщ
  begin
    cx := (loop mod 16) / 16;                             // X pozice aktuбlnнho znaku
    cy := (loop div 16) /16;                              // Y pozice aktuбlnнho znaku
    //tw:=FCharArr[loop].TextureWidth;
    //th:=FCharArr[loop].TextureHeight;
    //if tw>max_cell then tw:=max_cell;
    w:=FCharArr[loop].Width;
    //h:=FCharArr[loop].Height;

    glNewList(FFontListBase + loop,GL_COMPILE);                    // Vytvoшenн display listu
      glBegin(GL_QUADS);                                  // Pro kaЮdэ znak jeden obdйlnнk
        //glTexCoord2f(cx+PtPerPixel*((max_cell/2)-(tw/2)),1-cy-PtPerPixel*((max_cell/2)-(th/2)));  glVertex2i(ceil(-((tw-w)/2))  , ceil(-((th-h)/2)));   // leviy nizhniy
        //glTexCoord2f(cx+PtPerPixel*((max_cell/2)+(tw/2)),1-cy-PtPerPixel*((max_cell/2)-(th/2)));  glVertex2i(ceil(((tw-w)/2)+w) , ceil(-((th-h)/2)));   // praviy nizhniy
        //glTexCoord2f(cx+PtPerPixel*((max_cell/2)+(tw/2)),1-cy-PtPerPixel*((max_cell/2)+(th/2)));  glVertex2i(ceil(((tw-w)/2)+w) , ceil(((th-h)/2)+h));   // praviy verhniy
        //glTexCoord2f(cx+PtPerPixel*((max_cell/2)-(tw/2)),1-cy-PtPerPixel*((max_cell/2)+(th/2)));  glVertex2i(ceil(-((tw-w)/2))  , ceil(((th-h)/2)+h));   // leviy verhniy
        glTexCoord2f(cx,             1-cy-PtPerPixel);    glVertex2i(FCharArr[loop].VertexRect.Left,FCharArr[loop].VertexRect.Bottom);
        glTexCoord2f(cx+PtPerPixel,  1-cy-PtPerPixel);    glVertex2i(FCharArr[loop].VertexRect.Right,FCharArr[loop].VertexRect.Bottom);
        glTexCoord2f(cx+PtPerPixel,  1-cy);               glVertex2i(FCharArr[loop].VertexRect.Right,FCharArr[loop].VertexRect.Top);
        glTexCoord2f(cx,             1-cy);               glVertex2i(FCharArr[loop].VertexRect.Left,FCharArr[loop].VertexRect.Top);
      glEnd;                                              // Konec znaku
      glTranslated(w,0,0);                               // Pшesun na pravou stranu znaku
    glEndList;                                            // Konec kreslenн display listu
    
    //Log('Char#'+inttostr(loop)+', L='+inttostr(FCharArr[loop].VertexRect.Left)+', R='+inttostr(FCharArr[loop].VertexRect.Right)+', W='+inttostr(FCharArr[loop].VertexRect.Right-FCharArr[loop].VertexRect.Left));
  end;
end;

procedure TFontObj.InitBase_Metrics;
var bit:TBitmap;
max_cell,max_hei:integer;
i,j:integer;
str1:string;
PtPerPixel:double;
loop:cardinal;
cx,cy:GLdouble;
w{,h,tw,th}:integer;
begin
  //создаЄм битмап
  bit:=TBitmap.Create;
  try
  bit.Canvas.Font.Name:=FFontName;
  bit.Canvas.Font.Color:=clWhite;
  bit.Canvas.Font.Size:=FFontSize;
  bit.Canvas.Brush.Color:=clBlack;
  bit.Canvas.Brush.Style:=bsSolid;
  bit.Canvas.Pen.Color:=clRed;
  bit.Canvas.Pen.Style:=psSolid;

  //определ€ем максимум дл€ €чейки
  max_cell:=0;
  max_hei:=0;
  for i:=0 to 255 do
  begin
    j:=bit.Canvas.TextHeight(chr(i));
    if max_hei<j then max_hei:=j;
    if max_cell<j then max_cell:=j;
    j:=Ceil(bit.Canvas.TextWidth(chr(i))+j/2);
    if max_cell<j then max_cell:=j;
  end;

  //вычисл€ем каким размером должна быть текстура
  i:=16;
  while (i div 16)<max_cell do
  begin
    i:=i*2;
  end;

  FCharCellSize:=i;
  FExtraWidth:=Ceil(max_hei/2);
  FMaxHeight:=max_hei;

  //не рисуем символы, а просто снимаем метрики
  for j:=0 to 255 do
  begin
    //заносим параметры символа
    str1:=chr(j);
    FCharArr[j].Width:=bit.Canvas.TextWidth(str1);
    FCharArr[j].Height:=bit.Canvas.TextHeight(str1);
    FCharArr[j].TextureHeight:=FCharArr[j].Height;
    FCharArr[j].TextureWidth:=Ceil(FCharArr[j].Width+(FCharArr[j].TextureHeight/2));
    if (FCharArr[j].TextureWidth mod 2)<>0 then FCharArr[j].TextureWidth:=FCharArr[j].TextureWidth-1;
  end;

  finally
    bit.Free;
  end;

  //создани€ списка построени€
  FFontListBase:=glGenLists(256);
  FListGenerated:=true;
  glBindTexture(GL_TEXTURE_2D,FFontTexture);
  //определ€ем значение точки на 1 пиксель
  //max_cell:=FCharCellSize;
  //PtPerPixel:=1/(max_cell*16);
  PtPerPixel:=1/16;

  for loop:=0 to 255 do                                   // Vytvбшн 256 display listщ
  begin
    cx := (loop mod 16) / 16;                             // X pozice aktuбlnнho znaku
    cy := (loop div 16) /16;                              // Y pozice aktuбlnнho znaku
    //tw:=FCharArr[loop].TextureWidth;
    //th:=FCharArr[loop].TextureHeight;
    //if tw>max_cell then tw:=max_cell;
    w:=FCharArr[loop].Width;
    //h:=FCharArr[loop].Height;

    glNewList(FFontListBase + loop,GL_COMPILE);                    // Vytvoшenн display listu
      glBegin(GL_QUADS);                                  // Pro kaЮdэ znak jeden obdйlnнk
        //glTexCoord2f(cx+PtPerPixel*((max_cell/2)-(tw/2)),1-cy-PtPerPixel*((max_cell/2)-(th/2)));  glVertex2i(ceil(-((tw-w)/2))  , ceil(-((th-h)/2)));   // leviy nizhniy
        //glTexCoord2f(cx+PtPerPixel*((max_cell/2)+(tw/2)),1-cy-PtPerPixel*((max_cell/2)-(th/2)));  glVertex2i(ceil(((tw-w)/2)+w) , ceil(-((th-h)/2)));   // praviy nizhniy
        //glTexCoord2f(cx+PtPerPixel*((max_cell/2)+(tw/2)),1-cy-PtPerPixel*((max_cell/2)+(th/2)));  glVertex2i(ceil(((tw-w)/2)+w) , ceil(((th-h)/2)+h));   // praviy verhniy
        //glTexCoord2f(cx+PtPerPixel*((max_cell/2)-(tw/2)),1-cy-PtPerPixel*((max_cell/2)+(th/2)));  glVertex2i(ceil(-((tw-w)/2))  , ceil(((th-h)/2)+h));   // leviy verhniy
        glTexCoord2f(cx,             1-cy-PtPerPixel);    glVertex2i(FCharArr[loop].VertexRect.Left,FCharArr[loop].VertexRect.Bottom);
        glTexCoord2f(cx+PtPerPixel,  1-cy-PtPerPixel);    glVertex2i(FCharArr[loop].VertexRect.Right,FCharArr[loop].VertexRect.Bottom);
        glTexCoord2f(cx+PtPerPixel,  1-cy);               glVertex2i(FCharArr[loop].VertexRect.Right,FCharArr[loop].VertexRect.Top);
        glTexCoord2f(cx,             1-cy);               glVertex2i(FCharArr[loop].VertexRect.Left,FCharArr[loop].VertexRect.Top);
      glEnd;                                              // Konec znaku
      glTranslated(w,0,0);                               // Pшesun na pravou stranu znaku
    glEndList;                                            // Konec kreslenн display listu
  end;
end;

procedure TFontObj.SetColor(Col:TColor);
begin
  FFontColor:=Col;
  FFontColorRGB.rgbtBlue:=GetBValue(FFontColor);
  FFontColorRGB.rgbtGreen:=GetGValue(FFontColor);
  FFontColorRGB.rgbtRed:=GetRValue(FFontColor);
end;

procedure TFontObj.DrawText(X,Y:integer; text:string);
begin
  if text='' then exit;
  //помен€ть цвет
  glColor4f(FFontColorRGB.rgbtRed/255,FFontColorRGB.rgbtGreen/255,FFontColorRGB.rgbtBlue/255,1);

  glBindTexture(GL_TEXTURE_2D,FFontTexture);
  //glBindTexture(GL_TEXTURE_2D,0);
  //glPushMatrix;
  glLoadIdentity;
  glTranslated(x,y,0);
  {glBegin(GL_QUADS);
    glVertex2i(0,0);
    glVertex2i(500,0);
    glVertex2i(500,30);
    glVertex2i(0,30);
  glEnd;    }
  glListBase(FFontListBase);
  glCallLists(length(text),GL_UNSIGNED_BYTE,@text[1]);
  //glPopMatrix;
end;

procedure TFontObj.DrawText(X,Y:double; text:string);
begin
  if text='' then exit;
  //помен€ть цвет
  glColor4f(FFontColorRGB.rgbtRed/255,FFontColorRGB.rgbtGreen/255,FFontColorRGB.rgbtBlue/255,1);

  glBindTexture(GL_TEXTURE_2D,FFontTexture);
  //glBindTexture(GL_TEXTURE_2D,0);
  //glPushMatrix;
  glLoadIdentity;
  glTranslated(x,y,0);
  {glBegin(GL_QUADS);
    glVertex2i(0,0);
    glVertex2i(500,0);
    glVertex2i(500,30);
    glVertex2i(0,30);
  glEnd;    }
  glListBase(FFontListBase);
  glCallLists(length(text),GL_UNSIGNED_BYTE,@text[1]);
  //glPopMatrix;
end;

{function TFontObj.DrawTextFunc(R:TRect; text:string; Align:TAlignment=taLeftJustify; WordWrap:boolean=false):integer;
type TLineRec=record
       start,len:integer;
       line_text:string;
       h_start,w_start:integer;
       height:integer;
     end;
var i,j,k,z:integer;
line_cur,word_cur,max_width,max_height:integer;
lines:array of TLineRec;
begin
  if text='' then exit;
  //помен€ть цвет
  glColor4f(FFontColorRGB.rgbtRed/255,FFontColorRGB.rgbtGreen/255,FFontColorRGB.rgbtBlue/255,1);
  glBindTexture(GL_TEXTURE_2D,FFontTexture);

  line_cur:=0;
  word_cur:=0;
  max_width:=R.Right-R.Left;
  k:=length(text);
  z:=length(lines);
  setlength(lines,z+1);
  lines[z].start:=1;
  for i:=1 to k do
  begin
    if (text[i]=' ')or(i=k) then
    begin
      if line_cur<max_width then  //мы ещЄ не достигли конца строки
      begin
        word_cur:=0;
        line_cur:=line_cur+FCharArr[ord(text[i])].Width;
        lines[z].len:=i-lines[z].start+1;
        if i<>k then
        begin
          z:=length(lines);
          setlength(lines,z+1);
          lines[z].start:=lines[z-1].start+lines[z-1].len;
        end;
      end
      else
      begin  //больше чем конец строки, переносим слово
        line_cur:=word_cur;
        lines[z].len:=i-lines[z].start+1;
        z:=length(lines);
        setlength(lines,z+1);
        lines[z].start:=lines[z-1].start+lines[z-1].len;
        lines[z].len:=i-lines[z].start+1;
      end;
    end
    else
    begin  //если буква, то идЄт слово, считаем
      j:=FCharArr[ord(text[i])].Width;
      line_cur:=line_cur+j;
      word_cur:=word_cur+j;
    end;
  end;

  max_height:=r.Bottom-r.Top;
  k:=0;
  for i:=0 to length(lines)-1 do
  begin
    lines[i].line_text:=copy(text,lines[i].start,lines[i].len);
    //вычисл€ем начало по горизонтали
    j:=TextWidth(lines[i].line_text);
    case Align of
      taLeftJustify:lines[i].w_start:=r.Left;
      taRightJustify:lines[i].w_start:=r.Right-j;
      taCenter:lines[i].w_start:=r.Left+(max_width div 2)-(j div 2);
    end;
    lines[i].height:=TextHeight(lines[i].line_text);
    k:=k+lines[i].height;
  end;
  result:=k;
  k:=(max_height div 2)-(k div 2);  //начало строк по вертикали
  glListBase(FFontListBase);
  for i:=0 to length(lines)-1 do
  begin
    lines[i].h_start:=r.Top+k;
    k:=k+lines[i].height;

    glLoadIdentity;
    glTranslated(lines[i].w_start,lines[i].h_start,0);
    glCallLists(lines[i].len,GL_UNSIGNED_BYTE,@text[lines[i].start]);
  end;


end;  }

function TFontObj.DrawTextFunc(R:TRect; text:string; Align:TAlignment=taLeftJustify; WordWrap:boolean=false; Offset:double=0):integer;
var i,j,k,rect_wid,rect_hei,text_hei,hei,wid:integer;
input_text,line_text,str:string;
line_arr:array of string;
begin
  rect_wid:=r.Right-r.Left;
  rect_hei:=r.Bottom-r.Top;

  if WordWrap=false then
  begin
    i:=TextWidth(text);
    j:=TextHeight(text);
    case Align of
      taLeftJustify:DrawText(R.Left,R.Top+(rect_hei/2)-(j/2),text);
      taRightJustify:DrawText(R.Right-i,R.Top+(rect_hei/2)-(j/2),text);
      taCenter:DrawText(R.Left+(rect_wid/2)-(i/2),R.Top+(rect_hei/2)-(j/2),text);
      taRunning:DrawText(R.Left+Offset,R.Top+(rect_hei/2)-(j/2),text);
    end;
    result:=j;
  end
  else
  begin
    input_text:=text;
    text_hei:=TextHeight(text);
    //hei:=R.Top;
    hei:=text_hei;
    wid:=0;
    setlength(line_arr,0);
    rect_wid:=R.Right-R.Left;
    i:=pos(' ',input_text);
    line_text:='';
    str:='';
    while i<>0 do
    begin
      //копируем очередное слово
      str:=copy(input_text,1,i);
      delete(input_text,1,i);
      i:=pos(' ',input_text);
      //смотрим, не длинее ли оно строки
      j:=TextWidth(line_text+str);
      if j>rect_wid then
      begin
        if line_text='' then line_text:=str;
        j:=TextWidth(line_text);
        if wid<j then wid:=j;
        //заносим строку в массив
        j:=length(line_arr);
        setlength(line_arr,j+1);
        line_arr[j]:=line_text;
        line_text:=str;
        hei:=hei+text_hei;
      end
      else line_text:=line_text+str;
    end;

    if input_text<>'' then
    begin
      j:=TextWidth(line_text+input_text);
      if j>rect_wid then
      begin
        if line_text='' then
        begin
          line_text:=input_text;
          j:=TextWidth(line_text);
          //if wid<j then wid:=j;
          //заносим строку в массив
          j:=length(line_arr);
          setlength(line_arr,j+1);
          line_arr[j]:=line_text;
        end
        else
        begin
          j:=TextWidth(line_text);
          //if wid<j then wid:=j;
          //заносим строку в массив
          j:=length(line_arr);
          setlength(line_arr,j+1);
          line_arr[j]:=line_text;
          j:=length(line_arr);
          setlength(line_arr,j+1);
          line_arr[j]:=input_text;
          //line_text:='';
          //hei:=hei+text_hei;
        end;
      end
      else
      begin
        line_text:=line_text+input_text;
        j:=TextWidth(line_text);
        if wid<j then wid:=j;
        //заносим строку в массив
        j:=length(line_arr);
        setlength(line_arr,j+1);
        line_arr[j]:=line_text;
        //hei:=hei+text_hei;
      end;
    end;

    //выводим все строки
    //считаем, сколько занимают все строки по высоте\
    j:=0;
    for i:=0 to length(line_arr)-1 do
    begin
      j:=j+TextHeight(line_arr[i]);
      k:=length(line_arr[i]);
      if line_arr[i][k]=' ' then delete(line_arr[i],k,1);
    end;
    //вычисл€ем отступ первой строки от верхней границы
    j:=round((rect_hei/2)-(j/2));
    //выводим
    for i:=0 to length(line_arr)-1 do
    begin
      k:=TextWidth(line_arr[i]);
      case Align of
        taLeftJustify:DrawText(R.Left,R.Top+j+(i*text_hei),line_arr[i]);
        taRightJustify:DrawText(R.Right-k,R.Top+j+(i*text_hei),line_arr[i]);
        taCenter:DrawText(R.Left+(rect_wid/2)-(k/2),R.Top+j+(i*text_hei),line_arr[i]);
      end;
    end;
    setlength(line_arr,0);

    result:=hei;
  end;
end;

function TFontObj.DrawTextFunc(R:TRect; X,Y:integer; Text:string; Align:TAlignment=taLeftJustify):integer;
var i:integer;
begin
  if text='' then exit;
  //помен€ть цвет
  glColor4f(FFontColorRGB.rgbtRed/255,FFontColorRGB.rgbtGreen/255,FFontColorRGB.rgbtBlue/255,1);
  glBindTexture(GL_TEXTURE_2D,FFontTexture);
  glLoadIdentity;
  i:=TextWidth(text);
  case Align of
    taLeftJustify:glTranslated(R.Left,R.Top,0);
    taRightJustify:glTranslated(R.Right-i,R.Top,0);
    taCenter:glTranslated(r.Left+((r.Right-r.Left)div 2)-(i div 2),R.Top,0);
  end;
  glTranslated(X,Y,0);
  glListBase(FFontListBase);
  glCallLists(length(text),GL_UNSIGNED_BYTE,@text[1]);

  result:=TextHeight(text);
end;

function TFontObj.TextWidth(text:string):integer;
var i:integer;
begin
  result:=0;
  for i:=1 to length(text) do
    result:=result+FCharArr[ord(text[i])].Width;
end;

function TFontObj.TextHeight(text:string):integer;
var i:integer;
begin
  result:=0;
  for i:=1 to length(text) do
    if FCharArr[ord(text[i])].Height>result then result:=FCharArr[ord(text[i])].Height;
end;

{function TFontObj.TextDimensions(text:string; max_width:integer; out Width:integer):integer;
var i,j,k:integer;
line_cur,word_cur,height_cur,width_max:integer;
begin
  result:=0;
  line_cur:=0;
  word_cur:=0;
  width_max:=0;
  if text='' then exit;
  height_cur:=FCharArr[ord(text[1])].Height;
  k:=length(text);
  for i:=1 to k do
  begin
    if (text[i]=' ')or(i=k) then
    begin
      if line_cur<max_width then  //мы ещЄ не достигли конца строки
      begin
        word_cur:=0;
        line_cur:=line_cur+FCharArr[ord(text[i])].Width;
        if width_max<line_cur then width_max:=line_cur;
      end
      else
      begin  //больше чем конец строки, переносим слово
        if width_max<(line_cur-word_cur) then width_max:=line_cur-word_cur;
        line_cur:=word_cur;
        height_cur:=height_cur+FCharArr[ord(text[i])].Height;
      end;
    end
    else
    begin  //если буква, то идЄт слово, считаем
      j:=FCharArr[ord(text[i])].Width;
      line_cur:=line_cur+j;
      word_cur:=word_cur+j;
    end;
  end;

  Width:=width_max;
  result:=height_cur;
end; }

procedure TFontObj.CalcTextDimensions(text:string; Rect:TRect; out Width:integer; out Height:integer; WordWrap:boolean=false);
var i,j:integer;
hei,wid,text_hei,rect_wid:integer;
input_text,line_text,str:string;
begin
  if WordWrap=false then
  begin
    Width:=TextWidth(text);
    Height:=TextHeight(text);
  end
  else
  begin
    input_text:=text;
    text_hei:=TextHeight(text);
    hei:=text_hei;
    wid:=0;
    rect_wid:=Rect.Right-Rect.Left;
    i:=pos(' ',input_text);
    line_text:='';
    str:='';
    while i<>0 do
    begin
      //копируем очередное слово
      str:=copy(input_text,1,i);
      delete(input_text,1,i);
      i:=pos(' ',input_text);
      //смотрим, не длинее ли оно строки
      j:=TextWidth(line_text+str);
      if j>rect_wid then
      begin
        if line_text='' then line_text:=str;
        j:=TextWidth(line_text);
        if wid<j then wid:=j;
        line_text:=str;
        hei:=hei+text_hei;
      end
      else line_text:=line_text+str;
    end;

    if input_text<>'' then
    begin
      j:=TextWidth(line_text+input_text);
      if j>rect_wid then
      begin
        if line_text='' then line_text:=input_text;
        j:=TextWidth(line_text);
        if wid<j then wid:=j;
        //line_text:='';
        hei:=hei+text_hei;
      end
      else
      begin
        line_text:=line_text+input_text;
        j:=TextWidth(line_text);
        if wid<j then wid:=j;
      end;
    end;

    Width:=wid;
    Height:=hei;
  end;
end;

//++++++++++++++++++++++++++++TFontObj end+++++++++++++++++++++++++++++++


//===========================TImageObj begin===============================
constructor TImageObj.Create(FileName:string; Transparent:boolean);
begin
  inherited Create;

  FFileName:=FileName;
  FTransparent:=Transparent;
  FImageTexture:=0;

  InitTexture;
end;

constructor TImageObj.Create(Width, Height: integer; Transparent:boolean);
begin
  inherited Create;

  FFileName:='';
  FTransparent:=Transparent;
  FImageTexture:=0;
  FImageWidth:=Width;
  FImageHeight:=Height;

  InitTexture;
end;

destructor TImageObj.Destroy;
begin
  if FImageTexture<>0 then glDeleteTextures(1,@FImageTexture);
  FImageTexture:=0;

  inherited;
end;

procedure TImageObj.InitTexture;
begin
  if FFileName='' then
  begin
    if LoadEmptyTexture(FImageTexture,FTransparent,FImageWidth,FImageHeight)=false then FImageTexture:=0;
    exit;
  end;

  if FileExists(FFileName) then
  begin
    if LoadTexture(FFileName,FImageTexture,FTransparent,FImageWidth,FImageHeight)=false then FImageTexture:=0;
  end;
end;

procedure TImageObj.Draw(X,Y:integer; Width,Height:integer);
begin
  glBindTexture(GL_TEXTURE_2D,FImageTexture);
  glLoadIdentity;

  glColor3f(1,1,1);
  glBegin(GL_QUADS);
    glTexCoord2f(0.0, 1.0);
    glVertex2i(X,Y);
    glTexCoord2f(1.0, 1.0);
    glVertex2i(X+Width,Y);
    glTexCoord2f(1.0, 0.0);
    glVertex2i(X+Width,Y+Height);
    glTexCoord2f(0.0, 0.0);
    glVertex2i(X,Y+Height);
  glEnd();
end;

//+++++++++++++++++++++++++++TImageObj end+++++++++++++++++++++++++++++++

initialization

  setlength(FontsElementsArr,0);
  setlength(ImageElementsArr,0);

finalization

  FinalizationProc;

end.
