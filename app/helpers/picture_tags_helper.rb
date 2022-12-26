module PictureTagsHelper
  def get_link_to_pictures_for_tag(picture_tag)
    return link_to('View Pictures', admin_pictures_path('q[picture_tags_id_eq]' => picture_tag.id), { class: 'btn btn-secondary' })
  end
end
