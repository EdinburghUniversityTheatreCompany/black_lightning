class AddDraftWebLinkToReimbursementsBatches < ActiveRecord::Migration[8.1]
  # The EUSA draft's Outlook URL. Sending that draft is the one manual step
  # left in paying people, and until now the link reached only the operator's
  # own email (BuildBatchJob) — History and Detail both promised it and neither
  # could render one, because nothing stored it.
  #
  # Nullable with no backfill, deliberately: the link for a batch built before
  # this is not recoverable (Graph's webLink is handed back once, at creation,
  # and is not derivable from the message id), so those batches keep saying the
  # draft was created and say plainly that its link was not recorded.
  #
  # TEXT, not a string: an Outlook webLink is a long URL carrying a
  # base64url-encoded item id and routinely runs past 255 characters.
  def change
    add_column :reimbursements_batches, :draft_web_link, :text
  end
end
