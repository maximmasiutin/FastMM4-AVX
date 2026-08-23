program ConcurrentForeignPointerStressTest;

{ Extended SoftInvalidFreeMem stress test. Eight workers present controlled
  CRT-owned foreign pointers to FastMM while eight workers exercise normal
  FastMM allocation paths. CI uses a two-second run. Define LongStressTest for
  a ten-second local or extended run. A separate watchdog bounds shutdown. }

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
  FastMM4 in '..\..\FastMM4.pas',
  FastMM4Messages in '..\..\FastMM4Messages.pas',
  Classes,
  SysUtils;

{$IFDEF MSWINDOWS}
function SetErrorMode(uMode: Cardinal): Cardinal; stdcall;
  external 'kernel32' name 'SetErrorMode';
const
  SEM_FAILCRITICALERRORS = $0001;
  SEM_NOGPFAULTERRORBOX = $0002;
{$ENDIF}

{$IFDEF MSWINDOWS}
function cmalloc(Size: PtrUInt): Pointer; cdecl;
  external 'msvcrt' name 'malloc';
procedure cfree(P: Pointer); cdecl;
  external 'msvcrt' name 'free';
{$ELSE}
function cmalloc(Size: PtrUInt): Pointer; cdecl;
  external 'c' name 'malloc';
procedure cfree(P: Pointer); cdecl;
  external 'c' name 'free';
{$ENDIF}

const
  WorkerCount = 8;
  {$IFDEF LongStressTest}
  StressDurationMS = 10000;
  {$ELSE}
  {$IFDEF CheckedStressTest}
  StressDurationMS = 1000;
  {$ELSE}
  StressDurationMS = 2000;
  {$ENDIF}
  {$ENDIF}
  ShutdownTimeoutMS = 3000;
  PollIntervalMS = 25;
  AllocationSizeCount = 6;
  AllocationSizes: array[0..AllocationSizeCount - 1] of PtrUInt =
    (16, 64, 512, 8192, 131072, 1048576);

type
  TWorkerKind = (wkForeign, wkNormal);
  TFailureKind = (fkNone, fkAllocation, fkFreeResult, fkFreeException,
    fkReallocResult, fkReallocException, fkPattern);

  TStressThread = class(TThread)
  private
    FFailure: TFailureKind;
    FFailureIteration: Integer;
    FFreeOperations: Integer;
    FInitialSeed: Cardinal;
    FOperations: Integer;
    FRandomState: Cardinal;
    FReallocOperations: Integer;
    FWorkerId: Integer;
    FWorkerKind: TWorkerKind;
  protected
    procedure Execute; override;
    function NextRandom: Cardinal;
    procedure RecordFailure(AFailure: TFailureKind; AIteration: Integer);
    { Overridden by each worker kind. Execute wraps it so that the completed
      count rises even when the body exits early or raises. }
    procedure Run; virtual; abstract;
  public
    constructor Create(AWorkerKind: TWorkerKind; AWorkerId: Integer;
      ASeed: Cardinal);
    property Failure: TFailureKind read FFailure;
    property FailureIteration: Integer read FFailureIteration;
    property FreeOperations: Integer read FFreeOperations;
    property InitialSeed: Cardinal read FInitialSeed;
    property Operations: Integer read FOperations;
    property ReallocOperations: Integer read FReallocOperations;
    property WorkerId: Integer read FWorkerId;
    property WorkerKind: TWorkerKind read FWorkerKind;
  end;

  TForeignPointerThread = class(TStressThread)
  protected
    procedure Run; override;
  end;

  TNormalAllocationThread = class(TStressThread)
  protected
    procedure Run; override;
  end;

  TShutdownWatchdog = class(TThread)
  private
    FArmed: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create;
    procedure Disarm;
  end;

var
  { Raised by each worker as it leaves Run, whether it finished, exited early
    or raised. The watchdog reads it instead of trusting that the main thread
    reaches Disarm promptly after the last WaitFor. }
  CompletedWorkers: Integer = 0;

function FailureName(AFailure: TFailureKind): ShortString;
begin
  case AFailure of
    fkNone: FailureName := 'none';
    fkAllocation: FailureName := 'allocation failed';
    fkFreeResult: FailureName := 'FreeMem returned non-zero for foreign pointer';
    fkFreeException: FailureName := 'FreeMem raised an exception';
    fkReallocResult: FailureName := 'ReallocMem accepted foreign pointer';
    fkReallocException: FailureName := 'ReallocMem raised an exception';
    fkPattern: FailureName := 'normal allocation pattern changed';
  end;
end;

procedure FatalForeignFailure(AWorkerId: Integer; ASeed: Cardinal;
  AIteration: Integer; AFailure: TFailureKind);
begin
  { An allocator fault or unexpected success makes ownership uncertain. Stop
    without freeing thread objects through an allocator that may be damaged. }
  Write('[FAIL] foreign worker ');
  Write(AWorkerId);
  Write(', seed ');
  Write(ASeed);
  Write(', iteration ');
  Write(AIteration);
  Write(': ');
  WriteLn(FailureName(AFailure));
  Flush(Output);
  Halt(1);
end;

constructor TStressThread.Create(AWorkerKind: TWorkerKind;
  AWorkerId: Integer; ASeed: Cardinal);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FFailure := fkNone;
  FFailureIteration := -1;
  FFreeOperations := 0;
  FInitialSeed := ASeed;
  FOperations := 0;
  FRandomState := ASeed;
  FReallocOperations := 0;
  FWorkerId := AWorkerId;
  FWorkerKind := AWorkerKind;
end;

procedure TStressThread.Execute;
begin
  try
    Run;
  finally
    InterlockedIncrement(CompletedWorkers);
  end;
end;

function TStressThread.NextRandom: Cardinal;
begin
  FRandomState := Cardinal((UInt64(FRandomState) * 1664525 + 1013904223)
    and $FFFFFFFF);
  Result := FRandomState;
end;

procedure TStressThread.RecordFailure(AFailure: TFailureKind;
  AIteration: Integer);
begin
  if FFailure = fkNone then
  begin
    FFailure := AFailure;
    FFailureIteration := AIteration;
  end;
end;

procedure TForeignPointerThread.Run;
var
  AllocationSize: PtrUInt;
  BaseP, ForeignP, NewP: Pointer;
  Iteration, SizeIndex: Integer;
  { The one-argument FreeMem returns a pointer-sized result. Narrowing it to
    Integer would let -Cr raise a range error before fkFreeResult is recorded. }
  Res: NativeUInt;
begin
  Iteration := 0;
  while not Terminated do
  begin
    SizeIndex := NextRandom mod AllocationSizeCount;
    AllocationSize := AllocationSizes[SizeIndex];
    BaseP := cmalloc(AllocationSize);
    if BaseP = nil then
    begin
      RecordFailure(fkAllocation, Iteration);
      Exit;
    end;
    ForeignP := PByte(BaseP) + SizeOf(Pointer);
    PPtrUInt(PByte(ForeignP) - SizeOf(Pointer))^ := $0080;

    { Do not select on the low LCG bit: it alternates predictably, and two
      random draws per loop would make each worker choose only one operation. }
    if (NextRandom and $100) = 0 then
    begin
      try
        Res := FreeMem(ForeignP);
      except
        on E: Exception do
        begin
          cfree(BaseP);
          FatalForeignFailure(WorkerId, InitialSeed, Iteration,
            fkFreeException);
          Exit;
        end;
      end;
      cfree(BaseP);
      if Res <> 0 then
      begin
        RecordFailure(fkFreeResult, Iteration);
        Exit;
      end;
      Inc(FFreeOperations);
    end
    else
    begin
      NewP := ForeignP;
      try
        ReallocMem(NewP, AllocationSize * 2);
      except
        on E: Exception do
        begin
          cfree(BaseP);
          FatalForeignFailure(WorkerId, InitialSeed, Iteration,
            fkReallocException);
          Exit;
        end;
      end;
      if (NewP <> nil) and (NewP <> ForeignP) then
      begin
        FatalForeignFailure(WorkerId, InitialSeed, Iteration,
          fkReallocResult);
        Exit;
      end;
      cfree(BaseP);
      Inc(FReallocOperations);
    end;
    Inc(FOperations);
    Inc(Iteration);
  end;
end;

procedure TNormalAllocationThread.Run;
var
  AllocationSize, NewSize: PtrUInt;
  Iteration, SizeIndex: Integer;
  P: Pointer;
  Pattern: Byte;
begin
  Iteration := 0;
  while not Terminated do
  begin
    SizeIndex := NextRandom mod AllocationSizeCount;
    AllocationSize := AllocationSizes[SizeIndex];
    GetMem(P, AllocationSize);
    if P = nil then
    begin
      RecordFailure(fkAllocation, Iteration);
      Exit;
    end;
    Pattern := Byte(WorkerId xor Iteration);
    PByte(P)[0] := Pattern;
    PByte(P)[AllocationSize - 1] := Pattern xor $FF;

    if (NextRandom and 3) = 0 then
    begin
      NewSize := AllocationSize + (NextRandom mod 4096) + 1;
      ReallocMem(P, NewSize);
      if P = nil then
      begin
        RecordFailure(fkAllocation, Iteration);
        Exit;
      end;
      { NewSize always exceeds AllocationSize, so the old final byte survives
        the growth and is checked here as well as the first. Checking only the
        first would miss corruption or truncation at the old end. }
      if (PByte(P)[0] <> Pattern)
        or (PByte(P)[AllocationSize - 1] <> (Pattern xor $FF)) then
      begin
        FreeMem(P);
        RecordFailure(fkPattern, Iteration);
        Exit;
      end;
    end
    else if (PByte(P)[0] <> Pattern)
      or (PByte(P)[AllocationSize - 1] <> (Pattern xor $FF)) then
    begin
      FreeMem(P);
      RecordFailure(fkPattern, Iteration);
      Exit;
    end;
    FreeMem(P);
    Inc(FOperations);
    Inc(Iteration);
  end;
end;

constructor TShutdownWatchdog.Create;
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FArmed := True;
end;

procedure TShutdownWatchdog.Disarm;
begin
  FArmed := False;
  Terminate;
end;

procedure TShutdownWatchdog.Execute;
var
  Elapsed: Integer;
begin
  Elapsed := 0;
  while (Elapsed < StressDurationMS + ShutdownTimeoutMS) and
    not Terminated do
  begin
    Sleep(PollIntervalMS);
    Inc(Elapsed, PollIntervalMS);
  end;
  { Disarm runs only after the last WaitFor, so a main thread preempted in
    that window would otherwise be halted here although every worker had
    stopped. The completed count settles the question without that race. }
  if FArmed and not Terminated
    and (InterlockedExchangeAdd(CompletedWorkers, 0) < WorkerCount * 2) then
  begin
    WriteLn('[FAIL] concurrent stress shutdown timeout');
    Flush(Output);
    Halt(1);
  end;
end;

procedure ReportWorkerFailure(AThread: TStressThread);
begin
  Write('[FAIL] ');
  if AThread.WorkerKind = wkForeign then
    Write('foreign')
  else
    Write('normal');
  Write(' worker ');
  Write(AThread.WorkerId);
  Write(', seed ');
  Write(AThread.InitialSeed);
  Write(', iteration ');
  Write(AThread.FailureIteration);
  Write(': ');
  WriteLn(FailureName(AThread.Failure));
end;

{ FreePascal stores an exception that escapes Execute in FatalException and
  WaitFor does not re-raise it, so a worker killed by an allocator fault would
  otherwise leave the run reporting success. }
function ReportFatalException(AThread: TStressThread): Boolean;
var
  Raised: Boolean;
begin
  Raised := Assigned(AThread.FatalException);
  ReportFatalException := Raised;
  if not Raised then
    Exit;
  Write('[FAIL] ');
  if AThread.WorkerKind = wkForeign then
    Write('foreign')
  else
    Write('normal');
  Write(' worker ');
  Write(AThread.WorkerId);
  Write(', seed ');
  Write(AThread.InitialSeed);
  Write(': unhandled ');
  WriteLn(AThread.FatalException.ClassName);
end;

{ Reported rather than failed. A runner with fewer cores than workers can leave
  one thread unscheduled for the whole window, which says nothing about the
  allocator: CI saw normal worker 6 idle while the other workers completed
  4827689 operations. The aggregate checks below are what guard coverage. }
procedure ReportIdleWorker(AThread: TStressThread);
begin
  if AThread.Operations <> 0 then
    Exit;
  Write('[WARN] ');
  if AThread.WorkerKind = wkForeign then
    Write('foreign')
  else
    Write('normal');
  Write(' worker ');
  Write(AThread.WorkerId);
  WriteLn(' performed no operation');
end;

var
  ForeignThreads: array[0..WorkerCount - 1] of TForeignPointerThread;
  NormalThreads: array[0..WorkerCount - 1] of TNormalAllocationThread;
  Watchdog: TShutdownWatchdog;
  Elapsed, I, TotalForeignFreeOperations, TotalForeignOperations,
    TotalForeignReallocOperations, TotalNormalOperations: Integer;
  Failed: Boolean;
begin
  {$IFDEF MSWINDOWS}
  SetErrorMode(SEM_FAILCRITICALERRORS or SEM_NOGPFAULTERRORBOX);
  {$ENDIF}
  WriteLn('FastMM4-AVX Concurrent Foreign Pointer Stress Test');
  {$IFDEF CheckedStressTest}
  WriteLn('8 foreign workers + 8 normal workers, 1 second');
  {$ELSE}
  Write('8 foreign workers + 8 normal workers, ');
  Write(StressDurationMS div 1000);
  WriteLn(' seconds');
  {$ENDIF}
  WriteLn('Foreign seed base: $46505200; normal seed base: $4E4F5200');
  Flush(Output);

  for I := 0 to WorkerCount - 1 do
    ForeignThreads[I] := TForeignPointerThread.Create(wkForeign, I,
      $46505200 + Cardinal(I));
  for I := 0 to WorkerCount - 1 do
    NormalThreads[I] := TNormalAllocationThread.Create(wkNormal, I,
      $4E4F5200 + Cardinal(I));
  Watchdog := TShutdownWatchdog.Create;

  for I := 0 to WorkerCount - 1 do
    ForeignThreads[I].Start;
  for I := 0 to WorkerCount - 1 do
    NormalThreads[I].Start;
  Watchdog.Start;

  Elapsed := 0;
  while Elapsed < StressDurationMS do
  begin
    Sleep(PollIntervalMS);
    Inc(Elapsed, PollIntervalMS);
  end;

  for I := 0 to WorkerCount - 1 do
  begin
    ForeignThreads[I].Terminate;
    NormalThreads[I].Terminate;
  end;
  for I := 0 to WorkerCount - 1 do
  begin
    ForeignThreads[I].WaitFor;
    NormalThreads[I].WaitFor;
  end;

  Watchdog.Disarm;
  Watchdog.WaitFor;
  Failed := False;
  TotalForeignFreeOperations := 0;
  TotalForeignOperations := 0;
  TotalForeignReallocOperations := 0;
  TotalNormalOperations := 0;
  for I := 0 to WorkerCount - 1 do
  begin
    Inc(TotalForeignOperations, ForeignThreads[I].Operations);
    Inc(TotalForeignFreeOperations, ForeignThreads[I].FreeOperations);
    Inc(TotalForeignReallocOperations, ForeignThreads[I].ReallocOperations);
    Inc(TotalNormalOperations, NormalThreads[I].Operations);
    if ForeignThreads[I].Failure <> fkNone then
    begin
      ReportWorkerFailure(ForeignThreads[I]);
      Failed := True;
    end;
    if NormalThreads[I].Failure <> fkNone then
    begin
      ReportWorkerFailure(NormalThreads[I]);
      Failed := True;
    end;
    if ReportFatalException(ForeignThreads[I]) then
      Failed := True;
    if ReportFatalException(NormalThreads[I]) then
      Failed := True;
    ReportIdleWorker(ForeignThreads[I]);
    ReportIdleWorker(NormalThreads[I]);
  end;

  { A run that exercised none of an advertised path would otherwise report that
    path as covered. Both foreign operation types are selected at random, so
    each is checked separately from the total. }
  if TotalForeignFreeOperations = 0 then
  begin
    WriteLn('[FAIL] no foreign FreeMem operation was performed');
    Failed := True;
  end;
  if TotalForeignReallocOperations = 0 then
  begin
    WriteLn('[FAIL] no foreign ReallocMem operation was performed');
    Failed := True;
  end;
  if TotalNormalOperations = 0 then
  begin
    WriteLn('[FAIL] no normal allocation operation was performed');
    Failed := True;
  end;

  Write('Foreign operations: ');
  WriteLn(TotalForeignOperations);
  Write('  FreeMem: ');
  WriteLn(TotalForeignFreeOperations);
  Write('  ReallocMem: ');
  WriteLn(TotalForeignReallocOperations);
  Write('Normal operations: ');
  WriteLn(TotalNormalOperations);
  if Failed then
    WriteLn('TESTS FAILED!')
  else
    WriteLn('ALL TESTS PASSED!');
  Flush(Output);

  for I := 0 to WorkerCount - 1 do
  begin
    ForeignThreads[I].Free;
    NormalThreads[I].Free;
  end;
  Watchdog.Free;
  if Failed then
    Halt(1);
end.
