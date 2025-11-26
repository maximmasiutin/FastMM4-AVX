program IntegerOverflowTest;

{$IFNDEF UNIX}
{$APPTYPE CONSOLE}
{$ENDIF}

uses
  FastMM4 in '../../FastMM4.pas',
  FastMM4Messages in '../../FastMM4Messages.pas';

var
  TestsPassed: Integer;
  TestsFailed: Integer;
  TestsTotal: Integer;
  Is64Bit: Boolean;

procedure WriteHex(Value: NativeUInt);
var
  Digits: array[0..15] of Char;
  I, Len: Integer;
  D: NativeUInt;
begin
  {Convert to hex without SysUtils}
  Len := 0;
  repeat
    D := Value and $F;
    if D < 10 then
      Digits[Len] := Char(Ord('0') + D)
    else
      Digits[Len] := Char(Ord('A') + D - 10);
    Inc(Len);
    Value := Value shr 4;
  until Value = 0;
  {Write in reverse order}
  for I := Len - 1 downto 0 do
    Write(Digits[I]);
end;

procedure LogTest(const TestName: string; Passed: Boolean; const Details: string);
begin
  Inc(TestsTotal);
  if Passed then
  begin
    Inc(TestsPassed);
    WriteLn('[PASS] ', TestName);
    if Details <> '' then
      WriteLn('       ', Details);
  end
  else
  begin
    Inc(TestsFailed);
    WriteLn('[FAIL] ', TestName);
    if Details <> '' then
      WriteLn('       ERROR: ', Details);
  end;
end;

procedure TestNormalAllocation;
var
  P: Pointer;
begin
  WriteLn;
  WriteLn('=== Test 1: Normal Large Allocation ===');

  P := GetMem(1024 * 1024);
  if P <> nil then
  begin
    Write('[PASS] Normal 1MB allocation - Pointer: $');
    WriteHex(NativeUInt(P));
    WriteLn;
    Inc(TestsTotal);
    Inc(TestsPassed);
    FreeMem(P);
    LogTest('Normal 1MB deallocation', True, '');
  end
  else
  begin
    LogTest('Normal 1MB allocation', False, 'GetMem returned nil unexpectedly');
  end;
end;

procedure TestOverflowAllocation64;
var
  P: Pointer;
  TestSize: NativeUInt;
begin
  WriteLn;
  WriteLn('=== Test 2: Integer Overflow Attack (64-bit) ===');

  {64-bit overflow test value}
  TestSize := NativeUInt($FFFFFFFFFFFF0000);
  Write('Attempting to allocate: $');
  WriteHex(TestSize);
  WriteLn(' bytes');
  WriteLn('This value should cause integer overflow in size calculation');

  P := GetMem(TestSize);
  if P <> nil then
  begin
    Write('[FAIL] Overflow protection - VULNERABILITY: GetMem returned pointer $');
    WriteHex(NativeUInt(P));
    WriteLn;
    Inc(TestsTotal);
    Inc(TestsFailed);
    FreeMem(P);
  end
  else
  begin
    LogTest('Overflow protection', True,
      'GetMem correctly returned nil for overflow size');
  end;

  {Second 64-bit overflow test}
  WriteLn;
  TestSize := NativeUInt($FFFFFFFFFFEFFFA9);
  Write('Attempting to allocate: $');
  WriteHex(TestSize);
  WriteLn(' bytes');
  WriteLn('This value wraps to near-zero after adding overhead');

  P := GetMem(TestSize);
  if P <> nil then
  begin
    Write('[FAIL] Overflow protection #2 - VULNERABILITY: GetMem returned pointer $');
    WriteHex(NativeUInt(P));
    WriteLn;
    Inc(TestsTotal);
    Inc(TestsFailed);
    FreeMem(P);
  end
  else
  begin
    LogTest('Overflow protection #2', True,
      'GetMem correctly returned nil');
  end;

  {Third 64-bit overflow test}
  WriteLn;
  TestSize := NativeUInt($FFFFFFFFFFF00000);
  Write('Attempting to allocate: $');
  WriteHex(TestSize);
  WriteLn(' bytes');

  P := GetMem(TestSize);
  if P <> nil then
  begin
    Write('[FAIL] Overflow protection #3 - VULNERABILITY: GetMem returned pointer $');
    WriteHex(NativeUInt(P));
    WriteLn;
    Inc(TestsTotal);
    Inc(TestsFailed);
    FreeMem(P);
  end
  else
  begin
    LogTest('Overflow protection #3', True,
      'GetMem correctly returned nil');
  end;
end;

procedure TestOverflowAllocation32;
var
  P: Pointer;
  TestSize: NativeUInt;
begin
  WriteLn;
  WriteLn('=== Test 2: Integer Overflow Attack (32-bit) ===');

  {32-bit overflow test value}
  TestSize := NativeUInt($FFFF0000);
  Write('Attempting to allocate: $');
  WriteHex(TestSize);
  WriteLn(' bytes');
  WriteLn('This value should cause integer overflow in size calculation');

  P := GetMem(TestSize);
  if P <> nil then
  begin
    Write('[FAIL] Overflow protection - VULNERABILITY: GetMem returned pointer $');
    WriteHex(NativeUInt(P));
    WriteLn;
    Inc(TestsTotal);
    Inc(TestsFailed);
    FreeMem(P);
  end
  else
  begin
    LogTest('Overflow protection', True,
      'GetMem correctly returned nil for overflow size');
  end;

  {Second 32-bit overflow test}
  WriteLn;
  TestSize := NativeUInt($FFFEFFA9);
  Write('Attempting to allocate: $');
  WriteHex(TestSize);
  WriteLn(' bytes');
  WriteLn('This value wraps to near-zero after adding overhead');

  P := GetMem(TestSize);
  if P <> nil then
  begin
    Write('[FAIL] Overflow protection #2 - VULNERABILITY: GetMem returned pointer $');
    WriteHex(NativeUInt(P));
    WriteLn;
    Inc(TestsTotal);
    Inc(TestsFailed);
    FreeMem(P);
  end
  else
  begin
    LogTest('Overflow protection #2', True,
      'GetMem correctly returned nil');
  end;

  {Third 32-bit overflow test}
  WriteLn;
  TestSize := NativeUInt($FFFF8000);
  Write('Attempting to allocate: $');
  WriteHex(TestSize);
  WriteLn(' bytes');

  P := GetMem(TestSize);
  if P <> nil then
  begin
    Write('[FAIL] Overflow protection #3 - VULNERABILITY: GetMem returned pointer $');
    WriteHex(NativeUInt(P));
    WriteLn;
    Inc(TestsTotal);
    Inc(TestsFailed);
    FreeMem(P);
  end
  else
  begin
    LogTest('Overflow protection #3', True,
      'GetMem correctly returned nil');
  end;
end;

procedure TestBoundaryConditions;
var
  P: Pointer;
  Size: NativeUInt;
begin
  WriteLn;
  WriteLn('=== Test 3: Boundary Conditions ===');

  Size := High(NativeUInt);
  Write('Attempting to allocate: $');
  WriteHex(Size);
  WriteLn(' bytes (High(NativeUInt))');
  P := GetMem(Size);
  if P <> nil then
  begin
    Write('[FAIL] High(NativeUInt) allocation - VULNERABILITY: got pointer $');
    WriteHex(NativeUInt(P));
    WriteLn;
    Inc(TestsTotal);
    Inc(TestsFailed);
    FreeMem(P);
  end
  else
  begin
    LogTest('High(NativeUInt) allocation', True, 'Correctly returned nil');
  end;

  Size := High(NativeUInt) - 1;
  Write('Attempting to allocate: $');
  WriteHex(Size);
  WriteLn(' bytes (High(NativeUInt)-1)');
  P := GetMem(Size);
  if P <> nil then
  begin
    Write('[FAIL] High(NativeUInt)-1 allocation - VULNERABILITY: got pointer $');
    WriteHex(NativeUInt(P));
    WriteLn;
    Inc(TestsTotal);
    Inc(TestsFailed);
    FreeMem(P);
  end
  else
  begin
    LogTest('High(NativeUInt)-1 allocation', True, 'Correctly returned nil');
  end;
end;

var
  PassPercent, FailPercent: Integer;

begin
  TestsPassed := 0;
  TestsFailed := 0;
  TestsTotal := 0;

  {Detect platform at runtime}
  Is64Bit := SizeOf(Pointer) = 8;

  WriteLn('================================================================================');
  WriteLn('FastMM4-AVX Integer Overflow Vulnerability Test Suite');
  WriteLn('================================================================================');
  if Is64Bit then
    WriteLn('Platform: 64-bit')
  else
    WriteLn('Platform: 32-bit');
  {$IFDEF UNIX}
  WriteLn('OS: Linux/Unix');
  {$ELSE}
  WriteLn('OS: Windows');
  {$ENDIF}
  WriteLn('Purpose: Detect CVE-2017-17426 class integer overflow vulnerabilities');
  WriteLn('================================================================================');

  TestNormalAllocation;

  if Is64Bit then
    TestOverflowAllocation64
  else
    TestOverflowAllocation32;

  TestBoundaryConditions;

  WriteLn;
  WriteLn('================================================================================');
  WriteLn('TEST SUMMARY');
  WriteLn('================================================================================');
  WriteLn('Total tests:  ', TestsTotal);

  {Calculate percentages without floating point}
  if TestsTotal > 0 then
  begin
    PassPercent := (TestsPassed * 100) div TestsTotal;
    FailPercent := (TestsFailed * 100) div TestsTotal;
  end
  else
  begin
    PassPercent := 0;
    FailPercent := 0;
  end;

  WriteLn('Passed:       ', TestsPassed, ' (', PassPercent, '%)');
  WriteLn('Failed:       ', TestsFailed, ' (', FailPercent, '%)');
  WriteLn('================================================================================');

  if TestsFailed > 0 then
  begin
    WriteLn;
    WriteLn('*** SECURITY WARNING ***');
    WriteLn('Integer overflow vulnerabilities detected!');
    WriteLn('FastMM4-AVX is vulnerable to CVE-2017-17426 class attacks.');
    WriteLn('Recommendation: Apply integer overflow protection patch immediately.');
    WriteLn;
    ExitCode := 1;
  end
  else
  begin
    WriteLn;
    WriteLn('All tests passed - no integer overflow vulnerabilities detected.');
    WriteLn;
    ExitCode := 0;
  end;
end.
