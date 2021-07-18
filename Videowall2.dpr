program Videowall2;

{$R 'monitor_ico.res' 'monitor_ico.rc'}
{$R 'videowall_ver.res' 'videowall_ver.rc'}

uses
  FastMM4,
  mainUnit in 'mainUnit.pas',
  TexturesTest in 'TexturesTest.pas',
  fontsUnit in 'fontsUnit.pas',
  dataWorkUnit in 'dataWorkUnit.pas';

begin
  WinMain(hInstance,hPrevInst,CmdLine,CmdShow);
end.
