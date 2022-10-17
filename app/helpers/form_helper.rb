module FormHelper
  def simple_horizontal_form_for(object, *args, &block)
    options = args.extract_options!
    new_options = {
      wrapper: :horizontal_form,
      wrapper_mappings: {
        boolean:       :horizontal_boolean,
        check_boxes:   :horizontal_collection,
        date:          :horizontal_multi_select,
        datetime:      :horizontal_multi_select,
        file:          :horizontal_file,
        radio_buttons: :horizontal_collection,
        range:         :horizontal_range,
        time:          :horizontal_multi_select
      }
    }
    simple_form_for(object, *(args << options.merge(new_options)), &block)
  end
end
