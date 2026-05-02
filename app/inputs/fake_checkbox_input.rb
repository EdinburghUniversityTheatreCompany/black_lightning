class FakeCheckboxInput < SimpleForm::Inputs::StringInput
  # Creates a checkbox that does NOT read its value from the object.
  # Use label: and hint: normally — they render via the wrapper.
  # See https://github.com/heartcombo/simple_form/wiki/Create-a-fake-input-that-does-NOT-read-attributess
  def input(wrapper_options = nil)
    input_html_options.delete(:class)
    merged_input_options = merge_wrapper_options(input_html_options, wrapper_options)
    tag_name = "#{@builder.object_name}[#{attribute_name}]"
    template.check_box_tag(tag_name, options["value"] || 1, options["checked"], merged_input_options)
  end
end
