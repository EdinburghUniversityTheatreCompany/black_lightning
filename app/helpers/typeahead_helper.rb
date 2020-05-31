module TypeaheadHelper
  def position_typeahead
    return [
      'Director', 'Assistant Director', 'Co-Director', 'Producer',
      'Assistant Producer', 'Co-Producer', 'Tech Manager', 'Co-Tech Manager',
      'Tech Assistant', 'Lighting Designer', 'Sound Designer', 'Projections Designer',
      'Projections Manager', 'Stage Manager', 'Assistant Stage Manager', 'Co-Stage Manager',
      'Set Manager', 'Set Assistant', 'Set Designer', 'Production Manager', 'Costume Manager',
      'Costume Assistant', 'Co-Costume Manager', 'Writer', 'Actor', 'Musician',
      'Performer', 'Creative', 'Production Manager', 'Assistant to Mr B. Hussey'
    ]
  end

  # Works as a pass-by-reference
  # TODO: Having a filled id field, but an empty user name field should also be reason for error.
  def sanitize_user_typeahead_attributes!(attributes, add_error_to_flash)
    return [] if attributes.nil?

    invalid_user_names = []
    invalid_attribute_ids = []

    attributes.each do |id, value|
      # If a field has an user name entered, but doesn't have an ID, that means there was a typo entering the name.
      if value[:user_name_field].present? && value[:user_id].empty?
        invalid_user_names << value[:user_name_field]
        invalid_attribute_ids << id
      end
    end

    # Remove the invalid updates from the hash so they will not be updated and the previous name will be restored.
    attributes.extract!(*invalid_attribute_ids)

    # Staffing jobs do not have the attribute user_name_field that we used here, so we have to remove it first.
    attributes.each { |_id, value| value.extract!(:user_name_field) }

    if add_error_to_flash && invalid_user_names.any?
      error_message = "There was a typo entering the name of the #{'user'.pluralize(invalid_user_names.size)} #{invalid_user_names.to_sentence}. Their previous name has been restored."

      append_to_flash(:error, error_message)
    end

    return invalid_user_names
  end
end