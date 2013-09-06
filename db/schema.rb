# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended to check this file into your version control system.

ActiveRecord::Schema.define(:version => 20130906133225) do

  create_table "admin_answers", :force => true do |t|
    t.integer  "question_id"
    t.integer  "answerable_id"
    t.text     "answer"
    t.datetime "created_at",        :null => false
    t.datetime "updated_at",        :null => false
    t.string   "answerable_type"
    t.string   "file_file_name"
    t.string   "file_content_type"
    t.integer  "file_file_size"
    t.datetime "file_updated_at"
  end

  add_index "admin_answers", ["answerable_id"], :name => "index_admin_answers_on_answerable_id"
  add_index "admin_answers", ["answerable_id"], :name => "index_admin_proposals_answers_on_proposal_id"
  add_index "admin_answers", ["answerable_type"], :name => "index_admin_answers_on_answerable_type"
  add_index "admin_answers", ["question_id"], :name => "index_admin_proposals_answers_on_question_id"

  create_table "admin_editable_blocks", :force => true do |t|
    t.string   "name"
    t.text     "content"
    t.datetime "created_at", :null => false
    t.datetime "updated_at", :null => false
    t.boolean  "admin_page"
    t.string   "group"
  end

  create_table "admin_feedbacks", :force => true do |t|
    t.integer  "show_id"
    t.text     "body"
    t.datetime "created_at", :null => false
    t.datetime "updated_at", :null => false
  end

  create_table "admin_permissions", :force => true do |t|
    t.string   "name"
    t.string   "description"
    t.string   "action"
    t.string   "subject_class"
    t.datetime "created_at",    :null => false
    t.datetime "updated_at",    :null => false
  end

  create_table "admin_proposals_call_question_templates", :force => true do |t|
    t.string   "name"
    t.datetime "created_at", :null => false
    t.datetime "updated_at", :null => false
  end

  create_table "admin_proposals_calls", :force => true do |t|
    t.datetime "deadline"
    t.string   "name"
    t.boolean  "open"
    t.datetime "created_at", :null => false
    t.datetime "updated_at", :null => false
    t.boolean  "archived"
  end

  create_table "admin_proposals_proposals", :force => true do |t|
    t.integer  "call_id"
    t.string   "show_title"
    t.text     "publicity_text"
    t.text     "proposal_text"
    t.datetime "created_at",     :null => false
    t.datetime "updated_at",     :null => false
    t.boolean  "late"
    t.boolean  "approved"
    t.boolean  "successful"
  end

  add_index "admin_proposals_proposals", ["call_id"], :name => "index_admin_proposals_proposals_on_call_id"

  create_table "admin_questionnaires_questionnaire_templates", :force => true do |t|
    t.string   "name"
    t.datetime "created_at", :null => false
    t.datetime "updated_at", :null => false
  end

  create_table "admin_questionnaires_questionnaires", :force => true do |t|
    t.integer  "show_id"
    t.datetime "created_at", :null => false
    t.datetime "updated_at", :null => false
    t.string   "name"
  end

  create_table "admin_questions", :force => true do |t|
    t.text     "question_text"
    t.string   "response_type"
    t.datetime "created_at",        :null => false
    t.datetime "updated_at",        :null => false
    t.integer  "questionable_id"
    t.string   "questionable_type"
  end

  add_index "admin_questions", ["questionable_id"], :name => "index_admin_questions_on_questionable_id"
  add_index "admin_questions", ["questionable_type"], :name => "index_admin_questions_on_questionable_type"

  create_table "admin_staffing_jobs", :force => true do |t|
    t.string   "name"
    t.integer  "staffable_id"
    t.integer  "user_id"
    t.datetime "created_at",     :null => false
    t.datetime "updated_at",     :null => false
    t.string   "staffable_type"
  end

  add_index "admin_staffing_jobs", ["staffable_id"], :name => "index_admin_staffing_jobs_on_staffable_id"
  add_index "admin_staffing_jobs", ["staffable_id"], :name => "index_admin_staffing_jobs_on_staffing_id"
  add_index "admin_staffing_jobs", ["staffable_type"], :name => "index_admin_staffing_jobs_on_staffable_type"
  add_index "admin_staffing_jobs", ["user_id"], :name => "index_admin_staffing_jobs_on_user_id"

  create_table "admin_staffing_templates", :force => true do |t|
    t.string   "name"
    t.datetime "created_at", :null => false
    t.datetime "updated_at", :null => false
  end

  create_table "admin_staffings", :force => true do |t|
    t.datetime "start_time"
    t.string   "show_title"
    t.datetime "created_at",      :null => false
    t.datetime "updated_at",      :null => false
    t.integer  "reminder_job_id"
    t.datetime "end_time"
  end

  add_index "admin_staffings", ["reminder_job_id"], :name => "index_admin_staffings_on_reminder_job_id"

  create_table "attachments", :force => true do |t|
    t.integer  "editable_block_id"
    t.string   "name"
    t.string   "file_file_name"
    t.string   "file_content_type"
    t.integer  "file_file_size"
    t.datetime "file_updated_at"
    t.datetime "created_at",        :null => false
    t.datetime "updated_at",        :null => false
  end

  add_index "attachments", ["editable_block_id"], :name => "index_attachments_on_editable_block_id"

  create_table "children_techies", :force => true do |t|
    t.integer  "techie_id"
    t.integer  "child_id"
    t.datetime "created_at", :null => false
    t.datetime "updated_at", :null => false
  end

  add_index "children_techies", ["techie_id"], :name => "index_children_techies_on_techie_id"

  create_table "delayed_jobs", :force => true do |t|
    t.integer  "priority",    :default => 0
    t.integer  "attempts",    :default => 0
    t.text     "handler"
    t.text     "last_error"
    t.datetime "run_at"
    t.datetime "locked_at"
    t.datetime "failed_at"
    t.string   "locked_by"
    t.string   "queue"
    t.datetime "created_at",                 :null => false
    t.datetime "updated_at",                 :null => false
    t.string   "description"
  end

  add_index "delayed_jobs", ["priority", "run_at"], :name => "delayed_jobs_priority"

  create_table "events", :force => true do |t|
    t.string   "name"
    t.string   "tagline"
    t.string   "slug"
    t.text     "description"
    t.integer  "xts_id"
    t.datetime "created_at",         :null => false
    t.datetime "updated_at",         :null => false
    t.boolean  "is_public"
    t.string   "image_file_name"
    t.string   "image_content_type"
    t.integer  "image_file_size"
    t.datetime "image_updated_at"
    t.date     "start_date"
    t.date     "end_date"
    t.integer  "venue_id"
    t.integer  "season_id"
    t.string   "author"
    t.string   "type"
    t.string   "price"
  end

  add_index "events", ["season_id"], :name => "index_events_on_season_id"
  add_index "events", ["venue_id"], :name => "index_events_on_venue_id"

  create_table "mass_mails", :force => true do |t|
    t.integer  "sender_id"
    t.string   "subject"
    t.text     "body"
    t.datetime "send_date"
    t.boolean  "draft"
    t.datetime "created_at", :null => false
    t.datetime "updated_at", :null => false
  end

  create_table "mass_mails_users", :force => true do |t|
    t.integer "mass_mail_id"
    t.integer "user_id"
  end

  create_table "membership_cards", :force => true do |t|
    t.string   "card_number"
    t.integer  "user_id"
    t.datetime "created_at",  :null => false
    t.datetime "updated_at",  :null => false
  end

  create_table "news", :force => true do |t|
    t.string   "title"
    t.text     "body"
    t.string   "slug"
    t.datetime "publish_date"
    t.boolean  "show_public"
    t.datetime "created_at",         :null => false
    t.datetime "updated_at",         :null => false
    t.string   "image_file_name"
    t.string   "image_content_type"
    t.integer  "image_file_size"
    t.datetime "image_updated_at"
    t.integer  "author_id"
  end

  add_index "news", ["author_id"], :name => "index_news_on_author_id"

  create_table "newsletter_subscribers", :force => true do |t|
    t.string   "email"
    t.datetime "created_at", :null => false
    t.datetime "updated_at", :null => false
  end

  create_table "opportunities", :force => true do |t|
    t.string   "title"
    t.text     "description"
    t.boolean  "show_email"
    t.boolean  "approved"
    t.integer  "creator_id"
    t.integer  "approver_id"
    t.date     "expiry_date"
    t.datetime "created_at",  :null => false
    t.datetime "updated_at",  :null => false
  end

  create_table "permissions_roles", :force => true do |t|
    t.integer "role_id"
    t.integer "permission_id"
  end

  add_index "permissions_roles", ["role_id"], :name => "index_permissions_roles_on_role_id"

  create_table "pictures", :force => true do |t|
    t.text     "description"
    t.integer  "gallery_id"
    t.string   "gallery_type"
    t.string   "image_file_name"
    t.string   "image_content_type"
    t.integer  "image_file_size"
    t.datetime "image_updated_at"
    t.datetime "created_at",         :null => false
    t.datetime "updated_at",         :null => false
  end

  add_index "pictures", ["gallery_id"], :name => "index_pictures_on_gallery_id"
  add_index "pictures", ["gallery_type"], :name => "index_pictures_on_gallery_type"

  create_table "reviews", :force => true do |t|
    t.integer  "show_id"
    t.string   "reviewer"
    t.text     "body"
    t.decimal  "rating",       :precision => 2, :scale => 1
    t.date     "review_date"
    t.datetime "created_at",                                 :null => false
    t.datetime "updated_at",                                 :null => false
    t.string   "organisation"
  end

  create_table "roles", :force => true do |t|
    t.string   "name"
    t.integer  "resource_id"
    t.string   "resource_type"
    t.datetime "created_at",    :null => false
    t.datetime "updated_at",    :null => false
  end

  add_index "roles", ["name", "resource_type", "resource_id"], :name => "index_roles_on_name_and_resource_type_and_resource_id"
  add_index "roles", ["name"], :name => "index_roles_on_name"

  create_table "team_members", :force => true do |t|
    t.string   "position"
    t.integer  "user_id"
    t.integer  "teamwork_id"
    t.datetime "created_at",    :null => false
    t.datetime "updated_at",    :null => false
    t.string   "teamwork_type"
    t.integer  "display_order"
  end

  add_index "team_members", ["teamwork_id"], :name => "index_team_members_on_teamwork_id"
  add_index "team_members", ["teamwork_type"], :name => "index_team_members_on_teamwork_type"
  add_index "team_members", ["user_id"], :name => "index_team_members_on_user_id"

  create_table "techies", :force => true do |t|
    t.string   "name"
    t.datetime "created_at", :null => false
    t.datetime "updated_at", :null => false
  end

  create_table "users", :force => true do |t|
    t.string   "email",                  :default => "",   :null => false
    t.string   "encrypted_password",     :default => "",   :null => false
    t.string   "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer  "sign_in_count",          :default => 0
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string   "current_sign_in_ip"
    t.string   "last_sign_in_ip"
    t.string   "first_name"
    t.string   "last_name"
    t.datetime "created_at",                               :null => false
    t.datetime "updated_at",                               :null => false
    t.string   "phone_number"
    t.boolean  "public_profile",         :default => true
    t.text     "bio"
    t.string   "avatar_file_name"
    t.string   "avatar_content_type"
    t.integer  "avatar_file_size"
    t.datetime "avatar_updated_at"
    t.string   "stripe_customer_id"
  end

  add_index "users", ["email"], :name => "index_users_on_email", :unique => true
  add_index "users", ["reset_password_token"], :name => "index_users_on_reset_password_token", :unique => true

  create_table "users_roles", :id => false, :force => true do |t|
    t.integer "user_id"
    t.integer "role_id"
  end

  add_index "users_roles", ["user_id", "role_id"], :name => "index_users_roles_on_user_id_and_role_id"

  create_table "venues", :force => true do |t|
    t.string   "name"
    t.string   "tagline"
    t.text     "description"
    t.string   "location"
    t.string   "image_file_name"
    t.string   "image_content_type"
    t.integer  "image_file_size"
    t.datetime "image_updated_at"
    t.datetime "created_at",         :null => false
    t.datetime "updated_at",         :null => false
  end

end
