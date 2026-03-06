program SafeLinkingTest;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

{$APPTYPE CONSOLE}

uses
  SysUtils, FastMM4 in '../../FastMM4.pas';

var
  P1, P2, P3, P4, FakeTargetStruct: Pointer;
  FakeTarget: NativeUInt;
  BlockHeaderSize: Integer;
begin
  BlockHeaderSize := SizeOf(Pointer);

  WriteLn('Testing Safe-Linking Mitigation for Small Blocks...');
  
  // Create a real block that acts as our target region 
  // (to prevent immediate access violation when reading the fake block header itself)
  GetMem(FakeTargetStruct, 64);
  FakeTarget := NativeUInt(FakeTargetStruct) + NativeUInt(BlockHeaderSize);
  
  // Initialize the fake block with a null next-free-block so it won't traverse further
  PNativeUInt(PByte(FakeTarget) - BlockHeaderSize)^ := 1; // 1 represents IsFreeBlockFlag

  // Allocate two small blocks
  GetMem(P1, 32);
  GetMem(P2, 32);
  
  // Free them so they go into the small block pool free list.
  // LIFO: FirstFreeBlock -> P2 -> P1.
  FreeMem(P1);
  FreeMem(P2);

  // Simulate CWE-416 (UAF) or CWE-787 (Out-of-bounds write)
  // Overwriting the Free header of P2 to point to FakeTarget
  // 1 is IsFreeBlockFlag
  PNativeUInt(PByte(P2) - BlockHeaderSize)^ := FakeTarget or 1;
  WriteLn('Attacker corrupted P2 header to point to: ' + IntToHex(FakeTarget, SizeOf(Pointer)*2));

  try
    // Allocate again. This pops P2 and makes FirstFreeBlock = FakeTarget
    GetMem(P3, 32);
    
    // Attempt the second allocation. 
    // Vulnerable code: successfully returns FakeTarget enabling arbitrary write capability!
    // Safe-Linking Code: attempts to deobfuscate `FakeTarget` using address context, resulting in completely random bad pointer.
    // That bad pointer causes an immediate fault attempting `LNewFirstFreeBlock := PPointer(...)` preventing the attack execution chain.
    GetMem(P4, 32);
    
    WriteLn('Allocated second block after UAF at: ' + IntToHex(NativeUInt(P4), SizeOf(Pointer)*2));
    
    if NativeUInt(P4) = FakeTarget then
    begin
      WriteLn('VULNERABLE: Safe-Linking missing! Attacker successfully forged Free List pointer.');
      Halt(1);
    end
    else
    begin
      WriteLn('SAFE: Forged pointer was safely invalidated during deobfuscation (returned: ' + IntToHex(NativeUInt(P4), SizeOf(Pointer)*2) + ').');
    end;
  except
    on E: Exception do
    begin
      WriteLn('SAFE: Memory access violation caught (expected behavior when dereferencing obfuscated pointer) : ' + E.Message);
      Halt(0);
    end;
  end;
  
  WriteLn('Test completed.');
end.