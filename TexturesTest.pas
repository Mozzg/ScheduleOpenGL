unit TexturesTest;

interface

uses dglOpenGL, Graphics;

type TRGBImageRec=record
       SizeX,SizeY:integer;
       HasAlpha:boolean;
       data:Pointer;
     end;

     THSVColor=record
       h:double;
       s:double;
       v:double;
     end;

     TRGBColorByte=record
       r:byte;
       g:byte;
       b:byte;
     end;

     TRGBColorDouble=record
       r:double;
       g:double;
       b:double;
     end;

function LoadTexture(Filename: String; var Texture: GLuint; Transparent:boolean; out Width:integer; out Height:integer):boolean;
function LoadEmptyTexture(var Texture: GLuint; Transparent:boolean; Width:integer; Height:integer):boolean;

function LoadBMPTexture(Filename:string; var DataRec:TRGBImageRec; Transparent:boolean):boolean; overload;
function LoadBMPTexture(var FileBit:Graphics.TBitmap; var DataRec:TRGBImageRec; Transparent:boolean):boolean; overload;
function LoadBMPFontTexture(var FileBit:Graphics.TBitmap; var DataRec:TRGBImageRec):boolean;
function LoadJPEGTexture(Filename:string; var DataRec:TRGBImageRec; Transparent:boolean):boolean;
function LoadPNGTexture(Filename:string; var DataRec:TRGBImageRec; Transparent:boolean):boolean;

implementation

uses SysUtils, Windows, jpeg, pngimage, Math;

//----------------StrUtils implementation begin-----------------------
function AnsiCompareStr(const S1, S2: string): Integer;
begin
  Result := CompareString(LOCALE_USER_DEFAULT, 0, PChar(S1), Length(S1),
    PChar(S2), Length(S2)) - 2;
end;

function AnsiSameStr(const S1, S2: string): Boolean;
begin
  Result := AnsiCompareStr(S1, S2) = 0;
end;

function AnsiIndexStr(const AText: string;
  const AValues: array of string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := Low(AValues) to High(AValues) do
    if AnsiSameStr(AText, AValues[I]) then
    begin
      Result := I;
      Break;
    end;
end;

//=================StrUtils implementation end========================

//IN = R,G,B from 0 to 255
//out H in degrees from 0 to 360
//S saturation in fraction from 0 to 1
//V value in fraction from 0 to 1
function RGBtoHSV(r,g,b:byte):THSVColor;
var minv,maxv,delta:double;
InRGB:TRGBColorDouble;
begin
  InRGB.r:=r/255;
  InRGB.g:=g/255;
  InRGB.b:=b/255;

  minv:=min(InRGB.r,min(InRGB.g,InRGB.b));
  maxv:=max(InRGB.r,max(InRGB.g,InRGB.b));

  result.v:=maxv;
  delta:=maxv-minv;
  if (delta<0.00001) then
  begin
    result.h:=0;
    result.s:=0;
    exit;
  end;

  if (maxv>0) then
    result.s:=delta/maxv
  else
  begin
    result.s:=0;
    result.h:=0;
    exit;
  end;

  if (InRGB.r>=maxv) then
    result.h:=(InRGB.g-InRGB.b)/delta
  else if (InRGB.g>=maxv) then
    result.h:=2.0+(InRGB.b-InRGB.r)/delta
  else
    result.h:=4.0+(InRGB.r-InRGB.g)/delta;

  result.h:=result.h*60;

  if result.h<0 then result.h:=result.h+360.0; 
end;


//IN H in degrees from 0 to 360
//S saturation in fraction from 0 to 1
//V value in fraction from 0 to 1
//OUT = R,G,B in fraction from 0 to 1
function HSVtoRGB(InHSV:THSVColor):TRGBColorByte;
var hh,ff,p,q,t:double;
i:integer;
vrgb:TRGBColorDouble;
begin
  if (InHSV.s<=0) then
  begin
    result.r:=trunc(InHSV.v*255);
    result.g:=trunc(InHSV.v*255);
    result.b:=trunc(INHSV.v*255);
    exit;
  end;

  hh:=InHSV.h;
  if hh>=360 then hh:=0;
  hh:=hh/60;
  i:=floor(hh);
  ff:=hh-i;
  p:=InHSV.v*(1-InHSV.s);
  q:=InHSV.v*(1-(InHSV.s*ff));
  t:=InHSV.v*(1-(InHSV.s*(1-ff)));

  case i of
    0:begin
        vrgb.r:=InHSV.v;
        vrgb.g:=t;
        vrgb.b:=p;
      end;
    1:begin
        vrgb.r:=q;
        vrgb.g:=InHSV.v;
        vrgb.b:=p;
      end;
    2:begin
        vrgb.r:=p;
        vrgb.g:=InHSV.v;
        vrgb.b:=t;
      end;
    3:begin
        vrgb.r:=p;
        vrgb.g:=q;
        vrgb.b:=InHSV.v;
      end;
    4:begin
        vrgb.r:=t;
        vrgb.g:=p;
        vrgb.b:=InHSV.v;
      end;
    else
      begin
        vrgb.r:=InHSV.v;
        vrgb.g:=p;
        vrgb.b:=q;
      end; 
  end;

  result.r:=trunc(vrgb.r*255);
  result.g:=trunc(vrgb.g*255);
  result.b:=trunc(vrgb.b*255);
end;

function LoadEmptyTexture(var Texture: GLuint; Transparent:boolean; Width:integer; Height:integer):boolean;
var Rec:TRGBImageRec;
i:integer;
begin
  Result:=false;
  Rec.SizeX:=width;
  Rec.SizeY:=height;
  Rec.HasAlpha:=Transparent;
  i:=Rec.SizeX*Rec.SizeY*4;
  GetMem(Rec.data,i);
  //FillChar(@Rec.data,i,255);

  glGenTextures(1, @Texture);
  glBindTexture(GL_TEXTURE_2D, Texture);
  glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);  {Texture blends with object background}
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  gluBuild2DMipmaps(GL_TEXTURE_2D, GL_RGBA, Rec.SizeX, Rec.SizeY, GL_RGBA, GL_UNSIGNED_BYTE, Rec.data);

  if (Rec.SizeX*Rec.SizeY)<>0 then FreeMem(Rec.data,Rec.SizeX*Rec.SizeY*4);

  Result:=true;
end;

function LoadBMPTexture(Filename:string; var DataRec:TRGBImageRec; Transparent:boolean):boolean;
var bit:TPicture;
ColorData:array of byte;
TransparentColor:array[0..2] of byte;
p:^Byte;
i,j,z,wid,hei:integer;
x:byte;
Palette:HPALETTE;
PaletteSize:integer;
LogSize: Integer;
LogPalette: PLogPalette;
begin
  result:=false;
  if FileExists(Filename)=false then exit;

  bit:=TPicture.Create;
  try
    bit.LoadFromFile(Filename);
    wid:=bit.Width;
    hei:=bit.Height;
    SetLength(ColorData,wid*hei*4);

    case bit.Bitmap.PixelFormat of
      pf4bit:     //4 бита - 16 цветов
        begin
          //мы знаем, что при таком формате нужна палитра, поэтому загружаем её
          Palette:=bit.Bitmap.Palette;
          // определение размера палитры
          PaletteSize:=0;
          if GetObject(Palette, SizeOf(PaletteSize), @PaletteSize)=0 then exit;
          if PaletteSize=0 then exit;
          //задаём размер структуры
          LogSize := SizeOf(TLogPalette) + (PaletteSize - 1) * SizeOf(TPaletteEntry);
          //заполняем палитру
          GetMem(LogPalette, LogSize);
          try
            LogPalette^.palVersion:=$0300;
            LogPalette^.palNumEntries:=PaletteSize;
            GetPaletteEntries(Palette, 0, PaletteSize, LogPalette^.palPalEntry);

            //заполняем цвета по 2 цвета
            for i:=hei-1 downto 0 do
            begin
              p:=bit.Bitmap.ScanLine[i];
              if (i=(hei-1))and(Transparent) then
              begin
                x:=(p^) shr 4;
                TransparentColor[0]:=LogPalette^.palPalEntry[x].peRed;
                TransparentColor[1]:=LogPalette^.palPalEntry[x].peGreen;
                TransparentColor[2]:=LogPalette^.palPalEntry[x].peBlue;
              end;

              for j:=0 to wid-1 do
              begin
                z:=((hei-1-i)*wid*4)+j*4;  //индекс в общем цветовом массиве
                //вычисляем индекс в массиве
                x:=p^;
                if (j mod 2)=0 then x:=x shr 4
                else x:=x and ($F);
                //копируем палитру
                move(LogPalette^.palPalEntry[x],ColorData[z],3);
                //заполняем альфу
                if (Transparent) then
                begin
                  if (CompareMem(@TransparentColor[0],@ColorData[z],3)) then ColorData[z+3]:=0
                  else ColorData[z+3]:=255;
                end
                else ColorData[z+3]:=255;

                if (j mod 2)=1 then inc(p);
              end;
            end;
          finally
            FreeMem(LogPalette, LogSize);
          end;
        end;
      pf8bit:     //8 бита - 256 цветов
        begin
          //мы знаем, что при таком формате нужна палитра, поэтому загружаем её
          Palette:=bit.Bitmap.Palette;
          // определение размера палитры
          PaletteSize:=0;
          if GetObject(Palette, SizeOf(PaletteSize), @PaletteSize)=0 then exit;
          if PaletteSize=0 then exit;
          //задаём размер структуры
          LogSize := SizeOf(TLogPalette) + (PaletteSize - 1) * SizeOf(TPaletteEntry);
          //заполняем палитру
          GetMem(LogPalette, LogSize);
          try
            LogPalette^.palVersion:=$0300;
            LogPalette^.palNumEntries:=PaletteSize;
            GetPaletteEntries(Palette, 0, PaletteSize, LogPalette^.palPalEntry);

            //заполняем цвета по 2 цвета
            for i:=hei-1 downto 0 do
            begin
              p:=bit.Bitmap.ScanLine[i];
              if (i=(hei-1))and(Transparent) then
              begin
                x:=p^;
                TransparentColor[0]:=LogPalette^.palPalEntry[x].peRed;
                TransparentColor[1]:=LogPalette^.palPalEntry[x].peGreen;
                TransparentColor[2]:=LogPalette^.palPalEntry[x].peBlue;
              end;

              for j:=0 to wid-1 do
              begin
                z:=((hei-1-i)*wid*4)+j*4;  //индекс в общем цветовом массиве
                //вычисляем индекс в массиве
                x:=p^;
                //копируем палитру
                move(LogPalette^.palPalEntry[x],ColorData[z],3);
                //заполняем альфу
                if (Transparent) then
                begin
                  if (CompareMem(@TransparentColor[0],@ColorData[z],3)) then ColorData[z+3]:=0
                  else ColorData[z+3]:=255;
                end
                else ColorData[z+3]:=255;
                inc(p);
              end;
            end;
          finally
            FreeMem(LogPalette, LogSize);
          end;
        end;
      pf24bit:
        begin
          //тут палитра не нужна, все данные уже в битмапе
          for i:=hei-1 downto 0 do
          begin
            p:=bit.Bitmap.ScanLine[i];
            if i=(hei-1) then Move(p^,TransparentColor[0],3);

            for j:=0 to wid-1 do
            begin
              z:=((hei-1-i)*wid*4)+j*4;
              move(p^,ColorData[z],3);
              x:=ColorData[z];
              ColorData[z]:=ColorData[z+2];
              ColorData[z+2]:=x;
              //заполняем альфу
              if (Transparent)and(CompareMem(@TransparentColor[0],Addr(p^),3)) then ColorData[z+3]:=0
              else ColorData[z+3]:=255;
              inc(p,3);
            end;
          end;
        end;
      pf32bit:
        begin
          //палитра идёт с 8 битами альфы (игнорируем альфу, делаем свою по первому пикселю)
          for i:=hei-1 downto 0 do
          begin
            p:=bit.Bitmap.ScanLine[i];
            if i=(hei-1) then Move(p^,TransparentColor[0],3);

            for j:=0 to wid-1 do
            begin
              z:=((hei-1-i)*wid*4)+j*4;
              move(p^,ColorData[z],3);
              x:=ColorData[z];
              ColorData[z]:=ColorData[z+2];
              ColorData[z+2]:=x;
              //заполняем альфу
              if (Transparent)and(CompareMem(@TransparentColor[0],Addr(p^),3)) then ColorData[z+3]:=0
              else ColorData[z+3]:=255;
              inc(p,4);
            end;
          end;
        end;
      else exit;
    end;  //case bit.Bitmap.PixelFormat of
  finally
    bit.Free;
  end;

  DataRec.SizeX:=wid;
  DataRec.SizeY:=hei;
  DataRec.HasAlpha:=Transparent;
  i:=DataRec.SizeX*DataRec.SizeY*4;
  GetMem(DataRec.data,i);
  Move(ColorData[0],pByteArray(DataRec.data)^[0],i);

  //здесь у нас должен быть правильно заполненый массив ColorData с альфа каналом
  //готовим текстуру
  (*glGenTextures(1, @Texture);
  glBindTexture(GL_TEXTURE_2D, Texture);
  glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);  {Texture blends with object background}
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST); { only first two can be used }
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST); { all of the above can be used }
  gluBuild2DMipmaps(GL_TEXTURE_2D, GL_RGBA, wid, hei, GL_RGBA, GL_UNSIGNED_BYTE, Addr(ColorData[0])); *)

  setlength(ColorData,0);
  result:=true;
end;

function LoadBMPTexture(var FileBit:Graphics.TBitmap; var DataRec:TRGBImageRec; Transparent:boolean):boolean;
var //bit:TPicture;
ColorData:array of byte;
TransparentColor:array[0..2] of byte;
p:^Byte;
i,j,z,wid,hei:integer;
x:byte;
Palette:HPALETTE;
PaletteSize:integer;
LogSize: Integer;
LogPalette: PLogPalette;
begin
  result:=false;
  if FileBit=nil then exit;

  //bit:=TPicture.Create;
  //try
    {bit.Bitmap.Width:=FileBit.Width;
    bit.Bitmap.Height:=FileBit.Height;
    bit.Bitmap.Canvas.Draw(0,0,FileBit);  }
    //FileBit.SaveToFile('temp.bmp');
    //bit.LoadFromFile('temp.bmp');

    wid:=Filebit.Width;
    hei:=Filebit.Height;
    SetLength(ColorData,wid*hei*4);

    case Filebit.PixelFormat of
      pf4bit:     //4 бита - 16 цветов
        begin
          //мы знаем, что при таком формате нужна палитра, поэтому загружаем её
          Palette:=Filebit.Palette;
          // определение размера палитры
          PaletteSize:=0;
          if GetObject(Palette, SizeOf(PaletteSize), @PaletteSize)=0 then exit;
          if PaletteSize=0 then exit;
          //задаём размер структуры
          LogSize := SizeOf(TLogPalette) + (PaletteSize - 1) * SizeOf(TPaletteEntry);
          //заполняем палитру
          GetMem(LogPalette, LogSize);
          try
            LogPalette^.palVersion:=$0300;
            LogPalette^.palNumEntries:=PaletteSize;
            GetPaletteEntries(Palette, 0, PaletteSize, LogPalette^.palPalEntry);

            //заполняем цвета по 2 цвета
            for i:=hei-1 downto 0 do
            begin
              p:=Filebit.ScanLine[i];
              if (i=(hei-1))and(Transparent) then
              begin
                x:=(p^) shr 4;
                TransparentColor[0]:=LogPalette^.palPalEntry[x].peRed;
                TransparentColor[1]:=LogPalette^.palPalEntry[x].peGreen;
                TransparentColor[2]:=LogPalette^.palPalEntry[x].peBlue;
              end;

              for j:=0 to wid-1 do
              begin
                z:=((hei-1-i)*wid*4)+j*4;  //индекс в общем цветовом массиве
                //вычисляем индекс в массиве
                x:=p^;
                if (j mod 2)=0 then x:=x shr 4
                else x:=x and ($F);
                //копируем палитру
                move(LogPalette^.palPalEntry[x],ColorData[z],3);
                //заполняем альфу
                if (Transparent) then
                begin
                  if (CompareMem(@TransparentColor[0],@ColorData[z],3)) then ColorData[z+3]:=0
                  else ColorData[z+3]:=255;
                end
                else ColorData[z+3]:=255;

                if (j mod 2)=1 then inc(p);
              end;
            end;
          finally
            FreeMem(LogPalette, LogSize);
          end;
        end;
      pf8bit:     //8 бита - 256 цветов
        begin
          //мы знаем, что при таком формате нужна палитра, поэтому загружаем её
          Palette:=Filebit.Palette;
          // определение размера палитры
          PaletteSize:=0;
          if GetObject(Palette, SizeOf(PaletteSize), @PaletteSize)=0 then exit;
          if PaletteSize=0 then exit;
          //задаём размер структуры
          LogSize := SizeOf(TLogPalette) + (PaletteSize - 1) * SizeOf(TPaletteEntry);
          //заполняем палитру
          GetMem(LogPalette, LogSize);
          try
            LogPalette^.palVersion:=$0300;
            LogPalette^.palNumEntries:=PaletteSize;
            GetPaletteEntries(Palette, 0, PaletteSize, LogPalette^.palPalEntry);

            //заполняем цвета по 2 цвета
            for i:=hei-1 downto 0 do
            begin
              p:=Filebit.ScanLine[i];
              if (i=(hei-1))and(Transparent) then
              begin
                x:=p^;
                TransparentColor[0]:=LogPalette^.palPalEntry[x].peRed;
                TransparentColor[1]:=LogPalette^.palPalEntry[x].peGreen;
                TransparentColor[2]:=LogPalette^.palPalEntry[x].peBlue;
              end;

              for j:=0 to wid-1 do
              begin
                z:=((hei-1-i)*wid*4)+j*4;  //индекс в общем цветовом массиве
                //вычисляем индекс в массиве
                x:=p^;
                //копируем палитру
                move(LogPalette^.palPalEntry[x],ColorData[z],3);
                //заполняем альфу
                if (Transparent) then
                begin
                  if (CompareMem(@TransparentColor[0],@ColorData[z],3)) then ColorData[z+3]:=0
                  else ColorData[z+3]:=255;
                end
                else ColorData[z+3]:=255;
                inc(p);
              end;
            end;
          finally
            FreeMem(LogPalette, LogSize);
          end;
        end;
      pf24bit:
        begin
          //тут палитра не нужна, все данные уже в битмапе
          for i:=hei-1 downto 0 do
          begin
            p:=Filebit.ScanLine[i];
            if i=(hei-1) then Move(p^,TransparentColor[0],3);

            for j:=0 to wid-1 do
            begin
              z:=((hei-1-i)*wid*4)+j*4;
              move(p^,ColorData[z],3);
              x:=ColorData[z];
              ColorData[z]:=ColorData[z+2];
              ColorData[z+2]:=x;
              //заполняем альфу
              if (Transparent)and(CompareMem(@TransparentColor[0],Addr(p^),3)) then ColorData[z+3]:=0
              else ColorData[z+3]:=255;
              inc(p,3);
            end;
          end;
        end;
      pf32bit:
        begin
          //палитра идёт с 8 битами альфы (игнорируем альфу, делаем свою по первому пикселю)
          for i:=hei-1 downto 0 do
          begin
            p:=Filebit.ScanLine[i];
            if i=(hei-1) then Move(p^,TransparentColor[0],3);

            for j:=0 to wid-1 do
            begin
              z:=((hei-1-i)*wid*4)+j*4;
              move(p^,ColorData[z],3);
              x:=ColorData[z];
              ColorData[z]:=ColorData[z+2];
              ColorData[z+2]:=x;
              //заполняем альфу
              if (Transparent)and(CompareMem(@TransparentColor[0],Addr(p^),3)) then ColorData[z+3]:=0
              else ColorData[z+3]:=255;
              inc(p,4);
            end;
          end;
        end;
      else exit;
    end;  //case bit.Bitmap.PixelFormat of
  //finally
    //bit.Free;
  //end;

  DataRec.SizeX:=wid;
  DataRec.SizeY:=hei;
  DataRec.HasAlpha:=Transparent;
  i:=DataRec.SizeX*DataRec.SizeY*4;
  GetMem(DataRec.data,i);
  Move(ColorData[0],pByteArray(DataRec.data)^[0],i);

  //здесь у нас должен быть правильно заполненый массив ColorData с альфа каналом
  //готовим текстуру
  (*glGenTextures(1, @Texture);
  glBindTexture(GL_TEXTURE_2D, Texture);
  glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);  {Texture blends with object background}
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST); { only first two can be used }
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST); { all of the above can be used }
  gluBuild2DMipmaps(GL_TEXTURE_2D, GL_RGBA, wid, hei, GL_RGBA, GL_UNSIGNED_BYTE, Addr(ColorData[0])); *)

  setlength(ColorData,0);
  result:=true;
end;

function LoadBMPFontTexture(var FileBit:Graphics.TBitmap; var DataRec:TRGBImageRec):boolean;
var //bit:TPicture;
ColorData:array of byte;
TransparentColor:array[0..2] of byte;
p:^Byte;
i,j,z,k,wid,hei:integer;
x:byte;
Palette:HPALETTE;
PaletteSize:integer;
LogSize: Integer;
LogPalette: PLogPalette;
vhsv:THSVColor;
vrgb:TRGBColorByte;
begin
  result:=false;
  if FileBit=nil then exit;

  wid:=Filebit.Width;
  hei:=Filebit.Height;
  SetLength(ColorData,wid*hei*4);

    case Filebit.PixelFormat of
      pf4bit:     //4 бита - 16 цветов
        begin
          //мы знаем, что при таком формате нужна палитра, поэтому загружаем её
          Palette:=Filebit.Palette;
          // определение размера палитры
          PaletteSize:=0;
          if GetObject(Palette, SizeOf(PaletteSize), @PaletteSize)=0 then exit;
          if PaletteSize=0 then exit;
          //задаём размер структуры
          LogSize := SizeOf(TLogPalette) + (PaletteSize - 1) * SizeOf(TPaletteEntry);
          //заполняем палитру
          GetMem(LogPalette, LogSize);
          try
            LogPalette^.palVersion:=$0300;
            LogPalette^.palNumEntries:=PaletteSize;
            GetPaletteEntries(Palette, 0, PaletteSize, LogPalette^.palPalEntry);

            //заполняем цвета по 2 цвета
            for i:=hei-1 downto 0 do
            begin
              p:=Filebit.ScanLine[i];
              if i=(hei-1) then
              begin
                x:=(p^) shr 4;
                TransparentColor[0]:=LogPalette^.palPalEntry[x].peRed;
                TransparentColor[1]:=LogPalette^.palPalEntry[x].peGreen;
                TransparentColor[2]:=LogPalette^.palPalEntry[x].peBlue;
              end;

              for j:=0 to wid-1 do
              begin
                z:=((hei-1-i)*wid*4)+j*4;  //индекс в общем цветовом массиве
                //вычисляем индекс в массиве
                x:=p^;
                if (j mod 2)=0 then x:=x shr 4
                else x:=x and ($F);
                //копируем палитру
                move(LogPalette^.palPalEntry[x],ColorData[z],3);
                //заполняем альфу
                if (CompareMem(@TransparentColor[0],@ColorData[z],3)) then ColorData[z+3]:=0
                else
                begin
                  vhsv:=RGBtoHSV(LogPalette^.palPalEntry[x].peRed,LogPalette^.palPalEntry[x].peGreen,LogPalette^.palPalEntry[x].peBlue);
                  k:=trunc(vhsv.v*255);
                  ColorData[z+3]:=k;
                  vhsv.v:=1;
                  vrgb:=HSVtoRGB(vhsv);
                  move(vrgb,ColorData[z],3);
                end;

                if (j mod 2)=1 then inc(p);
              end;
            end;
          finally
            FreeMem(LogPalette, LogSize);
          end;
        end;
      pf8bit:     //8 бита - 256 цветов
        begin
          //мы знаем, что при таком формате нужна палитра, поэтому загружаем её
          Palette:=Filebit.Palette;
          // определение размера палитры
          PaletteSize:=0;
          if GetObject(Palette, SizeOf(PaletteSize), @PaletteSize)=0 then exit;
          if PaletteSize=0 then exit;
          //задаём размер структуры
          LogSize := SizeOf(TLogPalette) + (PaletteSize - 1) * SizeOf(TPaletteEntry);
          //заполняем палитру
          GetMem(LogPalette, LogSize);
          try
            LogPalette^.palVersion:=$0300;
            LogPalette^.palNumEntries:=PaletteSize;
            GetPaletteEntries(Palette, 0, PaletteSize, LogPalette^.palPalEntry);

            //заполняем цвета по 2 цвета
            for i:=hei-1 downto 0 do
            begin
              p:=Filebit.ScanLine[i];
              if i=(hei-1) then
              begin
                x:=p^;
                TransparentColor[0]:=LogPalette^.palPalEntry[x].peRed;
                TransparentColor[1]:=LogPalette^.palPalEntry[x].peGreen;
                TransparentColor[2]:=LogPalette^.palPalEntry[x].peBlue;
              end;

              for j:=0 to wid-1 do
              begin
                z:=((hei-1-i)*wid*4)+j*4;  //индекс в общем цветовом массиве
                //вычисляем индекс в массиве
                x:=p^;
                //копируем палитру
                move(LogPalette^.palPalEntry[x],ColorData[z],3);
                //заполняем альфу
                if (CompareMem(@TransparentColor[0],@ColorData[z],3)) then ColorData[z+3]:=0
                else
                begin
                  vhsv:=RGBtoHSV(LogPalette^.palPalEntry[x].peRed,LogPalette^.palPalEntry[x].peGreen,LogPalette^.palPalEntry[x].peBlue);
                  k:=trunc(vhsv.v*255);
                  ColorData[z+3]:=k;
                  vhsv.v:=1;
                  vrgb:=HSVtoRGB(vhsv);
                  move(vrgb,ColorData[z],3);
                end;

                inc(p);
              end;
            end;
          finally
            FreeMem(LogPalette, LogSize);
          end;
        end;
      pf24bit:
        begin
          //тут палитра не нужна, все данные уже в битмапе
          for i:=hei-1 downto 0 do
          begin
            p:=Filebit.ScanLine[i];
            if i=(hei-1) then Move(p^,TransparentColor[0],3);

            for j:=0 to wid-1 do
            begin
              z:=((hei-1-i)*wid*4)+j*4;
              move(p^,ColorData[z],3);
              x:=ColorData[z];
              ColorData[z]:=ColorData[z+2];
              ColorData[z+2]:=x;
              //заполняем альфу
              if CompareMem(@TransparentColor[0],Addr(p^),3) then ColorData[z+3]:=0
              else
              begin
                vhsv:=RGBtoHSV(ColorData[z],ColorData[z+1],ColorData[z+2]);
                if vhsv.v<>1 then k:=trunc((vhsv.v)*255)
                else k:=trunc(vhsv.v*255);
                ColorData[z+3]:=k;
                vhsv.v:=1;
                vrgb:=HSVtoRGB(vhsv);
                move(vrgb,ColorData[z],3);
              end;

              inc(p,3);
            end;
          end;
        end;
      pf32bit:
        begin
          //палитра идёт с 8 битами альфы (игнорируем альфу, делаем свою по первому пикселю)
          for i:=hei-1 downto 0 do
          begin
            p:=Filebit.ScanLine[i];
            if i=(hei-1) then Move(p^,TransparentColor[0],3);

            for j:=0 to wid-1 do
            begin
              z:=((hei-1-i)*wid*4)+j*4;
              move(p^,ColorData[z],3);
              x:=ColorData[z];
              ColorData[z]:=ColorData[z+2];
              ColorData[z+2]:=x;
              //заполняем альфу
              if CompareMem(@TransparentColor[0],Addr(p^),3) then ColorData[z+3]:=0
              else
              begin
                vhsv:=RGBtoHSV(ColorData[z],ColorData[z+1],ColorData[z+2]);
                k:=trunc(vhsv.v*255);
                ColorData[z+3]:=k;
                vhsv.v:=1;
                vrgb:=HSVtoRGB(vhsv);
                move(vrgb,ColorData[z],3);
              end;

              inc(p,4);
            end;
          end;
        end;
      else exit;
    end;  //case bit.Bitmap.PixelFormat of

  DataRec.SizeX:=wid;
  DataRec.SizeY:=hei;
  DataRec.HasAlpha:=true;
  i:=DataRec.SizeX*DataRec.SizeY*4;
  GetMem(DataRec.data,i);
  Move(ColorData[0],pByteArray(DataRec.data)^[0],i);

  setlength(ColorData,0);
  result:=true;
end;

function LoadJPEGTexture(Filename:string; var DataRec:TRGBImageRec; Transparent:boolean):boolean;
var JPG:TJPEGImage;
bmp:Graphics.TBitmap;
ColorData:Array of LongWord;
W, Width:Integer;
H, Height:Integer;
Line:^LongWord;
C, TransparentColor, TransMask:LongWord;
begin
  result:=false;
  if FileExists(Filename)=false then exit;

  JPG:=TJPEGImage.Create;
  try
    JPG.LoadFromFile(Filename);

    BMP:=Graphics.TBitmap.Create;
    try
      BMP.pixelformat:=pf32bit;
      BMP.width:=JPG.width;
      BMP.height:=JPG.height;
      BMP.canvas.draw(0,0,JPG);  // Copy the JPEG onto the Bitmap

      Width :=BMP.Width;
      Height :=BMP.Height;
      SetLength(ColorData, Width*Height);
      TransparentColor:=0;

      For H:=0 to Height-1 do
      Begin
        Line:=BMP.scanline[Height-H-1];   // flip JPEG
        if h=0 then TransparentColor:=Line^ and $FFFFFF;

        For W:=0 to Width-1 do
        Begin
          c:=Line^ and $FFFFFF; // Need to do a color swap
          if Transparent then
          begin
            if TransparentColor=c then TransMask:=0
            else TransMask:=$FF000000;
          end
          else TransMask:=$FF000000;
          ColorData[W+(H*Width)] :=(((c and $FF) shl 16)+(c shr 16)+(c and $FF00)) or TransMask;  // 4 channel.
          inc(Line);
        End;
      End;
    finally
      BMP.Free;
    end;
  finally
    JPG.Free;
  end;

  DataRec.SizeX:=Width;
  DataRec.SizeY:=Height;
  DataRec.HasAlpha:=Transparent;
  w:=DataRec.SizeX*DataRec.SizeY*4;
  GetMem(DataRec.data,w);
  Move(ColorData[0],pByteArray(DataRec.data)^[0],w);


  //здесь у нас должен быть правильно заполненый массив ColorData с альфа каналом
  //готовим текстуру
  (*glGenTextures(1, @Texture);
  glBindTexture(GL_TEXTURE_2D, Texture);
  glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);  {Texture blends with object background}
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST); { only first two can be used }
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST); { all of the above can be used }
  gluBuild2DMipmaps(GL_TEXTURE_2D, GL_RGBA, Width, Height, GL_RGBA, GL_UNSIGNED_BYTE, Addr(ColorData[0])); *)

  setlength(ColorData,0);
  result:=true;
end;

function LoadPNGTexture(Filename:string; var DataRec:TRGBImageRec; Transparent:boolean):boolean;
var png:TPNGObject;
Width,Height,W,H,X:integer;
alphadata:PByteArray;
//data:pTripleArray;
data:pByteArray;
ColorData:Array of LongWord;
TransColor:array[0..2] of byte;
C:LongWord;
x_alpha:byte;
Palette:HPALETTE;
PaletteSize:integer;
LogSize: Integer;
LogPalette: PLogPalette;
begin
  result:=false;
  if FileExists(Filename)=false then exit;

  png:=TPNGObject.Create;
  try
    png.LoadFromFile(Filename);
    Width:=png.Width;
    Height:=png.Height;
    {if (png.Header.BitDepth<>16)and(png.Header.BitDepth<>8) then exit;
    if (png.Header.ColorType<>COLOR_RGB)and(png.Header.ColorType<>COLOR_RGBALPHA) then exit;
    if (png.Header.BitDepth=8)and(png.Header.ColorType<>COLOR_PALETTE) then exit;  }
    setlength(ColorData,Width*Height);
      
    case png.Header.ColorType of
      COLOR_PALETTE:
        begin
          //мы знаем, что при таком формате нужна палитра, поэтому загружаем её
          Palette:=png.Palette;
          // определение размера палитры
          PaletteSize:=0;
          if GetObject(Palette, SizeOf(PaletteSize), @PaletteSize)=0 then exit;
          if PaletteSize=0 then exit;
          //задаём размер структуры
          LogSize := SizeOf(TLogPalette) + (PaletteSize - 1) * SizeOf(TPaletteEntry);
          //заполняем палитру
          GetMem(LogPalette, LogSize);
          try
            LogPalette^.palVersion:=$0300;
            LogPalette^.palNumEntries:=PaletteSize;
            GetPaletteEntries(Palette, 0, PaletteSize, LogPalette^.palPalEntry);

            for H:=0 to Height-1 do
            begin
              data:=png.Scanline[Height-1-H];
              alphadata:=png.AlphaScanline[Height-1-H];
              if (Transparent)and(h=0) then TransColor[0]:=data^[0];

              for W:=0 to Width-1 do
              begin
                x:=data^[w];
                c:=0;
                move(LogPalette^.palPalEntry[x],c,3);

                if Transparent then
                begin
                  if alphadata<>nil then x_alpha:=alphadata^[w]
                  else
                  begin
                    if data^[w]=TransColor[0] then x_alpha:=0
                    else x_alpha:=$FF;
                  end;
                  ColorData[W+(H*Width)]:=c or (x_alpha shl 24);
                end
                else ColorData[W+(H*Width)]:=c or $FF000000;
              end;
            end;
          finally
            FreeMem(LogPalette, LogSize);
          end;
        end;
      COLOR_RGB:
        begin
          for H:=0 to Height-1 do
          begin
            data:=png.Scanline[Height-1-H];
            if (Transparent)and(H=0) then Move(data^[0],TransColor,3);

            for W:=0 to Width-1 do
            begin
              x:=W+(H*Width);
              Move(data^[w*3],C,3);

              if Transparent then
              begin
                if CompareMem(@TransColor,@data^[w*3],3)=true then ColorData[x]:=((c and $FF) shl 16)or(c and $FF00)or((c and $FF0000)shr 16) and $FFFFFF
                else ColorData[x]:=((c and $FF) shl 16)or(c and $FF00)or((c and $FF0000)shr 16) or $FF000000;
              end
              else ColorData[x]:=((c and $FF) shl 16)or(c and $FF00)or((c and $FF0000)shr 16) or $FF000000;
            end;
          end;
        end;
      COLOR_RGBALPHA:
        begin
          for H:=0 to Height-1 do
          begin
            data:=png.Scanline[Height-1-H];
            if Transparent then alphadata:=png.AlphaScanline[Height-1-H];

            for W:=0 to Width-1 do
            begin
              x:=W+(H*Width);
              Move(data^[w*3],C,3);

              if Transparent then
                ColorData[x]:=((c and $FF) shl 16)or(c and $FF00)or((c and $FF0000)shr 16) or (alphadata^[w] shl 24)
              else
                ColorData[x]:=((c and $FF) shl 16)or(c and $FF00)or((c and $FF0000)shr 16) or $FF000000;
            end;
          end;
        end;
    end;

  finally
    png.Free;
  end;

  DataRec.SizeX:=Width;
  DataRec.SizeY:=Height;
  DataRec.HasAlpha:=Transparent;
  w:=DataRec.SizeX*DataRec.SizeY*4;
  GetMem(DataRec.data,w);
  Move(ColorData[0],pByteArray(DataRec.data)^[0],w);

  //здесь у нас должен быть правильно заполненый массив ColorData с альфа каналом
  //готовим текстуру
  (*glGenTextures(1, @Texture);
  glBindTexture(GL_TEXTURE_2D, Texture);
  glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);  {Texture blends with object background}
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST); { only first two can be used }
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST); { all of the above can be used }
  gluBuild2DMipmaps(GL_TEXTURE_2D, GL_RGBA, Width, Height, GL_RGBA, GL_UNSIGNED_BYTE, Addr(ColorData[0]));
  //glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, Width, Height, 0, GL_RGBA, GL_UNSIGNED_BYTE, Addr(ColorData[0]));  *)
 
  setlength(ColorData,0);
  result:=true;
end;

function LoadTexture(Filename: String; var Texture: GLuint; Transparent:boolean; out Width:integer; out Height:integer):boolean;
var Rec:TRGBImageRec;
begin
  result:=false;
  Rec.SizeX:=0;
  Rec.SizeY:=0;

  case AnsiIndexStr(UpperCase(ExtractFileExt(Filename)),['.BMP','.JPG','.JPEG','.PNG']) of
    0:begin
        result:=LoadBMPTexture(Filename, Rec, Transparent);

        if Result then
        begin
          glGenTextures(1, @Texture);
          glBindTexture(GL_TEXTURE_2D, Texture);
          glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);  {Texture blends with object background}
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
          gluBuild2DMipmaps(GL_TEXTURE_2D, GL_RGBA, Rec.SizeX, Rec.SizeY, GL_RGBA, GL_UNSIGNED_BYTE, Rec.data);
        end;

        if (Rec.SizeX*Rec.SizeY)<>0 then FreeMem(Rec.data,Rec.SizeX*Rec.SizeY*4);
        Width:=Rec.SizeX;
        Height:=Rec.SizeY;
      end;
    1,2:begin
          result:=LoadJPEGTexture(Filename, Rec, Transparent);

          if Result then
          begin
            glGenTextures(1, @Texture);
            glBindTexture(GL_TEXTURE_2D, Texture);
            glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);  {Texture blends with object background}
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
            gluBuild2DMipmaps(GL_TEXTURE_2D, GL_RGBA, Rec.SizeX, Rec.SizeY, GL_RGBA, GL_UNSIGNED_BYTE, Rec.data);
          end;

          if (Rec.SizeX*Rec.SizeY)<>0 then FreeMem(Rec.data,Rec.SizeX*Rec.SizeY*4);
          Width:=Rec.SizeX;
          Height:=Rec.SizeY;
        end;
    3:begin
        result:=LoadPNGTexture(Filename, Rec, Transparent);

        if Result then
        begin
          glGenTextures(1, @Texture);
          glBindTexture(GL_TEXTURE_2D, Texture);
          glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);  {Texture blends with object background}
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
          gluBuild2DMipmaps(GL_TEXTURE_2D, GL_RGBA, Rec.SizeX, Rec.SizeY, GL_RGBA, GL_UNSIGNED_BYTE, Rec.data);
        end;

        if (Rec.SizeX*Rec.SizeY)<>0 then FreeMem(Rec.data,Rec.SizeX*Rec.SizeY*4);
        Width:=Rec.SizeX;
        Height:=Rec.SizeY;
      end;
    else result:=false;
  end;
end;

end.
