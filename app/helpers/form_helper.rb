module FormHelper
  def horizontal_form_options
    if params[:controller].to_s.start_with?("admin/")
      {
        wrapper: :tailwind_horizontal_form,
        wrapper_mappings: {
          boolean:       :tailwind_horizontal_boolean,
          fake_checkbox: :tailwind_horizontal_boolean,
          check_boxes:   :tailwind_horizontal_collection,
          date:          :tailwind_horizontal_multi_select,
          datetime:      :tailwind_horizontal_multi_select,
          file:          :tailwind_horizontal_file,
          radio_buttons: :tailwind_horizontal_collection,
          range:         :tailwind_horizontal_range,
          time:          :tailwind_horizontal_multi_select
        }
      }
    else
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
  end

  def simple_horizontal_form_for(object, *args, &block)
    options = args.extract_options!
    new_options = horizontal_form_options
    simple_form_for(object, *(args << options.merge(new_options)), &block)
  end
end
