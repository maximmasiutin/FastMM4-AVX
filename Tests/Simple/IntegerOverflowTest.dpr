program IntegerOverflowTest;

{$IFNDEF UNIX}
{$APPTYPE CONSOLE}
{$ENDIF}

{Range and overflow checking stay on for this program. A test that hands the
 allocator the largest values its size type can hold is the one place where a
 truncating cast or a wrapping addition would otherwise pass unnoticed, and
 every expression below is written to be exact at both pointer widths rather
 than to be tolerated by a compiler that is not checking.}
{$R+}
{$Q+}

uses
  FastMM4 in '..\..\FastMM4.pas',
  FastMM4Messages in '..\..\FastMM4Messages.pas';

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

{Ask the allocator for a block and let it answer, rather than asking the
 runtime to raise on our behalf.

 FreePascal has a function form of GetMem that returns nil when the request is
 refused, and returning nil is exactly what this test reads: an overflow size
 must come back as nothing rather than as a block. Delphi has only the
 procedure form, which raises where FreePascal answers, and the program is
 killed before it can report anything, so the request goes through the memory
 manager record instead. That is the same entry FastMM installs itself into,
 so both compilers observe the allocator's own decision and neither observes
 the runtime's reaction to it.

 The argument is passed as NativeInt because that is what the record's field
 takes: plain Integer on the compilers that have no NativeInt of their own,
 where FastMM4 declares one to match, and a 64-bit NativeInt on the compilers
 that do, where truncating to Integer would turn the 64-bit test values into
 32-bit ones. The bit pattern is what matters: FastMM reads the size back as
 NativeUInt, so a value with the high bit set arrives as the large number this
 test means rather than as a negative one.

 SignedSize computes that pattern by subtraction instead of casting the whole
 range, because a plain NativeInt(ASize) on a value above High(NativeInt) is
 out of range by construction and this program compiles with range checking on.
 Every
 operand below stays inside the type it is written in: the subtraction is
 unsigned and cannot borrow, its result is at most High(NativeInt), and adding
 Low(NativeInt) to it lands between Low(NativeInt) and -1.}
{$IFNDEF FPC}
function SignedSize(ASize: NativeUInt): NativeInt;
begin
  if ASize > NativeUInt(High(NativeInt)) then
    Result := Low(NativeInt) + NativeInt(ASize - NativeUInt(High(NativeInt)) - 1)
  else
    Result := NativeInt(ASize);
end;
{$ENDIF}

function TryGetMem(ASize: NativeUInt): Pointer;
{$IFNDEF FPC}
var
  LMemoryManager: TMemoryManager;
{$ENDIF}
begin
{$IFDEF FPC}
  Result := GetMem(ASize);
{$ELSE}
  GetMemoryManager(LMemoryManager);
  Result := LMemoryManager.GetMem(SignedSize(ASize));
{$ENDIF}
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

  P := TryGetMem(1024 * 1024);
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

{The sizes are written as distances below High(NativeUInt) rather than as
 literal hex, so none of them is a constant too wide for the type it is
 assigned to. A literal $FFFFFFFFFFFF0000 compiles on 32-bit only because the
 cast that narrows it is not range checked, which is the opposite of what this
 program is for.

 Every distance has to stay smaller than the margin FastMM leaves below the top
 of the range, which is about 2MB on 64-bit and about 128KB on 32-bit. A size
 further down than that is under MaxSafeLargeBlockSize, so the overflow guard
 never sees it and the allocation fails only because no such block can be
 mapped, which is a pass the test has not earned. The first two distances are
 small enough at either width. The third is not, so it is chosen at run time
 from the pointer size rather than being made one value that is wrong on one of
 them.}
procedure TestOverflowAllocation;
var
  P: Pointer;
  TestSize: NativeUInt;
begin
  WriteLn;
  WriteLn('=== Test 2: Integer Overflow Attack ===');

  {Far above any address space, and wraps once the block overhead is added}
  TestSize := High(NativeUInt) - $FFFF;
  Write('Attempting to allocate: $');
  WriteHex(TestSize);
  WriteLn(' bytes');
  WriteLn('This value should cause integer overflow in size calculation');

  P := TryGetMem(TestSize);
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

  {Second overflow test}
  WriteLn;
  TestSize := High(NativeUInt) - $56;
  Write('Attempting to allocate: $');
  WriteHex(TestSize);
  WriteLn(' bytes');
  WriteLn('This value wraps to near-zero after adding overhead');

  P := TryGetMem(TestSize);
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

  {Third overflow test, kept above MaxSafeLargeBlockSize at either width}
  WriteLn;
  if Is64Bit then
    TestSize := High(NativeUInt) - $FFFFF
  else
    TestSize := High(NativeUInt) - $7FFF;
  Write('Attempting to allocate: $');
  WriteHex(TestSize);
  WriteLn(' bytes');

  P := TryGetMem(TestSize);
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

{$IFDEF FullDebugMode}
{The debug allocator adds its own header, trailer and free-block pointer to
 every request before passing the total to the ordinary allocator. A request
 within that overhead of the top of the size type makes the addition wrap, and
 the wrapped total is a small number the ordinary allocator will serve, so the
 caller receives a block far smaller than it asked for. These probes stand at
 both ends of that interval and at the two largest values there are.

 The overhead is the same sum the allocator forms: the full debug header, a
 NativeUInt trailer and one trailing free-block pointer. FastMM4 declares the
 header type in its interface, so the size is taken from it rather than written
 out, and a change to the stack trace depth moves the probes with it.}
function FullDebugOverheadForTest: NativeUInt;
begin
  Result := SizeOf(TFullDebugBlockHeader) + SizeOf(NativeUInt) + SizeOf(Pointer);
end;

{The debug entry points take the same signed size as the ordinary ones on
 Delphi, so the probes convert through SignedSize for the reason TryGetMem
 does: this program compiles with range checking on, and the values it exists
 to test are out of the signed range by construction.}
function TryDebugGetMem(ASize: NativeUInt): Pointer;
begin
{$IFDEF FPC}
  Result := DebugGetMem(ASize);
{$ELSE}
  Result := DebugGetMem(SignedSize(ASize));
{$ENDIF}
end;

procedure CheckDebugGetMemRefuses(const ATestName: string; ASize: NativeUInt);
var
  P: Pointer;
begin
  P := TryDebugGetMem(ASize);
  if P = nil then
    LogTest(ATestName, True, 'Correctly returned nil')
  else
  begin
    LogTest(ATestName, False, 'DebugGetMem returned an undersized block');
    {The block is deliberately not freed. Its footer was written outside it, so
     the free is what turns a reported failure into a terminated process, and
     every check after this one would then run against a corrupted heap and
     report nothing worth reading. The leak is the lesser evil and happens only
     on a run that has already failed.}
  end;
end;

procedure TestFullDebugModeBoundaries;
var
  LOverhead, LLastSafe, LFirstWrapping: NativeUInt;
begin
  WriteLn;
  WriteLn('=== Test 4: FullDebugMode overhead boundary ===');
  LOverhead := FullDebugOverheadForTest;
  LLastSafe := High(NativeUInt) - LOverhead;
  LFirstWrapping := LLastSafe + 1;

  {The first of these does not wrap when the overhead is added, and has to be
   refused by the ordinary size limit; the rest wrap, and have to be refused
   before the addition happens at all.}
  CheckDebugGetMemRefuses('DebugGetMem at the last size that does not wrap', LLastSafe);
  CheckDebugGetMemRefuses('DebugGetMem at the first size that wraps', LFirstWrapping);
  CheckDebugGetMemRefuses('DebugGetMem at High(NativeUInt)-1', High(NativeUInt) - 1);
  CheckDebugGetMemRefuses('DebugGetMem at High(NativeUInt)', High(NativeUInt));

{$IFNDEF FPC}
  {The size the signed parameter overflows on, which is a different value from
   the ones above and exists only on the compilers that declare the debug entry
   points with a signed size. It is positive, so it passes any test written
   against the unsigned interpretation, and adding the overhead to it overflows
   the parameter's own type. A build with overflow checking on is where that
   shows: unchecked it wraps to a negative number the allocator then refuses,
   so the outcome looks right and the arithmetic is not.

   FreePascal declares the same parameter unsigned, where this size is an
   ordinary large request rather than a boundary of any kind, so the probe is
   not run there. It would leave the debug path entirely and land in the large
   block allocator, which is a different question from the one this test asks.}
  CheckDebugGetMemRefuses('DebugGetMem at the largest signed size',
    NativeUInt(High(NativeInt)));
  CheckDebugGetMemRefuses('DebugGetMem one below the largest signed size',
    NativeUInt(High(NativeInt)) - 1);
{$ENDIF}
end;

{A reallocation to a wrapping size must fail without disturbing the block the
 caller already holds. The address is saved first because the two compilers
 differ on what they do with the pointer: under FreePascal the memory manager
 entry takes it as a var parameter and clears it on failure, so the caller's
 own copy is the only way back to a block that is still allocated.}
procedure TestFullDebugModeReallocBoundary;
const
  COriginalSize = 64;
  CFillValue = $5A;
type
  {A byte pointer of this program's own, because PByte is PAnsiChar on the
   compilers before Delphi 2009 and assigning a number through it does not
   compile there. FastMM4 defines PByteIsPAnsiChar for the same reason.}
  PTestByte = ^Byte;
var
  P, LOriginal, LResult: Pointer;
  LIndex: Integer;
  LIntact: Boolean;
  LFirstWrapping: NativeUInt;
begin
  WriteLn;
  WriteLn('=== Test 5: FullDebugMode reallocation boundary ===');
  P := TryDebugGetMem(COriginalSize);
  if P = nil then
  begin
    LogTest('DebugReallocMem setup', False, 'the original block could not be allocated');
    Exit;
  end;
  LOriginal := P;
  for LIndex := 0 to COriginalSize - 1 do
    PTestByte(NativeUInt(P) + NativeUInt(LIndex))^ := CFillValue;

  LFirstWrapping := High(NativeUInt) - FullDebugOverheadForTest + 1;
{$IFDEF FPC}
  LResult := DebugReallocMem(P, LFirstWrapping);
{$ELSE}
  LResult := DebugReallocMem(P, SignedSize(LFirstWrapping));
{$ENDIF}
  LogTest('DebugReallocMem at the first size that wraps', LResult = nil,
    'Expected nil');
  if LResult <> nil then
  begin
    {The reallocation was served, so the saved address names a block the
     allocator may already have freed or moved. Reading it to see whether it
     survived would be a use after free, and freeing either pointer on a heap
     this request has just corrupted ends the process instead of reporting.
     The check is recorded as failed and nothing further is touched.}
    LogTest('the original block survives the refused reallocation', False,
      'the reallocation was served, so the original block cannot be examined');
    Exit;
  end;

  LIntact := True;
  for LIndex := 0 to COriginalSize - 1 do
    if PTestByte(NativeUInt(LOriginal) + NativeUInt(LIndex))^ <> CFillValue then
      LIntact := False;
  LogTest('the original block survives the refused reallocation', LIntact,
    'its contents must be unchanged');
  DebugFreeMem(LOriginal);
end;
{$ENDIF FullDebugMode}

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
  P := TryGetMem(Size);
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
  P := TryGetMem(Size);
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

  {The largest size the signed half of the range can name. It is below
   MaxSafeLargeBlockSize, so the allocator's own guard passes it through to the
   large block path, where the padding is added. That padding is written in
   NativeUInt for this size's sake: as untyped constants it widened to int64,
   and a size at or above 2^63 overflowed the signed intermediate rather than
   the unsigned type the size has. Unchecked the mask hid it; with overflow
   checking on it ended the process inside the allocator. This probe is the
   ordinary path, so it runs whether or not FullDebugMode is set.}
  Size := NativeUInt(High(NativeInt));
  Write('Attempting to allocate: $');
  WriteHex(Size);
  WriteLn(' bytes (High(NativeInt))');
  P := TryGetMem(Size);
  if P <> nil then
  begin
    Write('[FAIL] High(NativeInt) allocation - VULNERABILITY: got pointer $');
    WriteHex(NativeUInt(P));
    WriteLn;
    Inc(TestsTotal);
    Inc(TestsFailed);
    FreeMem(P);
  end
  else
  begin
    LogTest('High(NativeInt) allocation', True, 'Correctly returned nil');
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

  TestOverflowAllocation;

  TestBoundaryConditions;
{$IFDEF FullDebugMode}
  TestFullDebugModeBoundaries;
  TestFullDebugModeReallocBoundary;
{$ENDIF}

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
