# The "Possible Matches" section of an import preview: rows whose name resembles one or more
# existing users, each with the candidates and their years active, and a radio per way to resolve
# it: one per candidate (best match first, preselected), then create new, then skip.
class Admin::ImportPossibleMatchesComponent < ViewComponent::Base
  # years_active: the import's years_active_cache, by user id.
  # choice: the decision a candidate's radio posts, as "<choice>_<user id>".
  # choice_label_prefix: goes before each candidate's name on their radio.
  # show_ids: the ids of the row and of each candidate.
  # show_blank_email: keeps the (empty) email line of a row without one, as the membership
  #   preview always has.
  # show_position: the position the row brings, in a column before the decision.
  def initialize(items:, years_active:, choice: "link", choice_label_prefix: nil,
                 create_label: "Different person (create new)", show_ids: true,
                 show_blank_email: false, show_position: false)
    @items = items
    @years_active = years_active
    @choice = choice
    @choice_label_prefix = choice_label_prefix
    @create_label = create_label
    @show_ids = show_ids
    @show_blank_email = show_blank_email
    @show_position = show_position
  end

  private

  def headers
    [ "Import Data", "Possible Match(es)", ("Position" if @show_position), [ "Decision", "280px" ] ].compact
  end

  def years_label(user)
    helpers.format_years_active_label(@years_active[user.id])
  end

  def choice_label(user)
    "#{@choice_label_prefix}#{user.name_or_email} (#{years_label(user)})"
  end
end
