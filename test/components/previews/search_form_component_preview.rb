class SearchFormComponentPreview < ViewComponent::Preview
  FIELDS = {
    first_name_cont: { label: "First name" },
    last_name_cont: { label: "Last name" },
    email_cont: {},
    phone_number_cont: { label: "Phone" },
    username_cont: { label: "Username" },
    student_id_cont: { label: "Student ID" },
    member_id_cont: { label: "Member ID" }
  }.freeze

  def default = form(3, 1)
  def two_columns = form(4, 2)
  def with_collapse = form(7, 1)

  private

  def form(count, columns)
    q = User.ransack({}, auth_object: Ability.new(User.first))
    render SearchFormComponent.new(q:, input_fields: FIELDS.first(count).to_h, columns:)
  end
end
