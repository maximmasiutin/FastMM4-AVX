{Compiler version defines, shared by every unit that needs to know which
 compiler is building it. This is the block FastMM4.pas has always carried,
 moved verbatim so other units can include it; only the names it defines are
 tested elsewhere. The CompilerVersion comparisons below are safe where they
 sit, inside the branches that exclude FreePascal and Delphi 4 and 5, because
 a skipped conditional block is never evaluated.}
{$IFNDEF fpc}
  {$IFNDEF BCB}
    {$IFDEF ver120}
      {$define Delphi4or5}
    {$ENDIF}
    {$IFDEF ver130}
      {$define Delphi4or5}
    {$ENDIF}
    {$IFDEF ver140}
      {$define Delphi6}
    {$ENDIF}
    {$IFDEF ver150}
      {$define Delphi7}
    {$ENDIF}
    {$IFDEF ver170}
      {$define Delphi2005}
    {$ENDIF}
  {$ELSE}
    {for BCB4, use the Delphi 5 codepath}
    {$IFDEF ver120}
      {$define Delphi4or5}
      {$define BCB4}
    {$ENDIF}
    {for BCB5, use the Delphi 5 codepath}
    {$IFDEF ver130}
      {$define Delphi4or5}
    {$ENDIF}
  {$ENDIF}
  {$IFDEF ver180}
    {$define BDS2006}
  {$ENDIF}
  {$define 32BIT}
  {$IFNDEF Delphi4or5}
    {$if SizeOf(Pointer) = 8}
      {$define 64BIT}
      {$undef 32BIT}
    {$ifend}
    {$if CompilerVersion >= 23}
      {$define XE2AndUp}
    {$ifend}
    {$define BCB6OrDelphi6AndUp}
    {$IFNDEF BCB}
      {$define Delphi6AndUp}
    {$ENDIF}
    {$IFNDEF Delphi6}
      {$define BCB6OrDelphi7AndUp}
      {$IFNDEF BCB}
        {$define Delphi7AndUp}
      {$ENDIF}
      {$IFNDEF BCB}
        {$IFNDEF Delphi7}
          {$IFNDEF Delphi2005}
            {$define BDS2006AndUp}
          {$ENDIF}
        {$ENDIF}
      {$ENDIF}
    {$ENDIF}
  {$ENDIF}
{$ELSE}
  {Defines for FreePascal}
  {$asmmode intel}
  {$IFDEF CPUX64}
    {$asmmode intel}
    {$define 64BIT}
    {$define fpc64BIT}
    {$undef 32BIT}
  {$ELSE}
    {$define 32BIT}
    {$undef 64BIT}
  {$ENDIF}
{$ENDIF}
