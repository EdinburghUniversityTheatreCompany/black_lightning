# Override the default select method to use select2. 
# See https://github.com/heartcombo/simple_form#custom-inputs

class CollectionSelectInput < SimpleForm::Inputs::CollectionSelectInput
  def input(wrapper_options = nil)
    label_method, value_method =                                                                  detect_collection_methods

    merged_input_options = merge_wrapper_options(input_html_options, wrapper_options)

    merged_input_options = merged_input_options.merge({ class: 'simple-select2' })

    # If it allows custom input, set the 'select2-with-tags' attribute to true so it will be recognised by the script that instantiates the select2 fields.
    merged_input_options['select2-with-tags'] = 'true' if input_options[:allow_custom_input]

    @builder.collection_select(
      attribute_name, collection, value_method, label_method,
      input_options, merged_input_options
    )
  end
end
