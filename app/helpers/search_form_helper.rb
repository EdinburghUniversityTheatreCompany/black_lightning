module SearchFormHelper
  # Essentially, hide all fields apart from the first 3 inside a collapsed field, except when there are 4.
  # I did that because rendering 5 fields takes the same space as rendering 3 fields + a collapsed collapse.
  NUMBER_OUTSIDE_COLLAPSE = 3
  NUMBER_BEFORE_COLLAPSE = 5

  def split_search_form_input_fields(input_fields, columns)
    # Do not include fields that have no params
    input_fields = input_fields.reject { |key, params| params.nil? }

    # Filter out the buttons.
    button_params, input_fields = input_fields.partition { |key, params| params[:type] == :submit_button }

    # Are there more fields than the threshold before collapsing.
    should_collapse = input_fields.length > NUMBER_BEFORE_COLLAPSE * columns

    if should_collapse
      input_fields_outside_collapse = Hash[input_fields.to_a[0, NUMBER_OUTSIDE_COLLAPSE * columns]]
      input_fields_in_collapse = Hash[input_fields.to_a[NUMBER_OUTSIDE_COLLAPSE * columns, input_fields.length]]
    else
      input_fields_outside_collapse = input_fields
      input_fields_in_collapse = []
    end

    return input_fields_in_collapse, input_fields_outside_collapse, button_params
  end

  def render_search_form_fields(f, input_fields, columns)
    output = ""

    raise(ArgumentError, "The amount of column should be a divisor of 12") unless [ 1, 2, 3, 4, 6, 12 ].include?(columns)

    output += "<div class=\"row row-cols-#{columns}\">"

    input_fields.each_with_index do |(key, params), i|
      output += render_search_form_field(f, key, params)
    end
    output += "</div>"

    output.html_safe
  end

  def render_search_form_field(f, key, params)
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
            return render("shared/boolean_search_form_field", f: f, name: key, label: label, params: params)
        elsif params[:type] == :select
            # By default, you need to select an item, while usually, you want to have the filtering using a select be optional.
            params[:include_blank] = true if params[:include_blank].nil?

        # No `next`. Just go on to render a normal select input, but with the above parameter set.
        elsif params[:type] == :date_range
            # Render a date range with options specified.
            return render("shared/date_range_search_form_field", { f: f }.merge(params[:options]))
        elsif params[:type] == :submit_button
          raise(ArgumentError, "A submit button has not been filtered out in the search fields.")
        end
    end

    # If there is no type key, text is implied, and we just render an input.

    # Set email fields to render as text fields to prevent email and url validations, unless there is already an as in the params
    if !params.key?(:as) && (key.to_s.include?("email") || key.to_s.include?("url"))
        params[:as] = "string"
    end

    # By default, the fields are required, so override that and set them to not required unless explicitly stated.
    # These are search fields so making them required is odd.
    params[:required] = false if params[:required].nil?

    # Remove the type and slug from the parameters since they are not relevant for the input.
    params = params.except!([ :type, :slug ])

    # Render the input itself, unless it was caught by the switch earlier and is already rendered.
    # Wrap the input in a col so we cal columnise the form.
    "  <div class=\"col\">\n  #{f.input(key, params)}\n  </div>\n"
  end
end
