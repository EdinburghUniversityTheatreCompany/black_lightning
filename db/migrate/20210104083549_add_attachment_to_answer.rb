class AddAttachmentToAnswer < ActiveRecord::Migration[6.0]
  def up
    # You do not have to create an attachment foreign key on the answer.
    # That field exists on the attachment.

    # Create new attachments for existing files.

    ActiveRecord::Base.transaction do
      ActiveStorage::Attachment.where(record_type: 'Admin::Answer').each do |active_storage_attachment|
        answer = Admin::Answer.find(active_storage_attachment.record_id)

        date = Date.today
        answerable_title = 'Unknown Answerable'

        if answer.answerable_type == 'Admin::Questionnaires::Questionnaire'
          event = answer.answerable.event

          date = event.start_date
          answerable_title = event.name
        end

        if answer.answerable_type == 'Admin::Proposals::Proposal'
          date = answer.answerable.call.submission_deadline.to_date
          answerable_title = "Proposal for #{answer.answerable.show_title}"
        end

        item_name = "? - #{answer.id}"

        question_text = answer.question.question_text.downcase
        if question_text.include?('rig plan')
          item_name = 'Rig Plan'
        elsif question_text.include?('dmx')
          item_name = 'DMX Run'
        elsif question_text.include?('set')
          item_name = 'Set Plan'
        elsif question_text.include?('poster')
          item_name = 'Poster'
        elsif question_text.include?('banner')
          item_name = 'Banner'
        end

        name = "#{date} #{answerable_title} #{item_name}"


        name = "#{name} #{answer.id}" if Attachment.find_by(name: name).present?

        p "Created new attachment called '#{name}'"

        attributes = {
          name: name,
          file_file_name: answer.file_file_name,
          file_content_type: answer.file_content_type,
          file_file_size: answer.file_file_size,
          file_updated_at: answer.file_updated_at,
          item_type: 'Admin::Answer',
          item_id: answer.id,
          access_level: 1
        }

        # Ignore the validations because we can only attach the file once the attachment exists.
        attachment = Attachment.new(attributes)
        attachment.file.attach(answer.file.blob)
        attachment.save!
      end
    end
    # Do not remove columns that refer to a file on answer, yet.
  end

  def down
    # Remove the attachments on answers.
    ActiveRecord::Base.transaction do
      Attachment.where(item_type: 'Admin::Answer').each do |attachment|
        attachment.delete
      end
    end
  end
end
