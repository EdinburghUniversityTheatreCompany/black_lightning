# Reimbursements cost centres. Fringe (F40) is live; termtime (BED) becomes a
# second row when the portal takes over termtime payments.
find_or_seed(
  Reimbursements::CostCentre,
  { key: "fringe" },
  {
    name: "Bedlam Fringe 2026",
    eusa_code: "F40",
    receive_mailbox: "reimbursements@bedlamfringe.co.uk",
    send_mailbox: "reimbursements@bedlamfringe.co.uk"
  }
)
seed_puts("Reimbursements cost centres seeded")
