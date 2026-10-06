class SearchFormComponentPreview < ViewComponent::Preview
  FIELDS = {
    first_name_cont: { label: "First name" },
    last_name_cont: { label: "Last name" },
    email_cont: {},
    phone_cont: { label: "Phone" },
    address_cont: { label: "Address" },
    city_cont: { label: "City" },
    postal_code_cont: { label: "Postal code" }
  }.freeze

  def default = form(3, 1)
  def two_columns = form(4, 2)
  def with_collapse = form(7, 1)

  private

  def form(count, columns)
    render SearchFormComponent.new(q: User.ransack, input_fields: FIELDS.first(count).to_h, columns:)
  end
end
