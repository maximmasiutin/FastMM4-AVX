{Compiler version defines, shared by every unit of FastMM4-AVX that needs to
 know which compiler it is being built by.

 The compiler's own verNNN symbols are mapped to names once, here, and the code
 elsewhere tests only the names. A unit that instead compares CompilerVersion
 in place breaks on FreePascal, which defines no such symbol and rejects the
 expression rather than reading it as zero, and it breaks on Delphi 4 and 5,
 whose compilers have no conditional-expression directive at all.

 A name that means "this release and later" is defined first and undefined for
 each older release, so a compiler newer than the newest one listed inherits it
 rather than falling into the old path.}

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
  {NativeInt and NativeUInt arrived with Delphi 2009.}
  {$IFDEF ver120}{$define Delphi2009AndDown}{$ENDIF}
  {$IFDEF ver130}{$define Delphi2009AndDown}{$ENDIF}
  {$IFDEF ver140}{$define Delphi2009AndDown}{$ENDIF}
  {$IFDEF ver150}{$define Delphi2009AndDown}{$ENDIF}
  {$IFDEF ver160}{$define Delphi2009AndDown}{$ENDIF}
  {$IFDEF ver170}{$define Delphi2009AndDown}{$ENDIF}
  {$IFDEF ver180}{$define Delphi2009AndDown}{$ENDIF}
  {$IFDEF ver185}{$define Delphi2009AndDown}{$ENDIF}
  {$IFDEF ver190}{$define Delphi2009AndDown}{$ENDIF}
  {$IFDEF ver200}{$define Delphi2009AndDown}{$ENDIF}
  {$define 32BIT}
  {$IFNDEF Delphi4or5}
    {$if SizeOf(Pointer) = 8}
      {$define 64BIT}
      {$undef 32BIT}
    {$ifend}
    {NativeInt arrived, and PByte stopped being PAnsiChar, in Delphi 2009.}
    {$define Delphi2009AndUp}
    {$IFDEF ver140}{$undef Delphi2009AndUp}{$ENDIF}
    {$IFDEF ver150}{$undef Delphi2009AndUp}{$ENDIF}
    {$IFDEF ver160}{$undef Delphi2009AndUp}{$ENDIF}
    {$IFDEF ver170}{$undef Delphi2009AndUp}{$ENDIF}
    {$IFDEF ver180}{$undef Delphi2009AndUp}{$ENDIF}
    {$IFDEF ver185}{$undef Delphi2009AndUp}{$ENDIF}
    {$IFDEF ver190}{$undef Delphi2009AndUp}{$ENDIF}
    {NativeUInt arrived in Delphi 2010.}
    {$define Delphi2010AndUp}
    {$IFDEF ver140}{$undef Delphi2010AndUp}{$ENDIF}
    {$IFDEF ver150}{$undef Delphi2010AndUp}{$ENDIF}
    {$IFDEF ver160}{$undef Delphi2010AndUp}{$ENDIF}
    {$IFDEF ver170}{$undef Delphi2010AndUp}{$ENDIF}
    {$IFDEF ver180}{$undef Delphi2010AndUp}{$ENDIF}
    {$IFDEF ver185}{$undef Delphi2010AndUp}{$ENDIF}
    {$IFDEF ver190}{$undef Delphi2010AndUp}{$ENDIF}
    {$IFDEF ver200}{$undef Delphi2010AndUp}{$ENDIF}
    {PNativeUInt arrived in Delphi XE.}
    {$define DelphiXEAndUp}
    {$IFDEF ver140}{$undef DelphiXEAndUp}{$ENDIF}
    {$IFDEF ver150}{$undef DelphiXEAndUp}{$ENDIF}
    {$IFDEF ver160}{$undef DelphiXEAndUp}{$ENDIF}
    {$IFDEF ver170}{$undef DelphiXEAndUp}{$ENDIF}
    {$IFDEF ver180}{$undef DelphiXEAndUp}{$ENDIF}
    {$IFDEF ver185}{$undef DelphiXEAndUp}{$ENDIF}
    {$IFDEF ver190}{$undef DelphiXEAndUp}{$ENDIF}
    {$IFDEF ver200}{$undef DelphiXEAndUp}{$ENDIF}
    {$IFDEF ver210}{$undef DelphiXEAndUp}{$ENDIF}
    {XE2 is where the inline assembler gained the align directive, where
     IntPtr and UIntPtr arrived, and where a class method of a record needs
     the static directive.}
    {$define XE2AndUp}
    {$IFDEF ver140}{$undef XE2AndUp}{$ENDIF}
    {$IFDEF ver150}{$undef XE2AndUp}{$ENDIF}
    {$IFDEF ver160}{$undef XE2AndUp}{$ENDIF}
    {$IFDEF ver170}{$undef XE2AndUp}{$ENDIF}
    {$IFDEF ver180}{$undef XE2AndUp}{$ENDIF}
    {$IFDEF ver185}{$undef XE2AndUp}{$ENDIF}
    {$IFDEF ver190}{$undef XE2AndUp}{$ENDIF}
    {$IFDEF ver200}{$undef XE2AndUp}{$ENDIF}
    {$IFDEF ver210}{$undef XE2AndUp}{$ENDIF}
    {$IFDEF ver220}{$undef XE2AndUp}{$ENDIF}
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
