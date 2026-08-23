{One guard is present in the file but commented out, so the compiled code
 runs without it. A verifier matching raw text accepts this file, which is the
 regression this fixture exists to catch.}
procedure FixtureProcedure;
begin
  {fixture-start}
  {ValidateBounds;}
  ValidateAlignment;
  GuardedUse;
  {fixture-end}
end;
