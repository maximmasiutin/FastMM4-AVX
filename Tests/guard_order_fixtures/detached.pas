{The guard condition logs and falls through, and the Exit that follows belongs
 to a later, unrelated condition. A verifier that only requires a terminator
 somewhere between the guard and the guarded use accepts this file, which is
 the regression this fixture exists to catch.}
procedure FixtureProcedure;
begin
  {fixture-start}
  ValidateBounds;
  ValidateAlignment;
  if SomethingUnrelated then
    Exit;
  GuardedUse;
  {fixture-end}
end;
