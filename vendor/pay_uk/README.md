# Pay.UK modulus-check rules

`Reimbursements::ModulusCheck.default_checker` loads two data files from this
directory to run the UK bank account modulus check (sort code + account number
consistency):

- `valacdos.txt` — the weighting/algorithm table (sort-code ranges → method,
  14 weights, exception code).
- `scsubtab.txt` — the sort-code substitution table.

## These files are NOT committed

Pay.UK distributes them under a **click-through licence**, so they are
gitignored (`vendor/pay_uk/*.txt`). Each machine/deploy must fetch its own copy.

## How to obtain them

Download the current "Modulus checking" data files from Pay.UK:

<https://www.vocalink.com/tools/modulus-checking/> (the industry sort code
database / modulus weight table). Save them here as `valacdos.txt` and
`scsubtab.txt`.

## Graceful degradation

If the files are absent the checker is built from an empty rule set, so every
check returns `OUTSIDE_SPEC` (a soft "couldn't verify") rather than raising —
the app never crashes for want of these files.
