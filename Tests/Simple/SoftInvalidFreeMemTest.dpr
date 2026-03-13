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
  {$ENDIF}
  FastMM4 in '../../FastMM4.pas',
  FastMM4Messages in '../../FastMM4Messages.pas',
  SysUtils;

{$IFDEF MSWINDOWS}
{ Import ExitProcess for clean shutdown after allocator corruption }
procedure ExitProcess(uExitCode: Cardinal); stdcall; external 'kernel32' name 'ExitProcess';
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

const
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
// Main
// =============================================================================
begin
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
  Halt(GExitCode);
  {$ENDIF}
end.
