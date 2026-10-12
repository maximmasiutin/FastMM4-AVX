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
 selects the EnterCriticalSection path instead of the lock byte. Exit code 0
 is a pass, 1 a block that FreeMem did not release, and 3 a hang caught by
 the watchdog.}

uses
  FastMM4,
  Windows;

const
  ThreadCount = 4;
  Iterations = 2000;
  ThreadRounds = 50;
  WatchdogMilliseconds = 120000;

var
  Failures: Integer;

{The watchdog runs on a thread created with CreateThread and calls only the
 Windows API, so it neither allocates nor needs the RTL thread setup. A
 process still alive when it wakes is hung, wherever that happened.}
function Watchdog(AParam: Pointer): DWORD; stdcall;
begin
  Sleep(WatchdogMilliseconds);
  TerminateProcess(GetCurrentProcess, 3);
  Result := 0;
end;

procedure Report(const AText: string);
begin
  {Flushed at once, so a run the watchdog ends still shows how far it got.}
  WriteLn(AText);
  Flush(Output);
end;

function CardinalToStr(AValue: Cardinal): string;
begin
  Str(AValue, Result);
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

procedure RunThreads(AAllocating: Boolean);
var
  LIndex: Integer;
  LThreadId: Cardinal;
  LThreads: array[0..ThreadCount - 1] of THandle;
begin
  for LIndex := 0 to ThreadCount - 1 do
  begin
    if AAllocating then
      LThreads[LIndex] := BeginThread(nil, 0, @AllocatingWorker, nil, 0, LThreadId)
    else
      LThreads[LIndex] := BeginThread(nil, 0, @IdleWorker, nil, 0, LThreadId);
  end;
  WaitForMultipleObjects(ThreadCount, @LThreads, True, INFINITE);
  for LIndex := 0 to ThreadCount - 1 do
    CloseHandle(LThreads[LIndex]);
end;

var
  LIndex: Integer;
  LWatchdogId: DWORD;
  LBaseMedium, LBaseLarge: Cardinal;
begin
  Failures := 0;
  CloseHandle(CreateThread(nil, 0, @Watchdog, nil, 0, LWatchdogId));

  {The release-stack cleanup thread is started with BeginThread when the
   memory manager installs, so IsMultiThread is already True here and every
   FreeMem takes the locks. The main thread alone was enough to hang: a
   medium free that left the lock byte held made the next one spin on it.}
  GetCounts(LBaseMedium, LBaseLarge);
  for LIndex := 1 to Iterations do
    AllocateAndFree(LIndex);
  CheckCounts('main thread', LBaseMedium, LBaseLarge);

  GetCounts(LBaseMedium, LBaseLarge);
  Report('multithreaded: starting');
  RunThreads(True);
  CheckCounts('multithreaded', LBaseMedium, LBaseLarge);

  {Thread creation and exit alone, which once left a run unable to exit.}
  for LIndex := 1 to ThreadRounds do
    RunThreads(False);
  CheckCounts('threads only', LBaseMedium, LBaseLarge);

  if Failures = 0 then
    Report('ReleaseStackTest PASS')
  else
  begin
    Report('ReleaseStackTest FAIL');
    ExitCode := 1;
  end;
end.
