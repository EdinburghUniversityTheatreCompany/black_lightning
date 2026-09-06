##
# Stamps each team member's +display_order+ from the position of its row in the
# submitted form, so the stored order is the order the user saw on screen.
#
# Browsers serialise a form in document order and nested attributes are
# assigned in that order, so a row's place in the params already says where it
# was — dragged there, added with "Add", or where the form first drew it. That
# is why the row carries no hidden order field: there is nothing for the
# browser to renumber and nothing for the server to disagree with, and it holds
# with JavaScript off. Rows on their way out are skipped so the sequence has no
# gaps, and rows the association's +reject_if+ will drop are left alone so it
# still drops them.
#
# The rows have to be numbered before assignment, not from the association
# afterwards: Rails keeps existing records in their loaded order and appends new
# ones, so the target no longer says where each row was.
module TeamMemberOrdering
  extend ActiveSupport::Concern

  def team_members_attributes=(attributes)
    super(team_member_rows_in_display_order(attributes))
  end

  private

  # +attributes+ is the index-keyed hash the form posts (a hash carrying an +id+
  # of its own is one row, as Rails reads it), or an array. Both Rails helpers
  # read the association's own options, so a change to +reject_if+ or
  # +allow_destroy+ on the includer is honoured here without a second copy.
  def team_member_rows_in_display_order(attributes)
    rows = case attributes
    when Array then attributes
    when Hash then attributes.key?("id") || attributes.key?(:id) ? [ attributes ] : attributes.values
    else return attributes
    end

    position = 0
    rows.map do |row|
      row = row.with_indifferent_access
      next row if will_be_destroyed?(:team_members, row) || call_reject_if(:team_members, row)

      row[:display_order] = position
      position += 1
      row
    end
  end
end
