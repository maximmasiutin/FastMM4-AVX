{One guard sits inside a conditional that nothing defines, so the compiler
 never sees it although its text is still in the file. A verifier that reads
 directives as commentary accepts this file, which is the regression this
 fixture exists to catch.}
procedure FixtureProcedure;
begin
  {fixture-start}
  ValidateBounds;
{$IFDEF NeverDefined}
  ValidateAlignment;
{$ENDIF}
  Exit;
  GuardedUse;
  {fixture-end}
end;
