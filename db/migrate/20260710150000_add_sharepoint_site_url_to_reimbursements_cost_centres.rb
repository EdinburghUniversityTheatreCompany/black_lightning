class AddSharepointSiteUrlToReimbursementsCostCentres < ActiveRecord::Migration[8.1]
  # The cost centre's SharePoint site (e.g. https://tenant.sharepoint.com/sites/Finance).
  # Under the least-privilege Sites.Selected model the app can't search/enumerate
  # sites, so the folder picker browses this configured site directly, and its
  # per-site write grant is shown (filled in) on the Settings page.
  def change
    add_column :reimbursements_cost_centres, :sharepoint_site_url, :string
  end
end
