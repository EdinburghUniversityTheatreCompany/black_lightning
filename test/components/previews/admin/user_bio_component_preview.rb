class Admin::UserBioComponentPreview < Admin::ApplicationComponentPreview
  # User with both avatar and bio
  def default
    user = User.where.not(bio: [ nil, "" ]).first || sample_user
    render Admin::UserBioComponent.new(user: user)
  end

  # User with no bio set
  def no_bio
    user = User.where(bio: [ nil, "" ]).first || sample_user
    render Admin::UserBioComponent.new(user: user)
  end

  # User with no avatar
  def no_avatar
    user = User.left_joins(:avatar_attachment).where(active_storage_attachments: { id: nil }).where.not(bio: [ nil, "" ]).first || sample_user
    render Admin::UserBioComponent.new(user: user)
  end
end
