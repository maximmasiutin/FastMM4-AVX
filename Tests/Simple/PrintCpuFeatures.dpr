program PrintCpuFeatures;

uses
  FastMM4 in '..\..\FastMM4.pas',
  FastMM4Messages in '..\..\FastMM4Messages.pas';

type
  TCpuFeature = packed record
    b: Byte;
    n: string;
  end;


const
  CCpuFeatures: array[0..8] of TCpuFeature = (
    (b: 0; n: 'MMX'),
    (b: 1; n: 'AVX1'),
    (b: 2; n: 'AVX2'),
    (b: 3; n: 'AVX512'),
    (b: 4; n: 'ERMS'),
    (b: 5; n: 'pause+SwitchToThread'),
    (b: 6; n: 'SSE'),
    (b: 7; n: 'FSRM'),
    (b: 8; n: 'WaitPKG')
  );

var
  CpuFeatures: Word;
  s: string;
  i: Integer;
begin
  CpuFeatures := GetFastMMCpuFeatures;
  s := '';

  for i := Low(CCpuFeatures) to High(CCpuFeatures) do
  begin
    with CCpuFeatures[i] do
    begin
      if ((Word(1) shl b) and CpuFeatures) <> 0 then
      begin
        if s <> '' then s := s + ', ';
        s := s + n;
      end;
    end;
  end;

  WriteLn('Supported FastMM4-AVX CPU features are: '+s+'.');
end.
