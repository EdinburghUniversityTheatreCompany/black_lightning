# A searchable list of users, with an optional second column: a Remove button
# per user (role membership) or their attendance count (maintenance sessions).
class UsersTableComponent < ViewComponent::Base
  SEARCH_FIELDS = { full_name_cont: { slug: "defaults.name" } }.freeze

  def initialize(users:, url:, q: nil, show_remove_buttons: false,
                 remove_url_helper: nil, credit_counts: nil)
    @users = users
    @url = url
    @q = q
    @show_remove_buttons = show_remove_buttons
    @remove_url_helper = remove_url_helper
    @credit_counts = credit_counts
  end

  private

  def headers
    return [ :name, "Actions" ] if @show_remove_buttons
    return [ :name, "Credits" ] if @credit_counts

    [ :name ]
  end

  # The user is the first cell in every shape, because IndexTableComponent reads
  # it to build the link and check the edit permission.
  def field_sets
    @users.map { |user| { fields: [ user, *extra_cells_for(user) ] } }
  end

  def extra_cells_for(user)
    return [ remove_button_for(user) ] if @show_remove_buttons
    return [ @credit_counts[user.id] || 1 ] if @credit_counts

    []
  end

  def remove_button_for(user)
    helpers.button_to(
      "Remove", @remove_url_helper.call(user.id), method: :delete,
      class: ButtonComponent.classes_for(variant: :danger, size: :sm),
      form: { style: "display:contents",
              data: { controller: "confirm", action: "submit->confirm#confirm",
                      confirm_message_value: "Remove #{user.name} from this role?" } }
    )
  end
end
