class AddOrganisationToReviews < ActiveRecord::Migration
  def change
    add_column :reviews, :organisation, :string
  end
end
