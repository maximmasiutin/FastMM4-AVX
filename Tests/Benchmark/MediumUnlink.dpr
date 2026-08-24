program MediumUnlink;

{$IFNDEF UNIX}
{$APPTYPE CONSOLE}
{$ENDIF}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  FastMM4 in '..\..\FastMM4.pas',
  FastMM4Messages in '..\..\FastMM4Messages.pas',
  {$IFDEF FPC}
  SysUtils;
  {$ELSE}
  System.SysUtils;
  {$ENDIF}

const
  BlockSize = 8192;
  Iterations = 20000000;

var
  FirstFree,
  FirstGuard,
  SecondFree,
  SecondGuard,
  Reused: Pointer;
  StartTicks,
  Elapsed: QWord;
  I: Integer;

begin
  FirstFree := nil;
  FirstGuard := nil;
  SecondFree := nil;
  SecondGuard := nil;
  Reused := nil;
  GetMem(FirstFree, BlockSize);
  GetMem(FirstGuard, BlockSize);
  GetMem(SecondFree, BlockSize);
  GetMem(SecondGuard, BlockSize);
  FreeMem(FirstFree);
  FreeMem(SecondFree);
  StartTicks := GetTickCount64;
  for I := 1 to Iterations do
  begin
    GetMem(Reused, BlockSize);
    FreeMem(Reused);
  end;
  Elapsed := GetTickCount64 - StartTicks;
  GetMem(SecondFree, BlockSize);
  GetMem(FirstFree, BlockSize);
  FreeMem(FirstFree);
  FreeMem(FirstGuard);
  FreeMem(SecondFree);
  FreeMem(SecondGuard);
  WriteLn('medium_unlinks=', Iterations, ' elapsed_ms=', Elapsed);
end.
