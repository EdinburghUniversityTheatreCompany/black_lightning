# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_01_30_213159) do
  create_table "active_storage_attachments", charset: "utf8mb3", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", charset: "utf8mb3", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", precision: nil, null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", charset: "utf8mb3", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admin_answers", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.text "answer"
    t.integer "answerable_id"
    t.string "answerable_type"
    t.datetime "created_at", precision: nil, null: false
    t.string "file_content_type"
    t.string "file_file_name"
    t.integer "file_file_size"
    t.datetime "file_updated_at", precision: nil
    t.integer "question_id"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["answerable_id"], name: "index_admin_answers_on_answerable_id"
    t.index ["answerable_id"], name: "index_admin_proposals_answers_on_proposal_id"
    t.index ["answerable_type"], name: "index_admin_answers_on_answerable_type"
    t.index ["question_id"], name: "index_admin_proposals_answers_on_question_id"
  end

  create_table "admin_debt_notifications", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.integer "notification_type"
    t.date "sent_on"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
    t.index ["sent_on"], name: "index_admin_debt_notifications_on_sent_on"
    t.index ["user_id"], name: "index_admin_debt_notifications_on_user_id"
  end

  create_table "admin_editable_blocks", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.boolean "admin_page"
    t.text "content"
    t.datetime "created_at", precision: nil, null: false
    t.string "group"
    t.string "name"
    t.bigint "ordering"
    t.datetime "updated_at", precision: nil, null: false
    t.string "url"
  end

  create_table "admin_feedbacks", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", precision: nil, null: false
    t.integer "show_id"
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "admin_maintenance_debts", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.boolean "converted_from_staffing_debt", default: false, null: false
    t.datetime "created_at", precision: nil, null: false
    t.date "due_by"
    t.bigint "maintenance_attendance_id"
    t.integer "show_id"
    t.integer "state", default: 0
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
    t.index ["due_by", "state"], name: "index_admin_maintenance_debts_on_due_by_and_state"
    t.index ["maintenance_attendance_id"], name: "index_admin_maintenance_debts_on_maintenance_attendance_id"
    t.index ["show_id", "converted_from_staffing_debt"], name: "index_admin_maintenance_debts_on_show_and_converted"
    t.index ["user_id"], name: "index_admin_maintenance_debts_on_user_id"
  end

  create_table "admin_permissions", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.string "action"
    t.datetime "created_at", precision: nil, null: false
    t.string "description"
    t.string "name"
    t.string "subject_class"
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "admin_permissions_roles", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.integer "permission_id"
    t.integer "role_id"
    t.index ["role_id"], name: "index_admin_permissions_roles_on_role_id"
  end

  create_table "admin_proposals_call_question_templates", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.string "name"
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "admin_proposals_calls", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.boolean "archived"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "editing_deadline", precision: nil
    t.string "name"
    t.datetime "submission_deadline", precision: nil
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "admin_proposals_proposals", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.integer "call_id"
    t.datetime "created_at", precision: nil, null: false
    t.boolean "late"
    t.text "proposal_text"
    t.text "publicity_text"
    t.string "show_title"
    t.bigint "status", null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["call_id"], name: "index_admin_proposals_proposals_on_call_id"
  end

  create_table "admin_questionnaires_questionnaire_templates", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.string "name"
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "admin_questionnaires_questionnaires", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.integer "event_id"
    t.string "name"
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "admin_questions", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.text "question_text"
    t.integer "questionable_id"
    t.string "questionable_type"
    t.string "response_type"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["questionable_id"], name: "index_admin_questions_on_questionable_id"
    t.index ["questionable_type"], name: "index_admin_questions_on_questionable_type"
  end

  create_table "admin_staffing_debts", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.integer "admin_staffing_job_id"
    t.boolean "converted_from_maintenance_debt", default: false
    t.datetime "created_at", precision: nil, null: false
    t.date "due_by"
    t.integer "show_id"
    t.bigint "state", default: 0, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
    t.index ["due_by", "state"], name: "index_admin_staffing_debts_on_due_by_and_state"
    t.index ["show_id"], name: "index_admin_staffing_debts_on_show_id"
    t.index ["user_id"], name: "index_admin_staffing_debts_on_user_id"
  end

  create_table "admin_staffing_jobs", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.string "name"
    t.datetime "reminder_sent_at"
    t.integer "staffable_id"
    t.string "staffable_type"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
    t.index ["staffable_id"], name: "index_admin_staffing_jobs_on_staffable_id"
    t.index ["staffable_id"], name: "index_admin_staffing_jobs_on_staffing_id"
    t.index ["staffable_type", "staffable_id"], name: "index_admin_staffing_jobs_on_staffable"
    t.index ["staffable_type"], name: "index_admin_staffing_jobs_on_staffable_type"
    t.index ["user_id"], name: "index_admin_staffing_jobs_on_user_id"
  end

  create_table "admin_staffing_templates", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.string "name"
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "admin_staffings", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.boolean "counts_towards_debt"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "end_time", precision: nil
    t.boolean "reminder_job_executed", default: false
    t.integer "reminder_job_id"
    t.string "scheduled_job_id"
    t.string "show_title"
    t.string "slug"
    t.datetime "start_time", precision: nil
    t.datetime "updated_at", precision: nil, null: false
    t.index ["reminder_job_id"], name: "index_admin_staffings_on_reminder_job_id"
    t.index ["slug"], name: "index_admin_staffings_on_slug"
  end

  create_table "attachment_tags", charset: "utf8mb3", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name"
    t.bigint "ordering"
    t.datetime "updated_at", null: false
  end

  create_table "attachment_tags_attachments", id: false, charset: "utf8mb3", force: :cascade do |t|
    t.bigint "attachment_id", null: false
    t.bigint "attachment_tag_id", null: false
  end

  create_table "attachments", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.integer "access_level", default: 1, null: false
    t.datetime "created_at", precision: nil, null: false
    t.integer "editable_block_id"
    t.string "file_content_type"
    t.string "file_file_name"
    t.integer "file_file_size"
    t.datetime "file_updated_at", precision: nil
    t.bigint "item_id"
    t.string "item_type"
    t.string "name"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["item_type", "item_id"], name: "index_attachments_on_item_type_and_item_id"
  end

  create_table "carousel_items", charset: "utf8mb3", force: :cascade do |t|
    t.string "carousel_name"
    t.datetime "created_at", null: false
    t.boolean "is_active"
    t.integer "ordering"
    t.text "tagline"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "url"
  end

  create_table "children_techies", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.integer "child_id"
    t.datetime "created_at", precision: nil, null: false
    t.integer "techie_id"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["techie_id"], name: "index_children_techies_on_techie_id"
  end

  create_table "complaints", charset: "utf8mb3", force: :cascade do |t|
    t.text "comments"
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "resolved"
    t.string "subject"
    t.datetime "updated_at", null: false
  end

  create_table "delayed_jobs", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.integer "attempts", default: 0
    t.datetime "created_at", precision: nil, null: false
    t.string "description"
    t.datetime "failed_at", precision: nil
    t.text "handler"
    t.text "last_error"
    t.datetime "locked_at", precision: nil
    t.string "locked_by"
    t.integer "priority", default: 0
    t.string "queue"
    t.datetime "run_at", precision: nil
    t.datetime "updated_at", precision: nil, null: false
    t.index ["priority", "run_at"], name: "delayed_jobs_priority"
  end

  create_table "emails", charset: "utf8mb3", force: :cascade do |t|
    t.bigint "attached_object_id", null: false
    t.string "attached_object_type", null: false
    t.datetime "created_at", null: false
    t.string "email"
    t.datetime "updated_at", null: false
    t.index ["attached_object_type", "attached_object_id"], name: "index_emails_on_attached_object"
    t.index ["email", "attached_object_id", "attached_object_type"], name: "index_emails_on_email_and_attached_object", unique: true
  end

  create_table "event_tags", charset: "utf8mb3", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name"
    t.bigint "ordering"
    t.datetime "updated_at", null: false
  end

  create_table "event_tags_events", id: false, charset: "utf8mb3", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.bigint "event_tag_id", null: false
  end

  create_table "events", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.string "author"
    t.text "content_warnings"
    t.datetime "created_at", precision: nil, null: false
    t.date "end_date"
    t.string "image_content_type"
    t.string "image_file_name"
    t.integer "image_file_size"
    t.datetime "image_updated_at", precision: nil
    t.boolean "is_public"
    t.date "maintenance_debt_start"
    t.text "members_only_text"
    t.string "name"
    t.boolean "pretix_shown"
    t.string "pretix_slug_override"
    t.string "pretix_view"
    t.string "price"
    t.integer "proposal_id"
    t.text "publicity_text"
    t.integer "season_id"
    t.string "slug"
    t.string "spark_seat_slug"
    t.date "staffing_debt_start"
    t.date "start_date"
    t.string "tagline"
    t.string "type"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "venue_id"
    t.integer "xts_id"
    t.index ["end_date", "is_public"], name: "index_events_on_end_date_and_is_public"
    t.index ["proposal_id"], name: "index_events_on_proposal_id"
    t.index ["season_id"], name: "index_events_on_season_id"
    t.index ["start_date", "end_date"], name: "index_events_on_date_range"
    t.index ["venue_id"], name: "index_events_on_venue_id"
  end

  create_table "fault_reports", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.text "description"
    t.integer "fixed_by_id"
    t.string "item"
    t.integer "reported_by_id"
    t.integer "severity", default: 0
    t.integer "status", default: 0
    t.datetime "updated_at", precision: nil, null: false
    t.index ["fixed_by_id"], name: "index_fault_reports_on_fixed_by_id"
    t.index ["reported_by_id"], name: "index_fault_reports_on_reported_by_id"
    t.index ["severity"], name: "index_fault_reports_on_severity"
    t.index ["status"], name: "index_fault_reports_on_status"
  end

  create_table "maintenance_attendances", charset: "utf8mb3", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "maintenance_session_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["maintenance_session_id"], name: "index_maintenance_attendances_on_maintenance_session_id"
    t.index ["user_id"], name: "index_maintenance_attendances_on_user_id"
  end

  create_table "maintenance_sessions", charset: "utf8mb3", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date"
    t.datetime "updated_at", null: false
  end

  create_table "marketing_creatives_categories", charset: "utf8mb3", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.string "name_on_profile"
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["url"], name: "index_marketing_creatives_categories_on_url"
  end

  create_table "marketing_creatives_category_infos", charset: "utf8mb3", force: :cascade do |t|
    t.bigint "category_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "profile_id"
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_marketing_creatives_category_infos_on_category_id"
    t.index ["profile_id"], name: "index_marketing_creatives_category_infos_on_profile_id"
  end

  create_table "marketing_creatives_profiles", charset: "utf8mb3", force: :cascade do |t|
    t.text "about"
    t.boolean "approved"
    t.text "contact"
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.string "url"
    t.integer "user_id"
    t.index ["url"], name: "index_marketing_creatives_profiles_on_url"
    t.index ["user_id"], name: "index_marketing_creatives_profiles_on_user_id"
  end

  create_table "mass_mails", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", precision: nil, null: false
    t.boolean "draft"
    t.datetime "send_date", precision: nil
    t.integer "sender_id"
    t.string "subject"
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "mass_mails_users", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.integer "mass_mail_id"
    t.integer "user_id"
  end

  create_table "membership_activation_tokens", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.string "token"
    t.string "uid"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
    t.index ["user_id"], name: "index_membership_activation_tokens_on_user_id"
  end

  create_table "membership_cards", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.string "card_number"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
    t.index ["user_id"], name: "index_membership_cards_on_user_id"
  end

  create_table "news", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.integer "author_id"
    t.text "body"
    t.datetime "created_at", precision: nil, null: false
    t.string "image_content_type"
    t.string "image_file_name"
    t.integer "image_file_size"
    t.datetime "image_updated_at", precision: nil
    t.datetime "publish_date", precision: nil
    t.boolean "show_public"
    t.string "slug"
    t.string "title"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["author_id"], name: "index_news_on_author_id"
    t.index ["slug"], name: "index_news_on_slug"
  end

  create_table "newsletter_subscribers", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.string "email"
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "oauth_access_grants", charset: "utf8mb3", force: :cascade do |t|
    t.bigint "application_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.integer "expires_in", null: false
    t.text "redirect_uri", null: false
    t.bigint "resource_owner_id", null: false
    t.datetime "revoked_at", precision: nil
    t.string "scopes", default: "", null: false
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_grants_on_application_id"
    t.index ["resource_owner_id"], name: "index_oauth_access_grants_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_grants_on_token", unique: true
  end

  create_table "oauth_access_tokens", charset: "utf8mb3", force: :cascade do |t|
    t.bigint "application_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.integer "expires_in"
    t.string "previous_refresh_token", default: "", null: false
    t.string "refresh_token"
    t.bigint "resource_owner_id"
    t.datetime "revoked_at", precision: nil
    t.string "scopes"
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_tokens_on_application_id"
    t.index ["refresh_token"], name: "index_oauth_access_tokens_on_refresh_token", unique: true
    t.index ["resource_owner_id"], name: "index_oauth_access_tokens_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_tokens_on_token", unique: true
  end

  create_table "oauth_applications", charset: "utf8mb3", force: :cascade do |t|
    t.boolean "confidential", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.text "redirect_uri", null: false
    t.string "scopes", default: "", null: false
    t.string "secret", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["uid"], name: "index_oauth_applications_on_uid", unique: true
  end

  create_table "oauth_openid_requests", charset: "utf8mb3", force: :cascade do |t|
    t.bigint "access_grant_id", null: false
    t.string "nonce", null: false
    t.index ["access_grant_id"], name: "index_oauth_openid_requests_on_access_grant_id"
  end

  create_table "opportunities", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.boolean "approved"
    t.integer "approver_id"
    t.datetime "created_at", precision: nil, null: false
    t.integer "creator_id"
    t.text "description"
    t.date "expiry_date"
    t.boolean "show_email"
    t.string "title"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["approved", "expiry_date"], name: "index_opportunities_on_approved_and_expiry"
  end

  create_table "picture_tags", charset: "utf8mb3", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "picture_tags_pictures", id: false, charset: "utf8mb3", force: :cascade do |t|
    t.bigint "picture_id", null: false
    t.bigint "picture_tag_id", null: false
  end

  create_table "pictures", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.integer "access_level", default: 2, null: false
    t.datetime "created_at", precision: nil, null: false
    t.text "description"
    t.integer "gallery_id"
    t.string "gallery_type"
    t.string "image_content_type"
    t.string "image_file_name"
    t.integer "image_file_size"
    t.datetime "image_updated_at", precision: nil
    t.datetime "updated_at", precision: nil, null: false
    t.index ["gallery_id"], name: "index_pictures_on_gallery_id"
    t.index ["gallery_type"], name: "index_pictures_on_gallery_type"
  end

  create_table "reviews", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", precision: nil, null: false
    t.integer "event_id"
    t.string "organisation"
    t.decimal "rating", precision: 2, scale: 1
    t.date "review_date"
    t.string "reviewer"
    t.string "title"
    t.datetime "updated_at", precision: nil, null: false
    t.string "url"
  end

  create_table "roles", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.string "name"
    t.bigint "resource_id"
    t.string "resource_type"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["name", "resource_type", "resource_id"], name: "index_roles_on_name_and_resource_type_and_resource_id"
    t.index ["name"], name: "index_roles_on_name"
    t.index ["resource_type", "resource_id"], name: "index_roles_on_resource_type_and_resource_id"
  end

  create_table "solid_queue_blocked_executions", charset: "utf8mb3", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", charset: "utf8mb3", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", charset: "utf8mb3", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", charset: "utf8mb3", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", charset: "utf8mb3", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", charset: "utf8mb3", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", charset: "utf8mb3", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", charset: "utf8mb3", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", charset: "utf8mb3", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", charset: "utf8mb3", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", charset: "utf8mb3", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "team_members", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.string "position"
    t.integer "teamwork_id"
    t.string "teamwork_type"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
    t.index ["teamwork_id", "teamwork_type", "user_id"], name: "index_team_members_on_teamwork_and_user", unique: true
    t.index ["teamwork_id"], name: "index_team_members_on_teamwork_id"
    t.index ["teamwork_type", "teamwork_id"], name: "index_team_members_on_teamwork_type_and_id"
    t.index ["teamwork_type"], name: "index_team_members_on_teamwork_type"
    t.index ["user_id"], name: "index_team_members_on_user_id"
  end

  create_table "techies", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.integer "entry_year"
    t.string "name"
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "users", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.string "associate_id"
    t.string "avatar_content_type"
    t.string "avatar_file_name"
    t.integer "avatar_file_size"
    t.datetime "avatar_updated_at", precision: nil
    t.text "bio"
    t.date "consented"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "current_sign_in_at", precision: nil
    t.string "current_sign_in_ip"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "first_name"
    t.string "last_name"
    t.datetime "last_sign_in_at", precision: nil
    t.string "last_sign_in_ip"
    t.json "not_duplicate_user_ids"
    t.string "phone_number"
    t.boolean "public_profile", default: true
    t.datetime "remember_created_at", precision: nil
    t.string "remember_token"
    t.datetime "reset_password_sent_at", precision: nil
    t.string "reset_password_token"
    t.integer "sign_in_count", default: 0
    t.string "student_id"
    t.datetime "updated_at", precision: nil, null: false
    t.string "username"
    t.index ["associate_id"], name: "index_users_on_associate_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["last_name"], name: "index_users_on_last_name"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["student_id"], name: "index_users_on_student_id"
  end

  create_table "users_roles", id: false, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.integer "role_id"
    t.integer "user_id"
    t.index ["user_id", "role_id"], name: "index_users_roles_on_user_id_and_role_id"
  end

  create_table "venues", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.text "address"
    t.datetime "created_at", precision: nil, null: false
    t.text "description"
    t.string "image_content_type"
    t.string "image_file_name"
    t.integer "image_file_size"
    t.datetime "image_updated_at", precision: nil
    t.string "location"
    t.string "name"
    t.string "tagline"
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "versions", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", precision: nil
    t.string "event", null: false
    t.integer "item_id", null: false
    t.string "item_type", limit: 191, null: false
    t.text "object", size: :long
    t.string "whodunnit"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  create_table "video_links", charset: "utf8mb3", force: :cascade do |t|
    t.integer "access_level", default: 1, null: false
    t.datetime "created_at", null: false
    t.bigint "item_id"
    t.string "item_type"
    t.string "link", null: false
    t.string "name", null: false
    t.integer "order"
    t.datetime "updated_at", null: false
    t.index ["item_type", "item_id"], name: "index_video_links_on_item_type_and_item_id"
  end

  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "admin_debt_notifications", "users"
  add_foreign_key "admin_maintenance_debts", "maintenance_attendances"
  add_foreign_key "events", "admin_proposals_proposals", column: "proposal_id"
  add_foreign_key "maintenance_attendances", "users"
  add_foreign_key "marketing_creatives_category_infos", "marketing_creatives_categories", column: "category_id"
  add_foreign_key "marketing_creatives_category_infos", "marketing_creatives_profiles", column: "profile_id"
  add_foreign_key "marketing_creatives_profiles", "users"
  add_foreign_key "membership_activation_tokens", "users"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_openid_requests", "oauth_access_grants", column: "access_grant_id", on_delete: :cascade
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
end
