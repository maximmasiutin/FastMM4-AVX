program ReleaseStackTest;

{$APPTYPE CONSOLE}

{Regression test for UseReleaseStack in the default builds, where the small,
 medium and large blocks are locked through the critical-section options.
 FreeMediumBlock and FreeLargeBlock passed the address of an uninitialized
 local flag to LockMediumBlocks and LockLargeBlocks, which write it only in
 the builds without those options, and then returned early whenever the flag
 happened to be nonzero: the block stayed allocated and the medium or large
 lock stayed held.

 Build with UseReleaseStack and NoMessageBoxes; DisablePauseAndSwitchToThread
 selects the EnterCriticalSection path instead of the lock byte.

 Exit codes: 0 pass; 1 a block that FreeMem did not release; 2 the workload
 did not run (a worker did not start, the wait for the workers failed, the
 watchdog could not be created, or the parameter is unknown); 3 a hang that
 the watchdog ended. The parameters start-none, start-partial, wait-fail and
 watchdog-fail simulate those failures, and each must end with exit code 2.}

uses
  FastMM4 in '..\..\FastMM4.pas',
  FastMM4LockFreeStack in '..\..\FastMM4LockFreeStack.pas',
  FastMM4Messages in '..\..\FastMM4Messages.pas',
  Windows;

const
  ThreadCount = 4;
  Iterations = 2000;
  ThreadRounds = 50;
  WatchdogMilliseconds = 120000;
  ExitLeak = 1;
  ExitNotRun = 2;
  ExitHang = 3;

var
  Failures: Integer;
  Fault: string;

{The watchdog runs on a thread created with CreateThread and calls only the
 Windows API, so it neither allocates nor needs the RTL thread setup. A
 process still alive when it wakes is hung, wherever that happened.}
function Watchdog(AParam: Pointer): DWORD; stdcall;
begin
  Sleep(WatchdogMilliseconds);
  TerminateProcess(GetCurrentProcess, ExitHang);
  Result := 0;
end;

procedure Report(const AText: string);
begin
  {Flushed at once, so a run the watchdog ends still shows how far it got.}
  WriteLn(AText);
  Flush(Output);
end;

function CardinalToStr(AValue: Cardinal): string;
var
  LText: ShortString;
begin
  Str(AValue, LText);
  Result := string(LText);
end;

procedure GetCounts(var AMedium, ALarge: Cardinal);
var
  LState: FastMM4.TMemoryManagerState;
begin
  FastMM4.GetMemoryManagerState(LState);
  AMedium := LState.AllocatedMediumBlockCount;
  ALarge := LState.AllocatedLargeBlockCount;
end;

procedure CheckCounts(const APhase: string; ABaseMedium, ABaseLarge: Cardinal);
var
  LMedium, LLarge: Cardinal;
begin
  GetCounts(LMedium, LLarge);
  Report(APhase + ': medium ' + CardinalToStr(LMedium) + ' (baseline '
    + CardinalToStr(ABaseMedium) + '), large ' + CardinalToStr(LLarge)
    + ' (baseline ' + CardinalToStr(ABaseLarge) + ')');
  if (LMedium <> ABaseMedium) or (LLarge <> ABaseLarge) then
    Inc(Failures);
end;

procedure AllocateAndFree(AIndex: Integer);
var
  LPointer: Pointer;
begin
  GetMem(LPointer, 16 + (AIndex and 255));
  FreeMem(LPointer);
  GetMem(LPointer, 4096 + (AIndex and 63) * 2048);
  FreeMem(LPointer);
  GetMem(LPointer, 300000 + (AIndex and 7) * 65536);
  FreeMem(LPointer);
end;

function AllocatingWorker(AParam: Pointer): {$IFDEF FPC}PtrInt{$ELSE}Integer{$ENDIF};
var
  LIndex: Integer;
begin
  for LIndex := 1 to Iterations do
    AllocateAndFree(LIndex);
  Result := 0;
end;

function IdleWorker(AParam: Pointer): {$IFDEF FPC}PtrInt{$ELSE}Integer{$ENDIF};
begin
  Result := 0;
end;

{Starts ThreadCount workers and joins every one that started. A phase whose
 workers did not all start has not run the workload it names, so it ends the
 run with ExitNotRun once the started ones are joined, rather than checking
 counts. A failed wait leaves workers that may still be running, so neither
 the counts nor the memory manager's shutdown can be trusted, and the process
 ends at once. AInjectFaults lets the fault parameters act on this call.}
procedure RunThreads(AAllocating, AInjectFaults: Boolean);
var
  LIndex, LStarted, LNotStarted: Integer;
  LThreadId: Cardinal;
  LThread: THandle;
  LThreads: array[0..ThreadCount - 1] of THandle;
  LWaitCount, LStartError, LWaitError: DWORD;
begin
  LStarted := 0;
  LNotStarted := 0;
  LStartError := 0;
  for LIndex := 0 to ThreadCount - 1 do
  begin
    if AInjectFaults and ((Fault = 'start-none')
      or ((Fault = 'start-partial') and (LIndex = 1))) then
    begin
      SetLastError(ERROR_NOT_ENOUGH_MEMORY);
      LThread := 0;
    end
    else if AAllocating then
      LThread := BeginThread(nil, 0, @AllocatingWorker, nil, 0, LThreadId)
    else
      LThread := BeginThread(nil, 0, @IdleWorker, nil, 0, LThreadId);
    if LThread = 0 then
    begin
      if LNotStarted = 0 then
        LStartError := GetLastError;
      Inc(LNotStarted);
    end
    else
    begin
      LThreads[LStarted] := LThread;
      Inc(LStarted);
    end;
  end;
  if LStarted > 0 then
  begin
    LWaitCount := LStarted;
    {A zero count makes the wait fail at once while the workers run.}
    if AInjectFaults and (Fault = 'wait-fail') then
      LWaitCount := 0;
    if WaitForMultipleObjects(LWaitCount, @LThreads, True, INFINITE) = WAIT_FAILED then
    begin
      LWaitError := GetLastError;
      Report('ReleaseStackTest NOT RUN: the wait for the workers failed, error '
        + CardinalToStr(LWaitError));
      TerminateProcess(GetCurrentProcess, ExitNotRun);
    end;
    for LIndex := 0 to LStarted - 1 do
      CloseHandle(LThreads[LIndex]);
  end;
  if LNotStarted > 0 then
  begin
    Report('ReleaseStackTest NOT RUN: ' + CardinalToStr(LNotStarted) + ' of '
      + CardinalToStr(ThreadCount) + ' workers did not start, error '
      + CardinalToStr(LStartError));
    Halt(ExitNotRun);
  end;
end;

var
  LIndex: Integer;
  LWatchdog: THandle;
  LWatchdogId: DWORD;
  LBaseMedium, LBaseLarge: Cardinal;
begin
  Failures := 0;
  Fault := ParamStr(1);
  if (Fault <> '') and (Fault <> 'start-none') and (Fault <> 'start-partial')
    and (Fault <> 'wait-fail') and (Fault <> 'watchdog-fail') then
  begin
    Report('ReleaseStackTest NOT RUN: unknown parameter ' + Fault);
    Halt(ExitNotRun);
  end;

  {Without the watchdog a hang would not end with ExitHang, so the run stops
   before any workload when the watchdog cannot be created.}
  if Fault = 'watchdog-fail' then
    LWatchdog := 0
  else
    LWatchdog := CreateThread(nil, 0, @Watchdog, nil, 0, LWatchdogId);
  if LWatchdog = 0 then
  begin
    Report('ReleaseStackTest NOT RUN: the watchdog thread could not be created');
    Halt(ExitNotRun);
  end;
  CloseHandle(LWatchdog);

  {Each medium and large FreeMem here reaches LockMediumBlocks or
   LockLargeBlocks although the test has started no thread yet:
   FastMM4Options.inc defines AssumeMultiThreaded, and in a build without it
   IsMultiThread is already True, because the release-stack cleanup thread is
   started with BeginThread when the memory manager installs. The main thread
   alone was enough to hang: a medium free that left the lock byte held made
   the next medium lock on the same thread spin on it.}
  GetCounts(LBaseMedium, LBaseLarge);
  for LIndex := 1 to Iterations do
    AllocateAndFree(LIndex);
  CheckCounts('main thread', LBaseMedium, LBaseLarge);

  GetCounts(LBaseMedium, LBaseLarge);
  Report('multithreaded: starting');
  RunThreads(True, True);
  CheckCounts('multithreaded', LBaseMedium, LBaseLarge);

  {Thread creation and exit alone, which once left a run unable to exit.}
  for LIndex := 1 to ThreadRounds do
    RunThreads(False, False);
  CheckCounts('threads only', LBaseMedium, LBaseLarge);

  if Failures = 0 then
    Report('ReleaseStackTest PASS')
  else
  begin
    Report('ReleaseStackTest FAIL');
    ExitCode := ExitLeak;
  end;
end.
