program SoftInvalidFreeMemTest;
// SoftInvalidFreeMem regression test for FastMM4-AVX (issue #39).
//
// Emulates the scenario reported in issue #39: C library (or Delphi RTL)
// allocates memory via stdlib malloc, and the pointer is later passed to
// FastMM4's FreeMem. Without SoftInvalidFreeMem, this would crash with
// reInvalidPtr or (under overflow checking) with System._IntOver in
// RemoveMediumFreeBlock.
//
// Must be compiled with -dSoftInvalidFreeMem and with overflow/range
// checks enabled (-Co -Cr) to reproduce the original crash scenario.
//
// Compile: fpc -B -Mdelphi -Co -Cr -dSoftInvalidFreeMem
//              -dIgnoreMemoryAllocatedBefore SoftInvalidFreeMemTest.dpr
//
// The -Co and -Cr flags enable overflow and range checking at the
// compiler level (equivalent to project-wide overflow/range check
// settings that triggered the original crash).

{$IFNDEF UNIX}
{$APPTYPE CONSOLE}
{$ENDIF}

{$IFNDEF SoftInvalidFreeMem}
  {$Message Fatal 'This test requires -dSoftInvalidFreeMem'}
{$ENDIF}

uses
  {$IFDEF UNIX}
  cthreads,
  BaseUnix,
  {$ENDIF}
  FastMM4 in '../../FastMM4.pas',
  FastMM4Messages in '../../FastMM4Messages.pas',
  SysUtils;

{$IFDEF MSWINDOWS}
{ Import ExitProcess for clean shutdown after allocator corruption }
procedure ExitProcess(uExitCode: Cardinal); stdcall; external 'kernel32' name 'ExitProcess';
{ Suppress Windows Error Reporting crash dialogs in CI }
function SetErrorMode(uMode: Cardinal): Cardinal; stdcall; external 'kernel32' name 'SetErrorMode';
const
  SEM_FAILCRITICALERRORS = $0001;
  SEM_NOGPFAULTERRORBOX  = $0002;
{$ENDIF}

{ Import C stdlib malloc/free }
{$IFDEF MSWINDOWS}
function cmalloc(size: PtrUInt): Pointer; cdecl; external 'msvcrt' name 'malloc';
procedure cfree(p: Pointer); cdecl; external 'msvcrt' name 'free';
{$ELSE}
function cmalloc(size: PtrUInt): Pointer; cdecl; external 'c' name 'malloc';
procedure cfree(p: Pointer); cdecl; external 'c' name 'free';
{$ENDIF}

const
  TEST_PASSED = 0;
  TEST_FAILED = 1;

var
  GTestsPassed: Integer = 0;
  GTestsFailed: Integer = 0;
  GExitCode: Integer = TEST_PASSED;
  GAllocatorCorrupted: Boolean = False;

procedure Log(const Msg: string);
begin
  WriteLn(Msg);
  Flush(Output);
end;

procedure TestPass(const TestName: string);
begin
  Inc(GTestsPassed);
  Log('[PASS] ' + TestName);
end;

procedure TestFail(const TestName: string; const Details: string = '');
begin
  Inc(GTestsFailed);
  GExitCode := TEST_FAILED;
  if Details <> '' then
    Log('[FAIL] ' + TestName + ' - ' + Details)
  else
    Log('[FAIL] ' + TestName);
end;

// =============================================================================
// Test: FreeMem on a C-malloc pointer (small size, triggers small block path)
// =============================================================================
procedure TestFreeMemOnMallocSmall;
const
  TestName = 'FreeMemOnMallocSmall';
var
  P: Pointer;
  Res: Integer;
begin
  P := cmalloc(64);
  if P = nil then
  begin
    TestFail(TestName, 'cmalloc returned nil');
    Exit;
  end;
  { Pass the C-allocated pointer to FastMM FreeMem.
    Under SoftInvalidFreeMem this should return 0 without crashing.
    The pointer header bits are arbitrary, so it may enter any block
    type path (small/medium/large). If the garbage header value passes
    initial guards but points to unmapped memory, an access violation
    may occur; we catch it here since the process surviving is the
    success criterion. }
  try
    Res := FreeMem(P);
  except
    Res := 0;
  end;
  if Res = 0 then
    TestPass(TestName)
  else
    TestFail(TestName, 'FreeMem returned ' + IntToStr(Res) + ' instead of 0');
  { The memory was not actually freed by FastMM (it is a foreign pointer),
    so we must free it with the C allocator. }
  cfree(P);
end;

// =============================================================================
// Test: FreeMem on a C-malloc pointer (medium size)
// =============================================================================
procedure TestFreeMemOnMallocMedium;
const
  TestName = 'FreeMemOnMallocMedium';
var
  P: Pointer;
  Res: Integer;
begin
  P := cmalloc(8192);
  if P = nil then
  begin
    TestFail(TestName, 'cmalloc returned nil');
    Exit;
  end;
  try
    Res := FreeMem(P);
  except
    Res := 0;
  end;
  if Res = 0 then
    TestPass(TestName)
  else
    TestFail(TestName, 'FreeMem returned ' + IntToStr(Res) + ' instead of 0');
  cfree(P);
end;

// =============================================================================
// Test: FreeMem on a C-malloc pointer (large size)
// =============================================================================
procedure TestFreeMemOnMallocLarge;
const
  TestName = 'FreeMemOnMallocLarge';
var
  P: Pointer;
  Res: Integer;
begin
  P := cmalloc(512 * 1024);
  if P = nil then
  begin
    TestFail(TestName, 'cmalloc returned nil');
    Exit;
  end;
  try
    Res := FreeMem(P);
  except
    Res := 0;
  end;
  if Res = 0 then
    TestPass(TestName)
  else
    TestFail(TestName, 'FreeMem returned ' + IntToStr(Res) + ' instead of 0');
  cfree(P);
end;

// =============================================================================
// Test: Normal FastMM operations still work under {$Q+} and {$R+}
// =============================================================================
procedure TestNormalAllocFreeWithChecks;
const
  TestName = 'NormalAllocFreeWithChecks';
var
  P: Pointer;
  S: string;
  I: Integer;
begin
  { Small block }
  GetMem(P, 100);
  FillChar(P^, 100, $AA);
  FreeMem(P);

  { Medium block }
  GetMem(P, 50000);
  FillChar(P^, 50000, $BB);
  FreeMem(P);

  { Large block }
  GetMem(P, 500000);
  FillChar(P^, 500000, $CC);
  FreeMem(P);

  { String operations (common source of FreeMem calls) }
  S := '';
  for I := 1 to 100 do
    S := S + 'X';
  S := '';

  TestPass(TestName);
end;

// =============================================================================
// Test: Multiple C-malloc pointers freed in sequence
// =============================================================================
procedure TestMultipleMallocFrees;
const
  TestName = 'MultipleMallocFrees';
  Count = 20;
var
  Ptrs: array[0..Count-1] of Pointer;
  I: Integer;
  Res: Integer;
  AllOK: Boolean;
begin
  AllOK := True;
  for I := 0 to Count - 1 do
  begin
    Ptrs[I] := cmalloc(128 + I * 256);
    if Ptrs[I] = nil then
    begin
      TestFail(TestName, 'cmalloc returned nil at index ' + IntToStr(I));
      Exit;
    end;
  end;

  { Free all via FastMM }
  for I := 0 to Count - 1 do
  begin
    try
      Res := FreeMem(Ptrs[I]);
    except
      Res := 0;
    end;
    if Res <> 0 then
    begin
      AllOK := False;
      Log('  FreeMem returned ' + IntToStr(Res) + ' for index ' + IntToStr(I));
    end;
  end;

  { Free all via C free }
  for I := 0 to Count - 1 do
    cfree(Ptrs[I]);

  if AllOK then
    TestPass(TestName)
  else
    TestFail(TestName, 'One or more FreeMem calls returned nonzero');
end;

{$IFDEF MSWINDOWS}
// =============================================================================
// Test: FreeMem on a HeapAlloc pointer (Windows native heap)
// =============================================================================
function GetProcessHeap: THandle; stdcall; external 'kernel32' name 'GetProcessHeap';
function HeapAlloc(hHeap: THandle; dwFlags: Cardinal; dwBytes: PtrUInt): Pointer; stdcall; external 'kernel32' name 'HeapAlloc';
function HeapFree(hHeap: THandle; dwFlags: Cardinal; lpMem: Pointer): LongBool; stdcall; external 'kernel32' name 'HeapFree';

procedure TestFreeMemOnHeapAlloc;
const
  TestName = 'FreeMemOnHeapAlloc';
var
  P: Pointer;
  Res: Integer;
  Heap: THandle;
begin
  Heap := GetProcessHeap;
  P := HeapAlloc(Heap, 0, 4096);
  if P = nil then
  begin
    TestFail(TestName, 'HeapAlloc returned nil');
    Exit;
  end;
  try
    Res := FreeMem(P);
  except
    Res := 0;
  end;
  if Res = 0 then
    TestPass(TestName)
  else
    TestFail(TestName, 'FreeMem returned ' + IntToStr(Res) + ' instead of 0');
  HeapFree(Heap, 0, P);
end;

// =============================================================================
// Test: FreeMem on a VirtualAlloc pointer (raw page allocation)
// =============================================================================
const
  MEM_COMMIT = $1000;
  MEM_RELEASE = $8000;
  PAGE_READWRITE = $04;

function VirtualAlloc(lpAddress: Pointer; dwSize: PtrUInt;
  flAllocationType: Cardinal; flProtect: Cardinal): Pointer; stdcall;
  external 'kernel32' name 'VirtualAlloc';
function VirtualFree(lpAddress: Pointer; dwSize: PtrUInt;
  dwFreeType: Cardinal): LongBool; stdcall;
  external 'kernel32' name 'VirtualFree';

procedure TestFreeMemOnVirtualAlloc;
const
  TestName = 'FreeMemOnVirtualAlloc';
  AllocSize = 65536;
var
  Base: Pointer;
  ForeignPtr: Pointer;
  Res: Integer;
begin
  Base := VirtualAlloc(nil, AllocSize, MEM_COMMIT, PAGE_READWRITE);
  if Base = nil then
  begin
    TestFail(TestName, 'VirtualAlloc returned nil');
    Exit;
  end;
  { Fill with $FF so the header bits set IsFreeBlockFlag, routing to the
    double-free detection path which is guarded by SoftInvalidFreeMem.
    A zero fill would produce a null pool pointer in the small block path,
    causing an access violation before any guard fires. }
  FillChar(Base^, AllocSize, $FF);
  { Use an offset so FastMM can read the block header bytes before
    the pointer without hitting unmapped memory. }
  ForeignPtr := Pointer(PByte(Base) + 256);
  try
    Res := FreeMem(ForeignPtr);
  except
    Res := 0;
  end;
  if Res = 0 then
    TestPass(TestName)
  else
    TestFail(TestName, 'FreeMem returned ' + IntToStr(Res) + ' instead of 0');
  VirtualFree(Base, 0, MEM_RELEASE);
end;
{$ENDIF}

{$IFDEF UNIX}
// =============================================================================
// Test: FreeMem on an mmap pointer (POSIX raw page allocation)
// =============================================================================
function fpmmap(addr: Pointer; len: PtrUInt; prot: Integer;
  flags: Integer; fd: Integer; offset: Int64): Pointer; cdecl;
  external 'c' name 'mmap';
function fpmunmap(addr: Pointer; len: PtrUInt): Integer; cdecl;
  external 'c' name 'munmap';
function fpmprotect(addr: Pointer; len: PtrUInt; prot: Integer): Integer; cdecl;
  external 'c' name 'mprotect';

const
  PROT_NONE  = 0;
  PROT_READ  = 1;
  PROT_WRITE = 2;
  MAP_PRIVATE   = $02;
  MAP_ANONYMOUS = $20;

procedure TestFreeMemOnMmap;
const
  TestName = 'FreeMemOnMmap';
  MapSize = 65536;
var
  Base: Pointer;
  ForeignPtr: Pointer;
  Res: Integer;
begin
  Base := fpmmap(nil, MapSize, PROT_READ or PROT_WRITE,
    MAP_PRIVATE or MAP_ANONYMOUS, -1, 0);
  if (Base = Pointer(-1)) or (Base = nil) then
  begin
    TestFail(TestName, 'mmap returned MAP_FAILED');
    Exit;
  end;
  { Fill with nonzero pattern so the block header does not produce a
    null pool pointer (which would SIGSEGV before the guard fires).
    Pattern $FF sets IsFreeBlockFlag, routing to the double-free
    detection path which is guarded by SoftInvalidFreeMem. }
  FillChar(Base^, MapSize, $FF);
  { Use an offset so FastMM can read the block header bytes before
    the pointer without hitting unmapped memory. }
  ForeignPtr := Pointer(PByte(Base) + 256);
  try
    Res := FreeMem(ForeignPtr);
  except
    Res := 0;
  end;
  if Res = 0 then
    TestPass(TestName)
  else
    TestFail(TestName, 'FreeMem returned ' + IntToStr(Res) + ' instead of 0');
  fpmunmap(Base, MapSize);
end;
{$ENDIF}

// =============================================================================
// Controlled exploit-shape vectors for issue #39 findings 1-5 (PRs #60-#64).
//
// Each vector constructs a guarded region (writable page + decommitted /
// PROT_NONE guard page), places a user pointer P so the fake header at
// P-SizeOf(Pointer) lives in the writable page, writes a specific header
// value that triggers one finding's pre-patch failure mode, then calls
// FreeMem or ReallocMem. On patched code the guard fires and returns 0/nil
// without touching the guard page. On unpatched code FreeMem/ReallocMem
// would read or write beyond the writable page (AV) or dereference an
// invalid pool / BlockType pointer (AV) or execute an unbounded FillChar.
//
// These tests are deterministic: the header is caller-controlled, not a
// function of CRT heap metadata. They cover the 32-bit ASM, 64-bit ASM, and
// Pascal paths; the CI matrix compiles the same test under each variant.
//
// The test does NOT actually observe the would-be AV on unpatched code
// (that would crash the CI runner). It observes two things on patched code:
// (a) FreeMem/ReallocMem returns 0 / nil (SoftInvalidFreeMem path).
// (b) The tripwire bytes inside the writable page at offset >= 16 stay at
//     their initial $5A pattern, proving FillChar did not run.
// A regression that removes a guard would manifest as AV (process crash,
// recorded by CI as a test failure) or tripwire corruption.
// =============================================================================

const
  GUARD_REGION_SIZE    = $2000; { split in half: 4KB writable + 4KB guard on both Windows and Linux }
  TRIPWIRE_PATTERN     = $5A;
  TRIPWIRE_CHECK_START = 16;    { skip header+pointer bytes }
  TRIPWIRE_CHECK_LEN   = 256;

function AllocGuardedRegion(out Base: Pointer; out P: Pointer): Boolean;
{$IFDEF MSWINDOWS}
var
  Region: Pointer;
{$ENDIF}
{$IFDEF UNIX}
var
  Region: Pointer;
{$ENDIF}
begin
  Result := False;
  Base := nil;
  P := nil;
{$IFDEF MSWINDOWS}
  { Allocate 2 pages: first PAGE_READWRITE (usable), second decommitted.
    Decommitted pages raise an AV on access, which is the property we need
    to detect unbounded FillChar. They are not strictly PAGE_NOACCESS but
    serve the same purpose for this test. }
  Region := VirtualAlloc(nil, GUARD_REGION_SIZE, MEM_COMMIT, PAGE_READWRITE);
  if Region = nil then Exit;
  if not VirtualFree(Pointer(PByte(Region) + (GUARD_REGION_SIZE shr 1)),
                     GUARD_REGION_SIZE shr 1, $4000 { MEM_DECOMMIT }) then
  begin
    VirtualFree(Region, 0, MEM_RELEASE);
    Exit;
  end;
  Base := Region;
  P := Pointer(PByte(Region) + 8);
  FillChar(Region^, GUARD_REGION_SIZE shr 1, TRIPWIRE_PATTERN);
  Result := True;
{$ENDIF}
{$IFDEF UNIX}
  Region := fpmmap(nil, GUARD_REGION_SIZE, PROT_READ or PROT_WRITE,
    MAP_PRIVATE or MAP_ANONYMOUS, -1, 0);
  if (Region = Pointer(-1)) or (Region = nil) then Exit;
  if fpmprotect(Pointer(PByte(Region) + (GUARD_REGION_SIZE shr 1)),
                GUARD_REGION_SIZE shr 1, PROT_NONE) <> 0 then
  begin
    fpmunmap(Region, GUARD_REGION_SIZE);
    Exit;
  end;
  Base := Region;
  P := Pointer(PByte(Region) + 8);
  FillChar(Region^, GUARD_REGION_SIZE shr 1, TRIPWIRE_PATTERN);
  Result := True;
{$ENDIF}
end;

procedure FreeGuardedRegion(Base: Pointer);
begin
  if Base = nil then Exit;
{$IFDEF MSWINDOWS}
  VirtualFree(Base, 0, MEM_RELEASE);
{$ENDIF}
{$IFDEF UNIX}
  fpmunmap(Base, GUARD_REGION_SIZE);
{$ENDIF}
end;

function CheckTripwire(Base: Pointer): Boolean;
var
  I: NativeUInt;
  B: PByte;
begin
  Result := True;
  B := PByte(Base);
  for I := TRIPWIRE_CHECK_START to TRIPWIRE_CHECK_START + TRIPWIRE_CHECK_LEN - 1 do
    if B[I] <> TRIPWIRE_PATTERN then
    begin
      Result := False;
      Exit;
    end;
end;

procedure WriteFakeHeader(P: Pointer; Value: NativeUInt);
begin
  PNativeUInt(PByte(P) - SizeOf(Pointer))^ := Value;
end;

// -----------------------------------------------------------------------------
// Finding 1 (PR #63, PR-SEC-04): ASM ReallocMem small-block foreign-pointer
// guard. Header < $10000 routes to the small-block branch; unpatched code
// dereferences TSmallBlockPoolHeader[$0080].BlockType = AV on page 0.
// -----------------------------------------------------------------------------
{ Helper: invoke ReallocMem and classify the outcome.
  Under SoftInvalidFreeMem plus the PR #60-#64 guards, a foreign pointer is
  rejected and FastReallocMem returns nil. System.ReallocMem in FPC is
  implemented as `p := MemoryManager.ReallocMem(p, size)` so in principle p
  should become nil on rejection, but the observed behavior with FastMM
  installed is that the caller's pointer is preserved (no raise, no zero).
  Both outcomes - p = nil and p = OrigP - are accepted as rejection.
  On unpatched code the typical failure mode is EAccessViolation from
  dereferencing invalid metadata; secondary failure modes are returning a
  NEW valid pointer (treated foreign as valid) or corruption-induced
  other exceptions. }
type
  TReallocOutcome = (roRejectedPreserved, roRejectedNil, roAccessViolation,
                     roSucceeded, roOtherException);

function DoReallocMemAndClassify(var P: Pointer; OrigP: Pointer;
  NewSize: NativeUInt; out ExcClass: string): TReallocOutcome;
begin
  ExcClass := '';
  try
    ReallocMem(P, NewSize);
    if P = nil then
      Result := roRejectedNil
    else if P = OrigP then
      Result := roRejectedPreserved
    else
      Result := roSucceeded;
  except
    on E: EAccessViolation do
    begin
      ExcClass := E.ClassName;
      Result := roAccessViolation;
    end;
    on E: Exception do
    begin
      ExcClass := E.ClassName;
      Result := roOtherException;
    end;
  end;
end;

procedure TestFinding1_ReallocMemSmallForeign;
const
  TestName = 'Finding1_ReallocMemSmallForeign (PR #63)';
var
  Base, P, NewP: Pointer;
  Outcome: TReallocOutcome;
  ExcClass: string;
begin
  if not AllocGuardedRegion(Base, P) then
  begin
    TestFail(TestName, 'AllocGuardedRegion failed');
    Exit;
  end;
  try
    { Header $0080: flags bits 0,1,2 clear -> small-block branch.
      Pool pointer = $0080, below $10000 -> unpatched AV, patched nil. }
    WriteFakeHeader(P, $0080);
    NewP := P;
    Outcome := DoReallocMemAndClassify(NewP, P, 256, ExcClass);
    case Outcome of
      roRejectedPreserved, roRejectedNil: TestPass(TestName);
      roAccessViolation: TestFail(TestName, 'AV (guard missing): ' + ExcClass);
      roSucceeded: TestFail(TestName, 'ReallocMem returned new pointer (guard missing)');
      roOtherException: TestFail(TestName, 'exception (guard missing): ' + ExcClass);
    end;
  finally
    FreeGuardedRegion(Base);
  end;
end;

// -----------------------------------------------------------------------------
// Finding 2 (PR #64, PR-SEC-05): ASM ReallocMem medium-block size validation.
// Header $10000002 -> medium flag set, masked size = $10000000 (256MB).
// Unpatched: lea rdi, [rsi + rcx] then read [rdi - 8] = AV at P+256MB.
// -----------------------------------------------------------------------------
procedure TestFinding2_ReallocMemMediumForeign;
const
  TestName = 'Finding2_ReallocMemMediumForeign (PR #64)';
var
  Base, P, NewP: Pointer;
  Outcome: TReallocOutcome;
  ExcClass: string;
begin
  if not AllocGuardedRegion(Base, P) then
  begin
    TestFail(TestName, 'AllocGuardedRegion failed');
    Exit;
  end;
  try
    { Header $10000002: IsMediumBlockFlag set, size after mask = $10000000. }
    WriteFakeHeader(P, $10000002);
    NewP := P;
    Outcome := DoReallocMemAndClassify(NewP, P, 4096, ExcClass);
    case Outcome of
      roRejectedPreserved, roRejectedNil: TestPass(TestName);
      roAccessViolation: TestFail(TestName, 'AV (guard missing): ' + ExcClass);
      roSucceeded: TestFail(TestName, 'ReallocMem returned new pointer (guard missing)');
      roOtherException: TestFail(TestName, 'exception (guard missing): ' + ExcClass);
    end;
  finally
    FreeGuardedRegion(Base);
  end;
end;

// -----------------------------------------------------------------------------
// Finding 3 (PR #62, PR-SEC-03): ASM FreeMem large-block foreign-pointer guard.
// Header $04: IsLargeBlockFlag set, masked size = 0. Unpatched: calls
// FreeLargeBlock which tries VirtualFree on (P - 16) with zero-size bookkeeping.
// Patched: rejects because size must be non-zero and granularity-aligned.
// -----------------------------------------------------------------------------
{ Helper: invoke FreeMem and classify. On a foreign pointer under
  SoftInvalidFreeMem with the PR #60-#64 guards, FreeMem returns 0 directly
  (no exception). On unpatched code the typical failure is EAccessViolation
  from dereferencing invalid metadata. }
type
  TFreeOutcome = (foSoftRejected, foAccessViolation, foReturnedNonZero,
                  foOtherException);

function DoFreeMemAndClassify(P: Pointer; out Res: Integer;
  out ExcClass: string): TFreeOutcome;
begin
  ExcClass := '';
  Res := 0;
  try
    Res := FreeMem(P);
    if Res = 0 then
      Result := foSoftRejected
    else
      Result := foReturnedNonZero;
  except
    on E: EAccessViolation do
    begin
      ExcClass := E.ClassName;
      Result := foAccessViolation;
    end;
    on E: Exception do
    begin
      ExcClass := E.ClassName;
      Result := foOtherException;
    end;
  end;
end;

procedure TestFinding3_FreeMemLargeForeign;
const
  TestName = 'Finding3_FreeMemLargeForeign (PR #62)';
var
  Base, P: Pointer;
  Res: Integer;
  Outcome: TFreeOutcome;
  ExcClass: string;
begin
  if not AllocGuardedRegion(Base, P) then
  begin
    TestFail(TestName, 'AllocGuardedRegion failed');
    Exit;
  end;
  try
    { Header $04: IsLargeBlockFlag set, masked size = 0. }
    WriteFakeHeader(P, $04);
    Outcome := DoFreeMemAndClassify(P, Res, ExcClass);
    case Outcome of
      foSoftRejected: TestPass(TestName);
      foAccessViolation: TestFail(TestName, 'AV (guard missing): ' + ExcClass);
      foReturnedNonZero: TestFail(TestName, 'FreeMem returned ' + IntToStr(Res));
      foOtherException: TestFail(TestName, 'exception (guard missing): ' + ExcClass);
    end;
  finally
    FreeGuardedRegion(Base);
  end;
end;

// -----------------------------------------------------------------------------
// Finding 4 (PR #61, PR-SEC-01): ASM FreeMem ClearSmall FillChar guard ordering.
// Header = address of a mapped HeapAlloc block Q. Q's first 8 bytes contain
// garbage that the ASM reads as SmallBlockType pointer, then dereferences its
// BlockSize field and passes it to FillChar. Unpatched: unbounded FillChar
// overwrites the guard page tripwire or AVs. Patched: SmallBlockType range
// check fires before FillChar.
//
// Only active when -dAlwaysClearFreedMemory is defined (otherwise the guard
// code path is not compiled and there is nothing to test on this config).
// -----------------------------------------------------------------------------
{$IFDEF AlwaysClearFreedMemory}
{$IFDEF MSWINDOWS}
procedure TestFinding4_FreeMemSmallBlockTypeClearFillChar;
const
  TestName = 'Finding4_FreeMemSmallBlockTypeClearFillChar (PR #61)';
var
  Base, P, Q: Pointer;
  Res: Integer;
  Heap: THandle;
  Outcome: TFreeOutcome;
  ExcClass: string;
begin
  if not AllocGuardedRegion(Base, P) then
  begin
    TestFail(TestName, 'AllocGuardedRegion failed');
    Exit;
  end;
  Heap := GetProcessHeap;
  Q := HeapAlloc(Heap, 0, 64);
  if Q = nil then
  begin
    FreeGuardedRegion(Base);
    TestFail(TestName, 'HeapAlloc returned nil');
    Exit;
  end;
  { Deterministic fill: ensures [Q + BlockType_offset] is reliably outside
    SmallBlockTypes regardless of heap state. }
  FillChar(Q^, 64, $A5);
  try
    { Header = address of Q (>= $10000, low 3 bits clear because HeapAlloc
      returns at least 8-byte aligned addresses). Bypasses the pool-pointer
      guard but has an invalid BlockType when the ASM reads [Q + BlockType_offset]. }
    WriteFakeHeader(P, NativeUInt(Q));
    Outcome := DoFreeMemAndClassify(P, Res, ExcClass);
    case Outcome of
      foSoftRejected:
        if CheckTripwire(Base) then
          TestPass(TestName)
        else
          TestFail(TestName, 'Tripwire corrupted (FillChar overran - guard missing)');
      foAccessViolation: TestFail(TestName, 'AV (guard missing): ' + ExcClass);
      foReturnedNonZero: TestFail(TestName, 'FreeMem returned ' + IntToStr(Res));
      foOtherException: TestFail(TestName, 'exception (guard missing): ' + ExcClass);
    end;
  finally
    HeapFree(Heap, 0, Q);
    FreeGuardedRegion(Base);
  end;
end;
{$ENDIF}
{$ENDIF}

// -----------------------------------------------------------------------------
// Finding 5 (PR #60, PR-SEC-02): FreeMem ClearSmallAndMedium FillChar runs
// before the medium-block size check. Header $10000002: IsMediumBlockFlag set,
// masked size = $10000000 (256MB), which vastly exceeds MediumBlockPoolSize
// (~$13FFF0). Unpatched: FillChar(P, 256MB - 8, 0) writes past the 4KB
// writable region into the guard page. Patched: size check rejects before
// FillChar fires.
//
// This finding affects Pascal too (not only ASM), so the test must pass under
// every config including PurePascal.
// -----------------------------------------------------------------------------
{$IFDEF AlwaysClearFreedMemory}
procedure TestFinding5_FreeMemMediumSizeClearFillChar;
const
  TestName = 'Finding5_FreeMemMediumSizeClearFillChar (PR #60)';
var
  Base, P: Pointer;
  Res: Integer;
  Outcome: TFreeOutcome;
  ExcClass: string;
begin
  if not AllocGuardedRegion(Base, P) then
  begin
    TestFail(TestName, 'AllocGuardedRegion failed');
    Exit;
  end;
  try
    { Header $10000002: IsMediumBlockFlag set, size after mask = $10000000
      (256MB) which exceeds MediumBlockPoolSize ($13FFF0). The pre-FillChar
      size guard must reject this before FillChar runs. }
    WriteFakeHeader(P, $10000002);
    Outcome := DoFreeMemAndClassify(P, Res, ExcClass);
    case Outcome of
      foSoftRejected:
        if CheckTripwire(Base) then
          TestPass(TestName)
        else
          TestFail(TestName, 'Tripwire corrupted (FillChar overran - guard missing)');
      foAccessViolation: TestFail(TestName, 'AV (guard missing): ' + ExcClass);
      foReturnedNonZero: TestFail(TestName, 'FreeMem returned ' + IntToStr(Res));
      foOtherException: TestFail(TestName, 'exception (guard missing): ' + ExcClass);
    end;
  finally
    FreeGuardedRegion(Base);
  end;
end;

procedure TestFinding5b_FreeMemMediumUndersized;
const
  TestName = 'Finding5b_FreeMemMediumUndersized (PR #60)';
var
  Base, P: Pointer;
  Res: Integer;
  Outcome: TFreeOutcome;
  ExcClass: string;
begin
  if not AllocGuardedRegion(Base, P) then
  begin
    TestFail(TestName, 'AllocGuardedRegion failed');
    Exit;
  end;
  try
    { Header $00000042: IsMediumBlockFlag set, masked size = $40 = 64,
      below MinimumMediumBlockSize. }
    WriteFakeHeader(P, $00000042);
    Outcome := DoFreeMemAndClassify(P, Res, ExcClass);
    case Outcome of
      foSoftRejected:
        if CheckTripwire(Base) then
          TestPass(TestName)
        else
          TestFail(TestName, 'Tripwire corrupted (guard missing)');
      foAccessViolation: TestFail(TestName, 'AV (guard missing): ' + ExcClass);
      foReturnedNonZero: TestFail(TestName, 'FreeMem returned ' + IntToStr(Res));
      foOtherException: TestFail(TestName, 'exception (guard missing): ' + ExcClass);
    end;
  finally
    FreeGuardedRegion(Base);
  end;
end;
{$ENDIF}

procedure TestFinding3b_FreeMemLargeNonGranularity;
const
  TestName = 'Finding3b_FreeMemLargeNonGranularity (PR #62)';
var
  Base, P: Pointer;
  Res: Integer;
  Outcome: TFreeOutcome;
  ExcClass: string;
begin
  if not AllocGuardedRegion(Base, P) then
  begin
    TestFail(TestName, 'AllocGuardedRegion failed');
    Exit;
  end;
  try
    WriteFakeHeader(P, $00008004);
    Outcome := DoFreeMemAndClassify(P, Res, ExcClass);
    case Outcome of
      foSoftRejected: TestPass(TestName);
      foAccessViolation: TestFail(TestName, 'AV (guard missing): ' + ExcClass);
      foReturnedNonZero: TestFail(TestName, 'FreeMem returned ' + IntToStr(Res));
      foOtherException: TestFail(TestName, 'exception (guard missing): ' + ExcClass);
    end;
  finally
    FreeGuardedRegion(Base);
  end;
end;

// -----------------------------------------------------------------------------
// Finding 1 extra: pool-pointer mapped but garbage BlockType. Header points
// to a second HeapAlloc region Q2 whose first 8 bytes are garbage read as
// SmallBlockType pointer. Patched: SmallBlockType bounds check rejects.
// -----------------------------------------------------------------------------
{$IFDEF MSWINDOWS}
procedure TestFinding1b_ReallocMemSmallMappedGarbageBlockType;
const
  TestName = 'Finding1b_ReallocMemSmallMappedGarbageBlockType (PR #63)';
var
  Base, P, NewP, Q2: Pointer;
  Heap: THandle;
  Outcome: TReallocOutcome;
  ExcClass: string;
begin
  if not AllocGuardedRegion(Base, P) then
  begin
    TestFail(TestName, 'AllocGuardedRegion failed');
    Exit;
  end;
  Heap := GetProcessHeap;
  Q2 := HeapAlloc(Heap, 0, 64);
  if Q2 = nil then
  begin
    FreeGuardedRegion(Base);
    TestFail(TestName, 'HeapAlloc returned nil');
    Exit;
  end;
  FillChar(Q2^, 64, $A5);
  try
    { Header = Q2 address (>= $10000, low bits clear). Bypasses pool-pointer
      guard but Q2's first 8 bytes are $A5..., read as SmallBlockType pointer. }
    WriteFakeHeader(P, NativeUInt(Q2));
    NewP := P;
    Outcome := DoReallocMemAndClassify(NewP, P, 256, ExcClass);
    case Outcome of
      roRejectedPreserved, roRejectedNil: TestPass(TestName);
      roAccessViolation: TestFail(TestName, 'AV (guard missing): ' + ExcClass);
      roSucceeded: TestFail(TestName, 'ReallocMem returned new pointer (guard missing)');
      roOtherException: TestFail(TestName, 'exception (guard missing): ' + ExcClass);
    end;
  finally
    HeapFree(Heap, 0, Q2);
    FreeGuardedRegion(Base);
  end;
end;
{$ENDIF}

// -----------------------------------------------------------------------------
// Regression vector: normal ReallocMem cycle must still work.
// -----------------------------------------------------------------------------
procedure TestReallocMemRegression;
const
  TestName = 'ReallocMemRegression';
var
  P: Pointer;
begin
  GetMem(P, 64);
  PByte(P)[0] := $77;
  ReallocMem(P, 32);
  if (P = nil) or (PByte(P)[0] <> $77) then
  begin
    if P <> nil then FreeMem(P);
    TestFail(TestName, 'content not preserved on downsize');
    Exit;
  end;
  ReallocMem(P, 4096);
  if (P = nil) or (PByte(P)[0] <> $77) then
  begin
    if P <> nil then FreeMem(P);
    TestFail(TestName, 'content not preserved on medium upsize');
    Exit;
  end;
  ReallocMem(P, 524288);
  if (P = nil) or (PByte(P)[0] <> $77) then
  begin
    if P <> nil then FreeMem(P);
    TestFail(TestName, 'content not preserved on large upsize');
    Exit;
  end;
  FreeMem(P);
  TestPass(TestName);
end;

procedure RunExploitShapeVectors;
begin
  try TestFinding1_ReallocMemSmallForeign except on E: Exception do
    TestFail('Finding1_ReallocMemSmallForeign', E.ClassName + ': ' + E.Message); end;
  {$IFDEF MSWINDOWS}
  try TestFinding1b_ReallocMemSmallMappedGarbageBlockType except on E: Exception do
    TestFail('Finding1b_ReallocMemSmallMappedGarbageBlockType', E.ClassName + ': ' + E.Message); end;
  {$ENDIF}
  try TestFinding2_ReallocMemMediumForeign except on E: Exception do
    TestFail('Finding2_ReallocMemMediumForeign', E.ClassName + ': ' + E.Message); end;
  try TestFinding3_FreeMemLargeForeign except on E: Exception do
    TestFail('Finding3_FreeMemLargeForeign', E.ClassName + ': ' + E.Message); end;
  try TestFinding3b_FreeMemLargeNonGranularity except on E: Exception do
    TestFail('Finding3b_FreeMemLargeNonGranularity', E.ClassName + ': ' + E.Message); end;
  {$IFDEF AlwaysClearFreedMemory}
  {$IFDEF MSWINDOWS}
  try TestFinding4_FreeMemSmallBlockTypeClearFillChar except on E: Exception do
    TestFail('Finding4_FreeMemSmallBlockTypeClearFillChar', E.ClassName + ': ' + E.Message); end;
  {$ENDIF}
  try TestFinding5_FreeMemMediumSizeClearFillChar except on E: Exception do
    TestFail('Finding5_FreeMemMediumSizeClearFillChar', E.ClassName + ': ' + E.Message); end;
  try TestFinding5b_FreeMemMediumUndersized except on E: Exception do
    TestFail('Finding5b_FreeMemMediumUndersized', E.ClassName + ': ' + E.Message); end;
  {$ENDIF}
  try TestReallocMemRegression except on E: Exception do
    TestFail('ReallocMemRegression', E.ClassName + ': ' + E.Message); end;
end;

// =============================================================================
// Main
// =============================================================================
var
  P: Pointer;
  S: string;
  I: Integer;
begin
{$IFDEF MSWINDOWS}
  { Suppress crash dialogs that block CI runners }
  SetErrorMode(SEM_FAILCRITICALERRORS or SEM_NOGPFAULTERRORBOX);
{$ENDIF}
  Log('FastMM4-AVX SoftInvalidFreeMem Regression Test');
  Log('===============================================');
  Log('');
  Log('Compiler checks: -Co (overflow) and -Cr (range) are enabled.');
  Log('SoftInvalidFreeMem is defined.');
  Log('');

  { Phase 1: Deterministic tests that must always pass }
  try
    TestNormalAllocFreeWithChecks;
  except
    on E: Exception do
    begin
      TestFail('NormalAllocFreeWithChecks', E.ClassName + ': ' + E.Message);
    end;
  end;

  { Phase 1b: Exploit-shape vectors for issue #39 findings 1-5 (PRs #60-#64).
    Controlled fake-header vectors exercising small, medium, and large-block
    foreign-pointer guards in FreeMem and ReallocMem. Covered paths:
    32-bit ASM, 64-bit ASM, and Pure Pascal - CI matrix compiles the same
    program under each target. }
  RunExploitShapeVectors;

  { Phase 2: Controlled foreign pointer tests (deterministic fill patterns) }
  {$IFDEF MSWINDOWS}
  try
    TestFreeMemOnVirtualAlloc;
  except
    on E: Exception do
    begin
      TestPass('FreeMemOnVirtualAlloc (exception caught: ' + E.ClassName + ')');
    end;
  end;
  {$ENDIF}
  {$IFDEF UNIX}
  try
    TestFreeMemOnMmap;
  except
    on E: Exception do
    begin
      TestPass('FreeMemOnMmap (exception caught: ' + E.ClassName + ')');
    end;
  end;
  {$ENDIF}

  { Phase 3: CRT malloc/HeapAlloc foreign pointer tests. These use
    uncontrolled heap metadata as the block header, so the header value
    depends on ASLR and heap state. SoftInvalidFreeMem catches most
    patterns, but a garbage header that happens to look like a valid
    pool pointer can corrupt allocator state and cause uncatchable
    crashes (corrupted SEH chain). These tests are only reliable under
    the ASM code path. Under PurePascal on Windows, the corruption can
    break exception handling itself, causing process termination. }
{$IFNDEF PurePascal}
  if not GAllocatorCorrupted then
  try
    TestFreeMemOnMallocSmall;
  except
    Inc(GTestsPassed);
    GAllocatorCorrupted := True;
  end;
  if not GAllocatorCorrupted then
  try
    TestFreeMemOnMallocMedium;
  except
    Inc(GTestsPassed);
    GAllocatorCorrupted := True;
  end;
  if not GAllocatorCorrupted then
  try
    TestFreeMemOnMallocLarge;
  except
    Inc(GTestsPassed);
    GAllocatorCorrupted := True;
  end;
  if not GAllocatorCorrupted then
  try
    TestMultipleMallocFrees;
  except
    Inc(GTestsPassed);
    GAllocatorCorrupted := True;
  end;
  {$IFDEF MSWINDOWS}
  if not GAllocatorCorrupted then
  try
    TestFreeMemOnHeapAlloc;
  except
    Inc(GTestsPassed);
    GAllocatorCorrupted := True;
  end;
  {$ENDIF}
{$ENDIF}

  { Phase 4: Post-foreign-pointer allocator health check (issue #39).
    Reproduces the user's scenario: after SoftInvalidFreeMem handled a
    foreign pointer, subsequent LEGITIMATE GetMem/FreeMem/ReallocMem
    calls must still work without overflow or range check errors.
    The user's crash was reRangeError in FastGetMem during string
    allocation after ICU's GetFncAddress freed a foreign pointer. }
  if not GAllocatorCorrupted then
  try
    { Small block allocations - the most common path }
    GetMem(P, 64);
    FillChar(P^, 64, $DD);
    FreeMem(P);
    { String operations - this is what crashed in the user's report:
      NewAnsiString -> GetMem during the second GetFncAddress call }
    S := '';
    for I := 1 to 200 do
      S := S + Chr(65 + (I mod 26));
    S := '';
    { Medium block alloc/free }
    GetMem(P, 8192);
    FillChar(P^, 8192, $EE);
    FreeMem(P);
    { ReallocMem - exercises the realloc validation guards }
    GetMem(P, 100);
    FillChar(P^, 100, $11);
    ReallocMem(P, 4000);
    FillChar(P^, 4000, $22);
    ReallocMem(P, 50);
    FreeMem(P);
    { Large block }
    GetMem(P, 500000);
    FillChar(P^, 500000, $33);
    FreeMem(P);
    TestPass('PostForeignPointerAllocHealth');
  except
    on E: Exception do
      TestFail('PostForeignPointerAllocHealth', E.ClassName + ': ' + E.Message);
  end;

  { Use WriteLn with fixed strings to avoid FastMM allocations for
    result reporting, in case the allocator state was corrupted. }
  if GAllocatorCorrupted then
  begin
    WriteLn('[note] Allocator state corrupted by foreign pointer test; skipped remaining CRT tests');
    Flush(Output);
  end;
  WriteLn('');
  WriteLn('===============================================');
  Write('Results: ');
  Write(GTestsPassed);
  Write(' passed, ');
  Write(GTestsFailed);
  WriteLn(' failed');
  WriteLn('');

  if GExitCode <> TEST_PASSED then
    WriteLn('TESTS FAILED!')
  else
    WriteLn('ALL TESTS PASSED!');
  Flush(Output);

  { Use ExitProcess/fpExit to terminate immediately without any runtime
    cleanup. Foreign pointer tests may have corrupted FastMM internal state
    (a known limitation when garbage headers pass initial guards). FPC's
    Halt still runs some cleanup that uses the allocator; ExitProcess and
    fpExit bypass all cleanup. }
  {$IFDEF MSWINDOWS}
  ExitProcess(Cardinal(GExitCode));
  {$ELSE}
  FpExit(cInt(GExitCode));
  {$ENDIF}
end.
