module FormHelper
  def horizontal_form_options
    {
      wrapper: :tailwind_horizontal_form,
      wrapper_mappings: {
        boolean:       :tailwind_horizontal_boolean,
        check_boxes:   :tailwind_horizontal_collection,
        date:          :tailwind_horizontal_multi_select,
        datetime:      :tailwind_horizontal_multi_select,
        file:          :tailwind_horizontal_file,
        radio_buttons: :tailwind_horizontal_collection,
        range:         :tailwind_horizontal_range,
        time:          :tailwind_horizontal_multi_select
      }
    }
  end

  def simple_horizontal_form_for(object, *args, &block)
    options = args.extract_options!
    new_options = horizontal_form_options
    simple_form_for(object, *(args << options.merge(new_options)), &block)
  end
end
