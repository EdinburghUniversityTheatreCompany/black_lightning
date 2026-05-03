class Admin::SearchFormComponent < ViewComponent::Base
  def initialize(q:, input_fields:, columns:, url: nil)
    @q = q
    @input_fields = input_fields
    @columns = columns
    @url = url
  end

  private

  def split_fields
    @split_fields ||= helpers.split_search_form_input_fields(@input_fields, @columns)
  end

  def fields_in_collapse   = split_fields[0]
  def fields_outside_collapse = split_fields[1]
  def button_params        = split_fields[2]

  def effective_columns
    return @columns if fields_in_collapse.any?
    [ fields_outside_collapse.count, @columns ].min
  end

  def form_url
    @url || "/#{helpers.controller_path}"
  end
end
