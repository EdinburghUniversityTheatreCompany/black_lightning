##
# Stamps each team member's display_order from its row's position in the
# submitted form. Browsers post rows in document order, so the row carries no
# hidden order field and this holds with JavaScript off. Rows reject_if will drop
# are left unstamped, or the stamp would make them non-blank.
#
# Numbered before assignment: afterwards Rails keeps loaded records in their old
# order and appends new ones, so the association no longer says where each was.
module TeamMemberOrdering
  extend ActiveSupport::Concern

  def team_members_attributes=(attributes)
    super(team_member_rows_in_display_order(attributes))
  end

  private

  # A hash with an id of its own is one row, as Rails reads it. Parameters is not
  # a Hash, so it is unwrapped: update deep-converts it, but a caller assigning
  # this attribute directly does not, and its rows would save with no order.
  #
  # will_be_destroyed? and call_reject_if are private ActiveRecord internals, used
  # so the association's own reject_if and allow_destroy are honoured. The
  # ordering tests pin them.
  def team_member_rows_in_display_order(attributes)
    attributes = attributes.to_h if attributes.respond_to?(:permitted?)

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
