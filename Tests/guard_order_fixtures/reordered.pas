{Both guards run before the guarded use, but in the wrong order relative to
 each other: the alignment test would consume flags the bounds check has not
 set yet. A verifier that accepts guard components in any order passes this
 file, which is the regression this fixture exists to catch.}
procedure FixtureProcedure;
begin
  {fixture-start}
  ValidateAlignment;
  ValidateBounds;
  Exit;
  GuardedUse;
  {fixture-end}
end;
