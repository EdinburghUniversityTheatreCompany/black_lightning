# Pay.UK modulus-check rules

`Reimbursements::ModulusCheck.default_checker` loads two data files from this
directory to run the UK bank account modulus check (sort code + account number
consistency):

- `valacdos.txt`: the weighting/algorithm table (sort-code ranges → method,
  14 weights, exception code).
- `scsubtab.txt`: the sort-code substitution table.

## These files ARE committed

They're committed to the repo so Kamal ships them inside the Docker image (a
gitignored file never reaches the built image, and the checker would then read
`OUTSIDE_SPEC` for every account in production). Pay.UK distributes them under a
**click-through licence**, so keep that in mind if this repo is made public.

## How to refresh them

Download the current "Modulus checking" data files from Pay.UK and overwrite the
copies here:

<https://www.vocalink.com/tools/modulus-checking/> (the industry sort code
database / modulus weight table). Save them as `valacdos.txt` and `scsubtab.txt`.

## Graceful degradation

If the files are absent the checker is built from an empty rule set, so every
check returns `OUTSIDE_SPEC` (a soft "couldn't verify") rather than raising.
The app never crashes for want of these files.
