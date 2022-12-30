module SearchFormHelper
  # Essentially, hide all fields apart from the first 3 inside a collapsed field, except when there are 4.
  # I did that because rendering 5 fields takes the same space as rendering 3 fields + a collapsed collapse.
  NUMBER_OUTSIDE_COLLAPSE = 3
  NUMBER_BEFORE_COLLAPSE = 5

  def split_search_form_input_fields(input_fields)
    # Do not include fields that have no params
    input_fields = input_fields.reject { |key, params| params.nil? }

    # Filter out the buttons.
    button_params, input_fields = input_fields.partition { |key, params| params[:type] == :submit_button }

    # Are there more fields than the threshold before collapsing.
    should_collapse = input_fields.length > NUMBER_BEFORE_COLLAPSE

    if should_collapse
      input_fields_outside_collapse = Hash[input_fields.to_a[0, NUMBER_OUTSIDE_COLLAPSE]]#input_fields.to(NUMBER_OUTSIDE_COLLAPSE - 1)
      input_fields_in_collapse = Hash[input_fields.to_a[NUMBER_OUTSIDE_COLLAPSE, input_fields.length]]
    else
      input_fields_outside_collapse = input_fields
      input_fields_in_collapse = nil
    end

    return input_fields_in_collapse, input_fields_outside_collapse, button_params
  end

  def render_search_form_fields(f, input_fields)
    output = ''

    input_fields.each do |key, params|
      if params.key?(:label)
          label = params[:label]
      elsif params.key?(:slug)
          label = t("simple_form.labels.#{params[:slug]}")
      else
          label = key.to_s.humanize
      end

      # Reassign label back to params in case it gets passed through to an input.
      params[:label] = label

      # Render specific input fields for some types.
      if params.key?(:type) && params[:type] != :text
          if params[:type] == :boolean
              # If it is a boolean, just render the boolean field and continue the loop.
              output += render('shared/boolean_search_form_field', f: f, name: key, label: label)
              next
          elsif params[:type] == :select
              # By default, you need to select an item, while usually, you want to have the filtering using a select be optional.
              params[:include_blank] = true if params[:include_blank].nil?

              # No `next`. Just go on to render a normal select input, but with the above parameter set.
          elsif params[:type] == :date_range
              # Render a date range with options specified.
              output += render('shared/date_range_search_form_field', { f: f }.merge(params[:options]))
              next
          elsif params[:type] == :submit_button
            raise(ArgumentError, 'A submit button has not been filtered out in the search fields.')
          end
      end

      # If there is no type key, text is implied, and we just render an input.

      # Set email fields to render as text fields to prevent email and url validations, unless there is already an as in the params
      if !params.key?(:as) && (key.to_s.include?('email') || key.to_s.include?('url'))
          params[:as] = 'string'
      end

      # By default, the fields are required, so override that and set them to not required unless explicitly stated.
      # These are search fields so making them required is odd.
      params[:required] = false if params[:required].nil?

      # Remove the type and slug from the parameters since they are not relevant for the input.
      params = params.except!([:type, :slug])

      # Render the input itself, unless it was caught by the switch earlier and is already rendered.
      output += f.input(key, params)
    end

    return output.html_safe
  end
end
