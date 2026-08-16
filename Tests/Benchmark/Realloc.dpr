program Realloc;

{$IFDEF FPC}
{$mode objfpc}{$H+}
{$ENDIF}

{$APPTYPE CONSOLE}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  FastMM4 in '..\..\FastMM4.pas',
  FastMM4Messages in '..\..\FastMM4Messages.pas',
  Classes,
  SysUtils;

procedure RunBenchmark;
const
  Prime = 10513;

var
  sz, i, LPointerNumber, FIterCount, NumPointers, BlockSizeDelta, MaxBlockSize, MinBlockSize: Integer;
  CurValue: Int64;
  P: PAnsiChar;

type
  PReallocMemBenchmarkBlockSizesArray = ^TReallocMemBenchmarkBlockSizesArray;
  PReallocMemBenchmarkPointerArray    = ^TReallocMemBenchmarkPointerArray;

  TReallocMemBenchmarkPointerArray    =  packed array[0..MaxInt div SizeOf(Pointer)-1] of Pointer;
  TReallocMemBenchmarkBlockSizesArray =  packed array[0..MaxInt div SizeOf(Pointer)-1] of Integer;

var
  BlockSizes: PReallocMemBenchmarkBlockSizesArray;
  Pointers: PReallocMemBenchmarkPointerArray;

begin

  MaxBlockSize := 0;
  MinBlockSize := MaxInt;
  CurValue := Prime;
  NumPointers := 20011;
  BlockSizeDelta := 257;

  GetMem(Pointers, NumPointers*SizeOf(Pointer));
  {Clear all the pointers}
  FillChar(Pointers^, NumPointers*SizeOf(Pointer), 0);

  GetMem(BlockSizes, NumPointers*SizeOf(Integer));
  {Clear all the block sizes}
  FillChar(BlockSizes^, NumPointers*SizeOf(Integer), 0);

  {Do the benchmark}
  FIterCount := 50000*1000;
  for i := 1 to FIterCount do
  begin
    {Get an arbitarry pointer number}
    LPointerNumber := CurValue mod NumPointers;
    Inc(CurValue, Prime);
    {Adjust the current block size up or down by up to BlockSizeDelta}
    BlockSizes^[LPointerNumber] := abs(BlockSizes^[LPointerNumber] + (CurValue mod BlockSizeDelta) - (BlockSizeDelta shr 1) - ((i and 7)mod BlockSizeDelta));
    Inc(CurValue, Prime);
    {Reallocate the pointer}
    if MaxBlockSize < BlockSizes^[LPointerNumber] then MaxBlockSize := BlockSizes^[LPointerNumber];
    if (BlockSizes^[LPointerNumber] > 0) and (MinBlockSize > BlockSizes^[LPointerNumber]) then MinBlockSize := BlockSizes^[LPointerNumber];

    System.ReallocMem(Pointers^[LPointerNumber], BlockSizes^[LPointerNumber]);
    {Touch the memory}
    sz := BlockSizes^[LPointerNumber];
    if sz > 0 then
    begin
      P := Pointers^[LPointerNumber];
      P[0] := #1;
      if sz > 1 then
      begin
        P[sz-1] := #2;
      end;
    end;
  end;

  {Free all residual pointers}
  for i := 0 to NumPointers - 1 do
  begin
    System.ReallocMem(Pointers^[i], 0);
  end;

  FreeMem(Pointers, NumPointers*SizeOf(Pointer));
  FreeMem(BlockSizes, NumPointers*SizeOf(Integer));
end;

type
  TBenchmarkThread = class(TThread)
    procedure Execute; override;
  end;

procedure TBenchmarkThread.Execute;
begin
  RunBenchmark;
end;

const
  CDefaultNumThreads = 12;
  CCreateSuspendedThread = True;

var
  VNumThreads: Integer;
  A: array[0..1000] of Pointer;
  i, j: Integer;
  w: Word;
  LThreads: array of TBenchmarkThread;
  LFastMMCpuSmallestMonitorLineSize, LFastMMCpuLargestMonitorLineSize: Word;

begin
  WriteLn('Usage: '+ExtractFileName(ParamStr(0))+ ' <numthreads>'{$IFDEF EnableWaitPKG}+' [disable_waitpkg]'{$ENDIF});
  VNumThreads := CDefaultNumThreads;
  if (ParamCount >= 1) then
  begin
    i := -1; j := -1;
    Val(ParamStr(1), i, j);
    if (j = 0) and (i > 0) then VNumThreads := i;
  end;
  SetLength(LThreads, VNumThreads);
  {$IFDEF EnableWaitPKG}
  if (ParamCount >= 2) then
  begin
    If ParamStr(2) = 'disable_waitpkg' then
    begin
      WriteLn('Disabling WaitPKG...');
      FastMMDisableWaitPKG;
    end;
  end;
  {$ENDIF}

  WriteLn('Running with '+IntToStr(VNumThreads)+' threads...');
  w := GetFastMMCpuFeatures;
  for i := Low(A) to High(A) do
    GetMem(A[i], i+1);
  for i := Low(A) to High(A) do
    FreeMem(A[i], i+1);
  {$IFDEF EnableWaitPKG}
  if (W and $100) <> 0 then
  begin
    WriteLn('Wait PKG is supported');
    LFastMMCpuSmallestMonitorLineSize := 0;
    LFastMMCpuLargestMonitorLineSize := 0;
    GetFastMMCpuUserModeMonitorLineSizes(LFastMMCpuSmallestMonitorLineSize, LFastMMCpuLargestMonitorLineSize);
    WriteLn('Smallest monitor line size = ', LFastMMCpuSmallestMonitorLineSize);
    WriteLn('Largest monitor line size = ', LFastMMCpuLargestMonitorLineSize);
  end else
  begin
    WriteLn('Wait PKG is not supported')
  end;
  {$ENDIF}
  for i := Low(LThreads) to High(LThreads) do
  begin
    LThreads[i] := TBenchmarkThread.Create(CCreateSuspendedThread);
  end;
  for i := Low(LThreads) to High(LThreads) do
  begin
    LThreads[i].Suspended := False;
  end;
  for i := Low(LThreads) to High(LThreads) do
  begin
    LThreads[i].WaitFor;
  end;
  for i := Low(LThreads) to High(LThreads) do
  begin
    LThreads[i].Destroy;
    LThreads[i] := nil;
  end;
end.

