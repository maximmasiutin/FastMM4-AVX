program MediumUnlink;

{$IFNDEF UNIX}
{$APPTYPE CONSOLE}
{$ENDIF}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  {$IFNDEF FPC}
  Windows,
  {$ENDIF}
  FastMM4 in '..\..\FastMM4.pas',
  FastMM4Messages in '..\..\FastMM4Messages.pas',
  {SysUtils is here for GetTickCount64 under FreePascal. The Delphi branch
   takes the reading from Windows instead, which is why that unit is used
   above.}
  SysUtils;

const
  BlockSize = 8192;
  Iterations = 20000000;

{Elapsed milliseconds. FreePascal has GetTickCount64 in SysUtils on every
 target this benchmark builds for; the Delphi versions the allocator still
 supports do not declare it, so the same number is computed from the system
 clock, which every one of them does have.}
function TickCountMs: Int64;
{$IFDEF FPC}
begin
  Result := Int64(GetTickCount64);
end;
{$ELSE}
var
  FileTimeNow: TFileTime;
begin
  {GetSystemTimeAsFileTime counts 100-nanosecond intervals, so ten thousand of
   them are one millisecond. TFileTime is two 32-bit halves and the cast reads
   them as the one 64-bit quantity they represent. The reading is wall clock
   rather than monotonic, which is enough here: the benchmark reports a single
   span, and only a clock adjustment during the run would disturb it.}
  GetSystemTimeAsFileTime(FileTimeNow);
  Result := Int64(FileTimeNow) div 10000;
end;
{$ENDIF}

var
  FirstFree,
  FirstGuard,
  SecondFree,
  SecondGuard,
  Reused: Pointer;
  StartTicks,
  Elapsed: Int64;
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
  StartTicks := TickCountMs;
  for I := 1 to Iterations do
  begin
    GetMem(Reused, BlockSize);
    FreeMem(Reused);
  end;
  Elapsed := TickCountMs - StartTicks;
  GetMem(SecondFree, BlockSize);
  GetMem(FirstFree, BlockSize);
  FreeMem(FirstFree);
  FreeMem(FirstGuard);
  FreeMem(SecondFree);
  FreeMem(SecondGuard);
  WriteLn('medium_unlinks=', Iterations, ' elapsed_ms=', Elapsed);
end.
