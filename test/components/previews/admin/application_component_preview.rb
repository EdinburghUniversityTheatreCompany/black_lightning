class Admin::ApplicationComponentPreview < ViewComponent::Preview
  private

  def sample_user
    User.where.not(first_name: [ nil, "" ]).first || User.first!
  end
end
