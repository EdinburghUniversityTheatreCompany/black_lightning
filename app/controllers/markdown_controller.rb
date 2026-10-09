##
# The markdown editor's endpoints.
#
# POST /markdown/preview with a JSON body { input_html: <markdown> } renders a preview.
# POST /markdown/upload stores an image for a signed-in user, attached to the record being edited.
##

class MarkdownController < ApplicationController
  include MdHelper

  skip_authorization_check
  # The editor wants JSON, never a redirect to the completion page, whose bio editor uses these too.
  skip_before_action :require_profile_completion!
  before_action :authenticate_user!, only: :upload
  rate_limit to: 30, within: 1.minute, by: -> { current_user.id }, only: :upload,
             with: -> { render json: { error: "Too many uploads. Try again in a minute." }, status: :too_many_requests }
  before_action :load_item, only: :upload

  ALLOWED_IMAGE_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze

  # The models whose forms render MdEditorComponent: an upload attaches to nothing else. Add a
  # model here when you give its form the editor.
  ITEM_TYPES = %w[
    Admin::Answer Admin::EditableBlock Admin::Feedback Admin::Proposals::Proposal Admin::Question
    AttachmentTag Complaint EventTag FaultReport MarketingCreatives::CategoryInfo
    MarketingCreatives::Profile MassMail News Opportunity PictureTag Review Season Show User Venue
    Workshop
  ].freeze

  def preview
    render json: { rendered_md: render_markdown(params[:input_html]) }
  end

  def upload
    file = params[:image]

    unless file.is_a?(ActionDispatch::Http::UploadedFile) &&
           ALLOWED_IMAGE_TYPES.include?(file.content_type)
      render json: { error: "Invalid file type" }, status: :unprocessable_entity
      return
    end

    stem = File.basename(file.original_filename, ".*").parameterize.truncate(40, omission: "")
    attachment = Attachment.new(
      name: "md-upload-#{stem}-#{SecureRandom.hex(4)}",
      access_level: 2,
      item: @item
    )
    attachment.file.attach(
      io: file.open,
      filename: file.original_filename,
      content_type: file.content_type
    )

    if attachment.save
      render json: { url: attachment_path(attachment.slug), alt: attachment.name }
    else
      render json: { error: attachment.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  private

  # A new record has no id yet, so its images are attached to nothing.
  def load_item
    return if params[:item_id].blank?

    unless ITEM_TYPES.include?(params[:item_type])
      render json: { error: "Unknown item type" }, status: :unprocessable_entity
      return
    end

    @item = params[:item_type].constantize.find_by(id: params[:item_id])
    if @item.nil?
      render json: { error: "Item not found" }, status: :not_found
    elsif !can_save_form_of?(@item)
      render json: { error: "You cannot edit this item" }, status: :forbidden
    end
  end

  # A nested record is edited on its parent's form, so the parent's permission is enough.
  def can_save_form_of?(item)
    return true if can?(:update, item)

    case item
    when Admin::Answer
      parent = item.answerable
      can?(parent.is_a?(Admin::Questionnaires::Questionnaire) ? :set_answers : :update, parent)
    when Admin::Question then can?(:update, item.questionable)
    when MarketingCreatives::CategoryInfo then can?(:update, item.profile)
    when Review then can?(:update, item.event)
    else false
    end
  end
end
