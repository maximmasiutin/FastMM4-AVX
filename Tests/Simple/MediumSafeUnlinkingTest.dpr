program MediumSafeUnlinkingTest;

{$IFNDEF UNIX}
{$APPTYPE CONSOLE}
{$ENDIF}

{$DEFINE MediumSafeUnlinkingTest}

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
        PByte(Blocks[I])^ := Byte(I);
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
