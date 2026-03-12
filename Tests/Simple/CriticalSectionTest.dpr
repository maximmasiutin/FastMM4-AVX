program CriticalSectionTest;
{
  Critical Section concurrency test for FastMM4-AVX.

  FastMM4 locking has two paths per block type (small/medium/large):
    1. Spin-lock via pause + SwitchToThread (default on modern CPUs)
    2. EnterCriticalSection / LeaveCriticalSection (fallback)

  Path 2 is taken when CpuFeaturePauseAndSwitch = False, which
  happens when DisablePauseAndSwitchToThread is defined or the CPU
  lacks the pause instruction.

  Critical section defines (on by default in FastMM4Options.inc):
    SmallBlocksLockedCriticalSection
    MediumBlocksLockedCriticalSection
    LargeBlocksLockedCriticalSection

  To exercise the critical section code path, compile with
  -dDisablePauseAndSwitchToThread. Otherwise, on modern CPUs,
  spin-locks are used and EnterCriticalSection is not called.

  Platform implementations of critical sections:
    Windows:      native CRITICAL_SECTION API
    Linux/FPC:    FPC RTL InitCriticalSection/DoneCriticalSection
    Linux/Delphi: direct pthread_mutex calls (see issue #39)
}

{$IFNDEF UNIX}
{$APPTYPE CONSOLE}
{$ENDIF}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  FastMM4 in '../../FastMM4.pas',
  FastMM4Messages in '../../FastMM4Messages.pas',
  {$IFDEF FPC}
  SysUtils,
  Classes;
  {$ELSE}
  System.SysUtils,
  System.Classes;
  {$ENDIF}

const
  TEST_PASSED = 0;
  TEST_FAILED = 1;
  ThreadCount = 8;
  IterationsPerThread = 500;

var
  GTestsPassed: Integer = 0;
  GTestsFailed: Integer = 0;
  GExitCode: Integer = TEST_PASSED;

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
// Report which critical section modes are active
// =============================================================================
procedure ReportCSConfig;
begin
  Log('Lock configuration (compile-time):');
  {$IFDEF DisablePauseAndSwitchToThread}
  Log('  DisablePauseAndSwitchToThread = YES (critical sections forced)');
  {$ELSE}
  Log('  DisablePauseAndSwitchToThread = no (spin-lock path on modern CPUs)');
  {$ENDIF}
  {$IFDEF ForceSingleThreaded}
  Log('  ForceSingleThreaded = YES (threads disabled)');
  {$ELSE}
  Log('  ForceSingleThreaded = no');
  {$ENDIF}
  Log('  Note: SmallBlocksLockedCriticalSection, MediumBlocksLockedCriticalSection,');
  Log('  LargeBlocksLockedCriticalSection are on by default in FastMM4Options.inc');
  Log('');
end;

// =============================================================================
// Thread that hammers small block allocations (< 2560 bytes)
// =============================================================================
type
  TSmallBlockThread = class(TThread)
  private
    FSuccess: Boolean;
    FId: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(AId: Integer);
    property Success: Boolean read FSuccess;
  end;

constructor TSmallBlockThread.Create(AId: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FId := AId;
  FSuccess := True;
end;

procedure TSmallBlockThread.Execute;
const
  Count = 50;
var
  Ptrs: array[0..Count-1] of Pointer;
  i, Iter: Integer;
  P: PByte;
  Size: Integer;
begin
  for Iter := 0 to IterationsPerThread - 1 do
  begin
    for i := 0 to Count - 1 do
      Ptrs[i] := nil;

    { Allocate small blocks of varying sizes }
    for i := 0 to Count - 1 do
    begin
      Size := ((FId * 7 + i * 13 + Iter) mod 200) * 12 + 8;
      if Size > 2500 then Size := 2500;
      GetMem(Ptrs[i], Size);
      if Ptrs[i] = nil then
      begin
        FSuccess := False;
        Exit;
      end;
      { Write pattern }
      P := Ptrs[i];
      P[0] := Byte(FId);
      P[Size - 1] := Byte(FId xor $FF);
    end;

    { Verify and free }
    for i := 0 to Count - 1 do
    begin
      if Ptrs[i] <> nil then
      begin
        P := Ptrs[i];
        Size := ((FId * 7 + i * 13 + Iter) mod 200) * 12 + 8;
        if Size > 2500 then Size := 2500;
        if (P[0] <> Byte(FId)) or (P[Size - 1] <> Byte(FId xor $FF)) then
          FSuccess := False;
        FreeMem(Ptrs[i]);
      end;
    end;
  end;
end;

// =============================================================================
// Thread that hammers medium block allocations (2.5KB - 260KB)
// =============================================================================
type
  TMediumBlockThread = class(TThread)
  private
    FSuccess: Boolean;
    FId: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(AId: Integer);
    property Success: Boolean read FSuccess;
  end;

constructor TMediumBlockThread.Create(AId: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FId := AId;
  FSuccess := True;
end;

procedure TMediumBlockThread.Execute;
const
  Count = 20;
var
  Ptrs: array[0..Count-1] of Pointer;
  i, Iter: Integer;
  P: PByte;
  Size: Integer;
begin
  for Iter := 0 to IterationsPerThread - 1 do
  begin
    for i := 0 to Count - 1 do
      Ptrs[i] := nil;

    for i := 0 to Count - 1 do
    begin
      Size := 3000 + ((FId * 11 + i * 17 + Iter) mod 100) * 2500;
      if Size > 250000 then Size := 250000;
      GetMem(Ptrs[i], Size);
      if Ptrs[i] = nil then
      begin
        FSuccess := False;
        Exit;
      end;
      P := Ptrs[i];
      P[0] := Byte(FId);
      P[Size - 1] := Byte(FId xor $AA);
    end;

    for i := 0 to Count - 1 do
    begin
      if Ptrs[i] <> nil then
      begin
        P := Ptrs[i];
        Size := 3000 + ((FId * 11 + i * 17 + Iter) mod 100) * 2500;
        if Size > 250000 then Size := 250000;
        if (P[0] <> Byte(FId)) or (P[Size - 1] <> Byte(FId xor $AA)) then
          FSuccess := False;
        FreeMem(Ptrs[i]);
      end;
    end;
  end;
end;

// =============================================================================
// Thread that hammers large block allocations (> 260KB)
// =============================================================================
type
  TLargeBlockThread = class(TThread)
  private
    FSuccess: Boolean;
    FId: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(AId: Integer);
    property Success: Boolean read FSuccess;
  end;

constructor TLargeBlockThread.Create(AId: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FId := AId;
  FSuccess := True;
end;

procedure TLargeBlockThread.Execute;
const
  Count = 5;
  ReducedIterations = 50;
var
  Ptrs: array[0..Count-1] of Pointer;
  i, Iter: Integer;
  P: PByte;
  Size: Integer;
begin
  for Iter := 0 to ReducedIterations - 1 do
  begin
    for i := 0 to Count - 1 do
      Ptrs[i] := nil;

    for i := 0 to Count - 1 do
    begin
      Size := 300000 + ((FId * 13 + i * 19 + Iter) mod 20) * 50000;
      GetMem(Ptrs[i], Size);
      if Ptrs[i] = nil then
      begin
        FSuccess := False;
        Exit;
      end;
      P := Ptrs[i];
      P[0] := Byte(FId);
      P[Size - 1] := Byte(FId xor $55);
    end;

    for i := 0 to Count - 1 do
    begin
      if Ptrs[i] <> nil then
      begin
        P := Ptrs[i];
        Size := 300000 + ((FId * 13 + i * 19 + Iter) mod 20) * 50000;
        if (P[0] <> Byte(FId)) or (P[Size - 1] <> Byte(FId xor $55)) then
          FSuccess := False;
        FreeMem(Ptrs[i]);
      end;
    end;
  end;
end;

// =============================================================================
// Thread that mixes small+medium+large allocations
// =============================================================================
type
  TMixedBlockThread = class(TThread)
  private
    FSuccess: Boolean;
    FId: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(AId: Integer);
    property Success: Boolean read FSuccess;
  end;

constructor TMixedBlockThread.Create(AId: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FId := AId;
  FSuccess := True;
end;

procedure TMixedBlockThread.Execute;
const
  Count = 30;
var
  Ptrs: array[0..Count-1] of Pointer;
  Sizes: array[0..Count-1] of Integer;
  i, j, Iter: Integer;
  P: PByte;
  Seed: Integer;
begin
  Seed := FId * 7919;
  for Iter := 0 to IterationsPerThread - 1 do
  begin
    for i := 0 to Count - 1 do
    begin
      Ptrs[i] := nil;
      { Simple PRNG for reproducible mixed sizes }
      Seed := (Int64(Seed) * 1103515245 + 12345) and $7FFFFFFF;
      case (Seed mod 3) of
        0: Sizes[i] := (Seed mod 2000) + 8;       { small: 8-2007 }
        1: Sizes[i] := (Seed mod 200000) + 3000;   { medium: 3000-202999 }
        2: Sizes[i] := (Seed mod 500000) + 300000;  { large: 300000-799999 }
      end;
    end;

    for i := 0 to Count - 1 do
    begin
      GetMem(Ptrs[i], Sizes[i]);
      if Ptrs[i] = nil then
      begin
        FSuccess := False;
        { Free what we allocated so far }
        if i > 0 then
          for j := 0 to i - 1 do
            if Ptrs[j] <> nil then FreeMem(Ptrs[j]);
        Exit;
      end;
      P := Ptrs[i];
      P[0] := Byte(FId);
      P[Sizes[i] - 1] := Byte(i);
    end;

    for i := 0 to Count - 1 do
    begin
      if Ptrs[i] <> nil then
      begin
        P := Ptrs[i];
        if (P[0] <> Byte(FId)) or (P[Sizes[i] - 1] <> Byte(i)) then
          FSuccess := False;
        FreeMem(Ptrs[i]);
      end;
    end;
  end;
end;

// =============================================================================
// Test runners
// =============================================================================

{$IFNDEF ForceSingleThreaded}

procedure TestConcurrentSmallBlocks;
const
  TestName = 'ConcurrentSmallBlocks';
var
  Threads: array[0..ThreadCount-1] of TSmallBlockThread;
  i: Integer;
  AllOK: Boolean;
begin
  AllOK := True;
  for i := 0 to ThreadCount - 1 do
    Threads[i] := TSmallBlockThread.Create(i + 1);
  for i := 0 to ThreadCount - 1 do
    Threads[i].Start;
  for i := 0 to ThreadCount - 1 do
  begin
    Threads[i].WaitFor;
    if not Threads[i].Success then AllOK := False;
    Threads[i].Free;
  end;
  if AllOK then TestPass(TestName)
  else TestFail(TestName, 'Data corruption detected under concurrent small block load');
end;

procedure TestConcurrentMediumBlocks;
const
  TestName = 'ConcurrentMediumBlocks';
var
  Threads: array[0..ThreadCount-1] of TMediumBlockThread;
  i: Integer;
  AllOK: Boolean;
begin
  AllOK := True;
  for i := 0 to ThreadCount - 1 do
    Threads[i] := TMediumBlockThread.Create(i + 1);
  for i := 0 to ThreadCount - 1 do
    Threads[i].Start;
  for i := 0 to ThreadCount - 1 do
  begin
    Threads[i].WaitFor;
    if not Threads[i].Success then AllOK := False;
    Threads[i].Free;
  end;
  if AllOK then TestPass(TestName)
  else TestFail(TestName, 'Data corruption detected under concurrent medium block load');
end;

procedure TestConcurrentLargeBlocks;
const
  TestName = 'ConcurrentLargeBlocks';
var
  Threads: array[0..ThreadCount-1] of TLargeBlockThread;
  i: Integer;
  AllOK: Boolean;
begin
  AllOK := True;
  for i := 0 to ThreadCount - 1 do
    Threads[i] := TLargeBlockThread.Create(i + 1);
  for i := 0 to ThreadCount - 1 do
    Threads[i].Start;
  for i := 0 to ThreadCount - 1 do
  begin
    Threads[i].WaitFor;
    if not Threads[i].Success then AllOK := False;
    Threads[i].Free;
  end;
  if AllOK then TestPass(TestName)
  else TestFail(TestName, 'Data corruption detected under concurrent large block load');
end;

procedure TestConcurrentMixedBlocks;
const
  TestName = 'ConcurrentMixedBlocks';
var
  Threads: array[0..ThreadCount-1] of TMixedBlockThread;
  i: Integer;
  AllOK: Boolean;
begin
  AllOK := True;
  for i := 0 to ThreadCount - 1 do
    Threads[i] := TMixedBlockThread.Create(i + 1);
  for i := 0 to ThreadCount - 1 do
    Threads[i].Start;
  for i := 0 to ThreadCount - 1 do
  begin
    Threads[i].WaitFor;
    if not Threads[i].Success then AllOK := False;
    Threads[i].Free;
  end;
  if AllOK then TestPass(TestName)
  else TestFail(TestName, 'Data corruption detected under concurrent mixed block load');
end;

{$ENDIF}

// =============================================================================
// Main
// =============================================================================
begin
  try
    Log('FastMM4-AVX Critical Section Test');
    Log('==================================');
    Log('');
    ReportCSConfig;

    {$IFNDEF ForceSingleThreaded}
    Log('Running concurrent tests with ' + IntToStr(ThreadCount) + ' threads...');
    Log('');

    TestConcurrentSmallBlocks;
    TestConcurrentMediumBlocks;
    TestConcurrentLargeBlocks;
    TestConcurrentMixedBlocks;
    {$ELSE}
    Log('[SKIP] All concurrent tests (ForceSingleThreaded defined)');
    {$ENDIF}

    Log('');
    Log('==================================');
    Log('Results: ' + IntToStr(GTestsPassed) + ' passed, ' + IntToStr(GTestsFailed) + ' failed');
    Log('');

    if GExitCode <> TEST_PASSED then
      Log('TESTS FAILED!')
    else
      Log('ALL TESTS PASSED!');

    ExitCode := GExitCode;

  except
    on E: Exception do
    begin
      WriteLn('FATAL ERROR: ', E.ClassName, ': ', E.Message);
      Flush(Output);
      ExitCode := TEST_FAILED;
    end;
  end;
end.
