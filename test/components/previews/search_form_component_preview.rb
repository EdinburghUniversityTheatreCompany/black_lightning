class SearchFormComponentPreview < ViewComponent::Preview
  def default
    render SearchFormComponent.new(
      q: User.ransack,
      input_fields: {
        first_name_cont: { label: "First name" },
        last_name_cont: { label: "Last name" },
        email_cont: {}
      },
      columns: 1
    )
  end

  def two_columns
    render SearchFormComponent.new(
      q: User.ransack,
      input_fields: {
        first_name_cont: { label: "First name" },
        last_name_cont: { label: "Last name" },
        email_cont: {},
        phone_cont: { label: "Phone" }
      },
      columns: 2
    )
  end

  def with_collapse
    render SearchFormComponent.new(
      q: User.ransack,
      input_fields: {
        first_name_cont: { label: "First name" },
        last_name_cont: { label: "Last name" },
        email_cont: {},
        phone_cont: { label: "Phone" },
        address_cont: { label: "Address" },
        city_cont: { label: "City" },
        postal_code_cont: { label: "Postal code" }
      },
      columns: 1
    )
  end
end
