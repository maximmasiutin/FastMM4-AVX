program FpuStackTest;

// Regression test for the FPU stack corruption fixed in the 32-bit fixed size
// move routines Move36, Move44, Move52, Move60 and Move68 (pleriche/FastMM4
// issue 85). Those routines copied through the x87 stack with fild and fistp.
// A caller that already held values there overflowed the eight register stack,
// which corrupts the caller's values and raises an invalid operation, and the
// fix replaced the sequence with rep movsd, which touches no floating point
// state at all. See https://stackoverflow.com/q/79833922/6910868
//
// What this checks is the property the fix restored: an upsize of a small
// block leaves the x87 stack exactly as it found it. The check is written
// against the allocator rather than against the routines, because they are
// internal to the unit and cannot be called from a test program.
//
// Which routine the check exercises depends on the build. On Windows, where
// the CPU has SSE, the allocator installs the SSE movers for these sizes, so
// the check covers those. The repaired routines are the ones installed on a
// Unix 32-bit build, and on any processor without SSE. The property is the
// same for both, which is what makes one test worth writing.
//
// Compile with FreePascal:
//   fpc -B -Mdelphi -Twin32 -Pi386 FpuStackTest.dpr
//
// On a 64-bit target the routines under test do not exist and the program
// reports that it skipped, with a passing exit code.

{$IFDEF FPC}
  {$MODE DELPHI}
  {$ASMMODE INTEL}
{$ENDIF}
{$APPTYPE CONSOLE}

uses
  FastMM4,
  SysUtils;

const
  TEST_PASSED = 0;
  TEST_FAILED = 1;

var
  GFailures: Integer = 0;

procedure Say(const AText: string);
begin
  WriteLn(AText);
  Flush(Output);
end;

procedure Check(ACondition: Boolean; const AWhat: string);
begin
  if ACondition then
    Say('  ok    ' + AWhat)
  else
  begin
    Say('  FAIL  ' + AWhat);
    Inc(GFailures);
  end;
end;

{$IFDEF CPU386}

{Seven values on the x87 stack leave one register free, which is the state that
 made the old sequence overflow: it pushed before it popped.}
procedure FpuInitAndPushSeven; assembler;
asm
  fninit
  fldz
  fldz
  fldz
  fldz
  fldz
  fldz
  fldz
end;

function FpuStatusWord: Word; assembler;
asm
  fstsw ax
end;

procedure FpuReset; assembler;
asm
  fninit
end;

{Upsize a small block of every size that the fixed size movers serve, with the
 x87 stack loaded, and then ask the status word what happened to it.}
procedure TestFpuStackAcrossUpsize;
const
  CLowSize = 33;
  CHighSize = 96;
var
  LBlock: Pointer;
  {PByteArray rather than PByte, because indexing a PByte needs POINTERMATH,
   which arrived in Delphi 2009 and this unit still compiles on Delphi 4.}
  LBytes: PByteArray;
  LSize, LIndex: Integer;
  LDataKept: Boolean;
  LBefore, LAfter: Word;
  LTopBefore, LTopAfter: Integer;
begin
  Say('the x87 stack across a small block upsize');
  LDataKept := True;

  FpuInitAndPushSeven;
  LBefore := FpuStatusWord;

  for LSize := CLowSize to CHighSize do
  begin
    {The procedure form of GetMem, which is the only one Delphi has: the
     function form exists in FreePascal alone.}
    GetMem(LBlock, LSize);
    LBytes := LBlock;
    for LIndex := 0 to LSize - 1 do
      LBytes^[LIndex] := Byte((LIndex + LSize) and $FF);
    {A grow of this size cannot stay in place, so the allocator copies the old
     contents with the fixed size move procedure of the old block type.}
    ReallocMem(LBlock, LSize + 256);
    LBytes := LBlock;
    for LIndex := 0 to LSize - 1 do
      if LBytes^[LIndex] <> Byte((LIndex + LSize) and $FF) then
        LDataKept := False;
    FreeMem(LBlock);
  end;

  LAfter := FpuStatusWord;
  FpuReset;

  LTopBefore := (LBefore shr 11) and 7;
  LTopAfter := (LAfter shr 11) and 7;

  Check(LTopBefore = 1, 'seven values loaded, so the stack pointer reads one');
  Check(LTopAfter = LTopBefore, 'the stack pointer is where it was after 64 upsizes');
  Check((LAfter and $0040) = 0, 'no stack fault is flagged');
  Check((LAfter and $0001) = 0, 'no invalid operation is flagged');
  Check(LDataKept, 'every upsized block kept its contents');
end;

{$ENDIF CPU386}

{The exit code is set rather than the program halted. Halt abandons the frame it
 is called from, so any string the compiler built for these calls is still held
 when the allocator runs its leak check, and it is then reported as a leak of
 this program rather than of the runtime. Falling off the end of the main block
 finalises those temporaries first, which is what keeps the check clean.}
begin
{$IFDEF CPU386}
  Say('FPU stack across the 32-bit fixed size move routines');
  TestFpuStackAcrossUpsize;

  if GFailures = 0 then
  begin
    Say('all checks passed');
    ExitCode := TEST_PASSED;
  end
  else
  begin
    Say('failures: ' + IntToStr(GFailures));
    ExitCode := TEST_FAILED;
  end;
{$ELSE}
  Say('skipped: the move routines that used the x87 stack exist only in the 32-bit code path');
  ExitCode := TEST_PASSED;
{$ENDIF}
end.
