module FormHelper
  def horizontal_form_options
    {
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
  end

  # Search forms are horizontal, but have a special boolean search field that takes up less space.
  def search_form_options
    options = horizontal_form_options
    options[:wrapper_mappings][:boolean] = :horizontal_boolean_search
    options
  end

  def simple_horizontal_form_for(object, *args, &block)
    options = args.extract_options!
    new_options = horizontal_form_options
    simple_form_for(object, *(args << options.merge(new_options)), &block)
  end
end
