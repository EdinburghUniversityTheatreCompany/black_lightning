# Override the default select method to use select2. 
# See https://github.com/heartcombo/simple_form#custom-inputs

class CollectionSelectInput < SimpleForm::Inputs::CollectionSelectInput
  def input(wrapper_options = nil)
    label_method, value_method = detect_collection_methods

    merged_input_options = merge_wrapper_options(input_html_options, wrapper_options)

    if input_options.key?(:allow_custom_input) && input_options[:allow_custom_input]
      merged_input_options = merged_input_options.merge({ class: 'simple-select2-with-tags' })
    else
      merged_input_options = merged_input_options.merge({ class: 'simple-select2' })
    end

    @builder.collection_select(
      attribute_name, collection, value_method, label_method,
      input_options, merged_input_options
    )
  end
end
