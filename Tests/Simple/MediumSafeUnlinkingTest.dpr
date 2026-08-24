program MediumSafeUnlinkingTest;

{$IFNDEF UNIX}
{$APPTYPE CONSOLE}
{$ENDIF}

{The test-only entry point this program calls is compiled into FastMM4.pas
 only when MediumSafeUnlinkingTest is defined, and a define written here does
 not reach that unit: a conditional symbol is local to the module that
 declares it. The symbol has to come from the command line, as
 -dMediumSafeUnlinkingTest for FreePascal or -DMediumSafeUnlinkingTest for
 Delphi, which is what the CI steps pass. Without it the build fails at the
 call below rather than silently testing nothing.}
{$IFNDEF MediumSafeUnlinkingTest}
{Delphi 4 and 5 have no $MESSAGE directive and ignore this line, so on those
 compilers a build without the symbol still fails, at the unresolved call
 rather than here.}
{$MESSAGE ERROR 'Build this program with -dMediumSafeUnlinkingTest'}
{$ENDIF}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  FastMM4 in '..\..\FastMM4.pas',
  FastMM4Messages in '..\..\FastMM4Messages.pas',
  {SysUtils is load-bearing here rather than a convenience: it declares
   Exception and installs the RTL hook that turns a hardware fault into a
   catchable Pascal exception, which is what lets a rejected vector be reported
   instead of ending the process.}
  SysUtils;

type
  {A byte pointer this program declares for itself. PByte cannot be used:
   Windows declares it as PAnsiChar, following the Win32 headers, and that
   declaration shadows the one in System for any unit that uses Windows, so on
   Delphi 7 assigning a Byte through PByte fails with "Incompatible types:
   'Char' and 'Byte'".}
  PTestByte = ^Byte;

var
  Failures: Integer;

procedure Pass(const AName: string);
begin
  WriteLn('[PASS] ', AName);
end;

procedure Fail(const AName, AReason: string);
begin
  Inc(Failures);
  WriteLn('[FAIL] ', AName, ': ', AReason);
end;

procedure TestValidUnlink;
begin
  try
    if FastMMTestMediumSafeUnlinking(0) then
      Fail('valid medium free-list unlink', 'valid list was rejected')
    else
      Pass('valid medium free-list unlink');
  except
    on E: Exception do
      Fail('valid medium free-list unlink', E.ClassName + ': ' + E.Message);
  end;
end;

procedure TestRejectedCorruption(AMode: Integer; const AName: string);
begin
  try
    if FastMMTestMediumSafeUnlinking(AMode) then
      Pass(AName)
    else
      Fail(AName, 'corruption was accepted');
  except
    on E: Exception do
      Fail(AName, 'unexpected exception ' + E.ClassName + ': ' + E.Message);
  end;
end;

procedure TestNormalMediumTraffic;
const
  Count = 256;
  Rounds = 50;
var
  Blocks: array[0..Count - 1] of Pointer;
  I,
  RoundNumber: Integer;
begin
  for I := 0 to Count - 1 do
    Blocks[I] := nil;
  try
    for RoundNumber := 1 to Rounds do
    begin
      for I := 0 to Count - 1 do
      begin
        GetMem(Blocks[I], 4096 + (I mod 16) * 256);
        PTestByte(Blocks[I])^ := Byte(I);
      end;
      for I := 0 to Count - 1 do
      begin
        FreeMem(Blocks[I]);
        Blocks[I] := nil;
      end;
    end;
    Pass('normal medium traffic');
  except
    on E: Exception do
      Fail('normal medium traffic', E.ClassName + ': ' + E.Message);
  end;
  for I := 0 to Count - 1 do
    if Blocks[I] <> nil then
      FreeMem(Blocks[I]);
end;

begin
  Failures := 0;
  TestRejectedCorruption(3, 'foreign next pointer ownership');
  TestRejectedCorruption(4, 'foreign previous pointer ownership');
  TestRejectedCorruption(5, 'readable non-node pointer ownership');
  TestRejectedCorruption(6, 'null next pointer ownership');
  TestRejectedCorruption(7, 'misaligned previous pointer ownership');
  TestValidUnlink;
  TestRejectedCorruption(1, 'corrupt previous reciprocal link');
  TestRejectedCorruption(2, 'corrupt next reciprocal link');
  TestNormalMediumTraffic;
  if Failures = 0 then
  begin
    WriteLn('ALL TESTS PASSED!');
    ExitCode := 0;
  end
  else
  begin
    WriteLn('TESTS FAILED: ', Failures);
    ExitCode := 1;
  end;
end.
