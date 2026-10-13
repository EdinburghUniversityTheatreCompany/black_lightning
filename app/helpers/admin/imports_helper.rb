# frozen_string_literal: true

# Markup shared by the bulk import previews.
module Admin::ImportsHelper
  # One radio for a row's decision. It posts as actions[index], which the confirm action reads.
  def import_choice(index, value, label, checked: false)
    id = "action_#{index}_#{value}"

    tag.div(class: "form-check") do
      radio_button_tag("actions[#{index}]", value, checked, class: "form-check-input", id: id) +
        label_tag(id, label, class: "form-check-label")
    end
  end

  # What matched a row to its user: the id it carried, or its email.
  def import_match_label(item)
    case item[:match_type]
    when :user_id then "User ID #{item[:row][:user_id]}"
    when nil then item[:row][:email]
    else item[:row][item[:match_type]]
    end
  end
end
