# Overrides simple_form's grouped select so Tom Select takes it over, as
# CollectionSelectInput does for a flat one: the class is ONLY simple-select2,
# because Tom Select copies the select's classes onto its own boxed wrapper.
class GroupedCollectionSelectInput < SimpleForm::Inputs::GroupedCollectionSelectInput
  def input(wrapper_options = nil)
    label_method, value_method = detect_collection_methods
    merged_input_options = merge_wrapper_options(input_html_options, wrapper_options).merge(class: "simple-select2")

    @builder.grouped_collection_select(attribute_name, grouped_collection,
                                       group_method, group_label_method, value_method, label_method,
                                       input_options, merged_input_options)
  end
end
