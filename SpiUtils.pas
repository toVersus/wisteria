unit SpiUtils;

interface

uses
  Winapi.Windows, System.Classes, System.SysUtils, Vcl.Forms, Vcl.Graphics;

function IsLoadableBySpi(Ext: string): Boolean;
procedure LoadBySpi(FileName: string; Src: TBitmap);
procedure DumpSpiMapInfo();
{$IFNDEF WIN64}
function IsSavableByXpi(Ext: string): Boolean;
procedure SaveByXpi(FileName: string; Src: TBitmap);
procedure DumpXpiMapInfo();
{$ENDIF}

implementation

type
  {$IFNDEF WIN64}
  TPictureInfo = packed record
    Left: Longint;
    Top: Longint;
    Width: Longint;
    Height: Longint;
    XDensity: Word;
    YDensitiy: Word;
    ColorDepth: SmallInt;
    Info: HLOCAL;
  end;

  TProgressCallback = function(nNum, nDenom: Integer; lData: Longint): Integer; stdcall;
  TGetPluginInfo = function(InfoNo: Longint; Buf: PAnsiChar; BufLen: Longint): Integer; stdcall;
  TGetPicture = function(Buf: PAnsiChar; Len: Longint; Flag: Longword; var HBInfo: HLOCAL; var HBm: HLOCAL; ProgressCallback: TProgressCallback; lData: Longint): Integer; stdcall;
  TCreatePicture = function(FilePath: PAnsiChar; Flag: Longword; HBInfo: PHANDLE; HBm: PHANDLE; var PictureInfo: TPictureInfo; ProgressCallback: TProgressCallback; lData: Longint): Integer; stdcall;
  {$ELSE}
  TProgressCallback = function(nNum, nDenom: Integer; lData: LONG_PTR): Integer; stdcall;
  TGetPluginInfo = function(InfoNo: Integer; Buf: PAnsiChar; BufLen: Integer): Integer; stdcall;
  TGetPicture = function(Buf: PAnsiChar; Len: LONG_PTR; Flag: Cardinal; var HBInfo: THandle; var HBm: THandle; ProgressCallback: TProgressCallback; lData: LONG_PTR): Integer; stdcall;
  {$ENDIF}

const
  {$IFNDEF WIN64}
  SpiFileExt = 'spi';
  XpiFileExt = 'xpi';
  {$ELSE}
  SpiFileExt = 'sph';
  {$ENDIF}

var
  SpiMapInfo: TStrings;
  {$IFNDEF WIN64}
  XpiMapInfo: TStrings;
  {$ENDIF}

function IsLoadableBySpi(Ext: string): Boolean;
begin
  Result := SpiMapInfo.IndexOfName(Ext) <> -1;
end;

{$IFNDEF WIN64}
function IsSavableByXpi(Ext: string): Boolean;
begin
  Result := XpiMapInfo.IndexOfName(Ext) <> -1;
end;
{$ENDIF}

procedure GetPluginList(Dir, Pattern: string; FileList: TStrings);
var
  Handle: THandle;
  Data: TWin32FindData;
begin
  Handle := Winapi.Windows.FindFirstFile(PChar(Dir + Pattern), Data);
  if Handle = INVALID_HANDLE_VALUE then Exit;
  FileList.Add(Dir + Data.cFileName);
  while Winapi.Windows.FindNextFile(Handle, Data) = True do
  begin
    FileList.Add(Dir + Data.cFileName);
  end;
  Winapi.Windows.FindClose(Handle);
end;

function GetPluginApiVersion(GetPluginInfo: TGetPluginInfo): string;
var
  A: AnsiString;
begin
  SetLength(A, 5);
  GetPluginInfo(0, PAnsiChar(A), 5);
  SetLength(A, 4);
  Result := string(A);
end;

function GetFilterPatterns(GetPluginInfo: TGetPluginInfo): string;
const
  BufSize = 256;
var
  A: AnsiString;
begin
  SetLength(A, BufSize);
  GetPluginInfo(2, PAnsiChar(A), BufSize);
  SetLength(A, StrLen(PAnsiChar(A)));
  Result := string(A);
end;

function PatternToExt(Pattern: string): string;
begin
  Result := Trim(StringReplace(Pattern, '*.', '', [rfReplaceAll]));
end;

procedure RegisterFileExts(PluginFileName: string; FilterPatterns: string; MapInfo: TStrings);
var
  I: Cardinal;
  List: TStringList;
begin
  List := TStringList.Create;
  try
    List.Text := StringReplace(FilterPatterns, ';', #13#10, [rfReplaceAll]);
    for I := 0 to List.Count - 1 do
    begin
      MapInfo.Values[PatternToExt(List.Strings[I])] := PluginFileName;
    end;
  finally
    List.Free;
  end;
end;

procedure AddPlugin(PluginFileName, PluginApiVersion: string; MapInfo: TStrings);
var
  HDLL: HINST;
  GetPluginInfo: TGetPluginInfo;
const
  BufSize = 256;
begin
  HDLL := LoadLibrary(PChar(PluginFileName));
  try
    GetPluginInfo := GetProcAddress(HDLL, 'GetPluginInfo');
    if GetPluginApiVersion(GetPluginInfo) = PluginApiVersion then
    begin
      RegisterFileExts(PluginFileName, GetFilterPatterns(GetPluginInfo), MapInfo);
    end;
  finally
    FreeLibrary(HDLL);
  end;
end;

procedure InitPluginRuntime(FilterPattern, PluginApiVersion: string; MapInfo: TStrings);
var
  I: Integer;
  PluginList: TStrings;
begin
  PluginList := TStringList.Create;
  try
    GetPluginList(ExtractFilePath(Application.ExeName), FilterPattern, PluginList);
    for I := 0 to PluginList.Count - 1 do
    begin
      AddPlugin(PluginList.Strings[I], PluginApiVersion, MapInfo);
    end;
  finally
    PluginList.Free;
  end;
end;

procedure InitSpi();
begin
  InitPluginRuntime('*.' + SpiFileExt, '00IN', SpiMapInfo);
end;

{$IFNDEF WIN64}
procedure InitXpi();
begin
  InitPluginRuntime('*.' + XpiFileExt, 'T0XN', XpiMapInfo);
end;
{$ENDIF}

procedure LoadBySpi(FileName: string; Src: TBitmap);
var
  pHBInfo, pHBm: HLOCAL;
  BitmapInfo: ^TBitmapInfo;
  Ext: string;
  HDLL: HINST;
  GetPicture: TGetPicture;
begin
  Ext := ExtractFileExt(FileName);
  Ext := Copy(Ext, 2, Length(Ext));
  if not IsLoadableBySpi(Ext) then Exit;

  HDLL := LoadLibrary(PChar(SpiMapInfo.Values[Ext]));
  try
    GetPicture := GetProcAddress(HDLL, 'GetPicture');
    if GetPicture(PAnsiChar(AnsiString(FileName)), 0, 0, pHBInfo, pHBm, nil, 0) <> 0 then Exit;
    BitmapInfo := LocalLock(pHBInfo);
    Src.Width := BitmapInfo^.bmiHeader.biWidth;
    Src.Height := BitmapInfo^.bmiHeader.biHeight;
    Src.PixelFormat := pf24bit;
    SetDIBits(0, Src.Handle, 0, BitmapInfo^.bmiHeader.biHeight, LocalLock(pHBm), BitmapInfo^, DIB_RGB_COLORS);
    LocalUnlock(pHBm);
    LocalUnlock(pHBInfo);
    LocalFree(pHBInfo);
    LocalFree(pHBm);
  finally
    FreeLibrary(HDLL);
  end;
end;

{$IFNDEF WIN64}
procedure SaveByXpi(FileName: string; Src: TBitmap);
var
  Ext: string;
  HDLL: HINST;
  PictureInfo: TPictureInfo;
  DS: TDIBSECTION;
  CreatePicture: TCreatePicture;
begin
  Ext := ExtractFileExt(FileName);
  Ext := Copy(Ext, 2, Length(Ext));
  if not IsSavableByXpi(Ext) then Exit;

  HDLL := LoadLibrary(PChar(XpiMapInfo.Values[Ext]));
  try
    CreatePicture := GetProcAddress(HDLL, 'CreatePicture');
    ZeroMemory(@PictureInfo, SizeOf(PictureInfo));
    GetObject(Src.Handle, sizeof(DIBSECTION), @DS);
    CreatePicture(PAnsiChar(AnsiString(FileName)), 1, @DS.dsBmih, DS.dsBm.bmBits, PictureInfo, nil, 0);
  finally
    FreeLibrary(HDLL);
  end;
end;
{$ENDIF}

procedure DumpMapInfo(MapInfo: TStrings; PluginFileExt: string);
begin
  MapInfo.SaveToFile(Format('%s\%s.ini', [ExtractFilePath(Application.ExeName), PluginFileExt]));
end;

procedure DumpSpiMapInfo();
begin
  DumpMapInfo(SpiMapInfo, SpiFileExt);
end;

{$IFNDEF WIN64}
procedure DumpXpiMapInfo();
begin
  DumpMapInfo(XpiMapInfo, XpiFileExt);
end;
{$ENDIF}

initialization
  SpiMapInfo := TStringList.Create;
  InitSpi();
  {$IFNDEF WIN64}
  XpiMapInfo := TStringList.Create;
  InitXpi();
  {$ENDIF}

finalization
  SpiMapInfo.Free;
  {$IFNDEF WIN64}
  XpiMapInfo.Free;
  {$ENDIF}

end.
