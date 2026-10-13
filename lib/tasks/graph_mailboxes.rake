namespace :graph do
  desc "Print the mailboxes the app touches over Graph, as env assignments for docs/graph-mailbox-rbac.ps1"
  task mailboxes: :environment do
    # Read from the database, so the Entra app isn't scoped to the wrong mailboxes: a cost centre's
    # send address is a separate editable column from its receive address, and live they differ
    # (finance@ vs reimbursements@). Scoping only the receive mailbox passed every check, then 403'd
    # on sendMail.
    centres = Reimbursements::CostCentre.all.to_a

    # Each needs Application Mail Full Access, not Mail.ReadWrite: the receive mailbox replies
    # (Mail.Send), and the send mailbox creates, reads back and deletes drafts (Mail.ReadWrite).
    send_receive = centres.flat_map { |c| [ c.receive_mailbox, c.send_mailbox ] }
    climate = Climate::Settings.mailbox

    puts "# Cost centres:"
    centres.each { |c| puts "#   #{c.key}: receive=#{c.receive_mailbox} send=#{c.send_mailbox}" }
    puts
    puts %($env:BL_SEND_RECEIVE_MAILBOXES = "#{send_receive.compact.uniq.sort.join(',')}")
    puts %($env:BL_READ_ONLY_MAILBOXES    = "#{climate}") if climate.present?
    puts "# No climate mailbox configured (CLIMATE_MAILBOX unset)." if climate.blank?
  end
end
