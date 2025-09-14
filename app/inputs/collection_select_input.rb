# Override the default select method to use select2.
# See https://github.com/heartcombo/simple_form#custom-inputs

class CollectionSelectInput < SimpleForm::Inputs::CollectionSelectInput
  def input(wrapper_options = nil)
    label_method, value_method =                                                                  detect_collection_methods

    merged_input_options = merge_wrapper_options(input_html_options, wrapper_options)

    # Add the simple-select2 class to the input so it is found by the select2 script.
    merged_input_options = merged_input_options.merge({ class: "simple-select2" })

    # If it allows custom input, set the 'select2-with-tags' attribute to true so it will be recognised by the script that instantiates the select2 fields.
    merged_input_options["select2-with-tags"] = "true" if input_options[:allow_custom_input]

    # I have no idea why this is necessary, but if you just replace "collection2" by "collection" everywhere it will break.
    # This is only because of the 'adding the current_value' part.
    collection2 = collection

    # If the field is a custom input, try to get the current value (for example, for positions),
    # and add it to the collection if it is not in there already. Only for string selects.
    if input_options[:allow_custom_input] && collection.first.present? && collection.first.is_a?(String)
      current_value = @builder.object.try(attribute_name.to_sym).presence

      # Only add the current value to the collection if it's present and not already in the collection
      if current_value.present? && !collection.include?(current_value)
        collection2 = [ current_value ] + collection2
      end
    end

    @builder.collection_select(
      attribute_name, collection2, value_method, label_method,
      input_options, merged_input_options
    )
  end
end
