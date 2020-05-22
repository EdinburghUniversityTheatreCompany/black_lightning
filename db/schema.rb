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
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20200320112531) do

  create_table "admin_answers", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.integer  "question_id"
    t.integer  "answerable_id"
    t.text     "answer",            limit: 65535
    t.datetime "created_at",                      null: false
    t.datetime "updated_at",                      null: false
    t.string   "answerable_type"
    t.string   "file_file_name"
    t.string   "file_content_type"
    t.integer  "file_file_size"
    t.datetime "file_updated_at"
    t.index ["answerable_id"], name: "index_admin_answers_on_answerable_id", using: :btree
    t.index ["answerable_id"], name: "index_admin_proposals_answers_on_proposal_id", using: :btree
    t.index ["answerable_type"], name: "index_admin_answers_on_answerable_type", using: :btree
    t.index ["question_id"], name: "index_admin_proposals_answers_on_question_id", using: :btree
  end

  create_table "admin_debt_notifications", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.integer  "user_id"
    t.date     "sent_on"
    t.datetime "created_at",        null: false
    t.datetime "updated_at",        null: false
    t.integer  "notification_type"
    t.index ["user_id"], name: "index_admin_debt_notifications_on_user_id", using: :btree
  end

  create_table "admin_editable_blocks", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.string   "name"
    t.text     "content",    limit: 65535
    t.datetime "created_at",               null: false
    t.datetime "updated_at",               null: false
    t.boolean  "admin_page"
    t.string   "group"
  end

  create_table "admin_feedbacks", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.integer  "show_id"
    t.text     "body",       limit: 65535
    t.datetime "created_at",               null: false
    t.datetime "updated_at",               null: false
  end

  create_table "admin_maintenance_debts", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.integer  "user_id"
    t.date     "due_by"
    t.integer  "show_id"
    t.datetime "created_at",             null: false
    t.datetime "updated_at",             null: false
    t.integer  "state",      default: 0
  end

  create_table "admin_permissions", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.string   "name"
    t.string   "description"
    t.string   "action"
    t.string   "subject_class"
    t.datetime "created_at",    null: false
    t.datetime "updated_at",    null: false
  end

  create_table "admin_permissions_roles", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.integer "role_id"
    t.integer "permission_id"
    t.index ["role_id"], name: "index_admin_permissions_roles_on_role_id", using: :btree
  end

  create_table "admin_proposals_call_question_templates", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.string   "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "admin_proposals_calls", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.datetime "deadline"
    t.string   "name"
    t.boolean  "open"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean  "archived"
  end

  create_table "admin_proposals_proposals", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.integer  "call_id"
    t.string   "show_title"
    t.text     "publicity_text", limit: 65535
    t.text     "proposal_text",  limit: 65535
    t.datetime "created_at",                   null: false
    t.datetime "updated_at",                   null: false
    t.boolean  "late"
    t.boolean  "approved"
    t.boolean  "successful"
    t.index ["call_id"], name: "index_admin_proposals_proposals_on_call_id", using: :btree
  end

  create_table "admin_questionnaires_questionnaire_templates", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.string   "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "admin_questionnaires_questionnaires", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.integer  "show_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string   "name"
  end

  create_table "admin_questions", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.text     "question_text",     limit: 65535
    t.string   "response_type"
    t.datetime "created_at",                      null: false
    t.datetime "updated_at",                      null: false
    t.integer  "questionable_id"
    t.string   "questionable_type"
    t.index ["questionable_id"], name: "index_admin_questions_on_questionable_id", using: :btree
    t.index ["questionable_type"], name: "index_admin_questions_on_questionable_type", using: :btree
  end

  create_table "admin_staffing_debts", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.integer  "user_id"
    t.integer  "show_id"
    t.date     "due_by"
    t.integer  "admin_staffing_job_id"
    t.datetime "created_at",                            null: false
    t.datetime "updated_at",                            null: false
    t.boolean  "converted"
    t.boolean  "forgiven",              default: false
  end

  create_table "admin_staffing_jobs", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.string   "name"
    t.integer  "staffable_id"
    t.integer  "user_id"
    t.datetime "created_at",     null: false
    t.datetime "updated_at",     null: false
    t.string   "staffable_type"
    t.index ["staffable_id"], name: "index_admin_staffing_jobs_on_staffable_id", using: :btree
    t.index ["staffable_id"], name: "index_admin_staffing_jobs_on_staffing_id", using: :btree
    t.index ["staffable_type"], name: "index_admin_staffing_jobs_on_staffable_type", using: :btree
    t.index ["user_id"], name: "index_admin_staffing_jobs_on_user_id", using: :btree
  end

  create_table "admin_staffing_templates", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.string   "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "admin_staffings", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.datetime "start_time"
    t.string   "show_title"
    t.datetime "created_at",          null: false
    t.datetime "updated_at",          null: false
    t.integer  "reminder_job_id"
    t.datetime "end_time"
    t.boolean  "counts_towards_debt"
    t.string   "slug"
    t.index ["reminder_job_id"], name: "index_admin_staffings_on_reminder_job_id", using: :btree
    t.index ["slug"], name: "index_admin_staffings_on_slug", using: :btree
  end

  create_table "attachments", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.integer  "editable_block_id"
    t.string   "name"
    t.string   "file_file_name"
    t.string   "file_content_type"
    t.integer  "file_file_size"
    t.datetime "file_updated_at"
    t.datetime "created_at",        null: false
    t.datetime "updated_at",        null: false
    t.index ["editable_block_id"], name: "index_attachments_on_editable_block_id", using: :btree
  end

  create_table "children_techies", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.integer  "techie_id"
    t.integer  "child_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["techie_id"], name: "index_children_techies_on_techie_id", using: :btree
  end

  create_table "delayed_jobs", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.integer  "priority",                  default: 0
    t.integer  "attempts",                  default: 0
    t.text     "handler",     limit: 65535
    t.text     "last_error",  limit: 65535
    t.datetime "run_at"
    t.datetime "locked_at"
    t.datetime "failed_at"
    t.string   "locked_by"
    t.string   "queue"
    t.datetime "created_at",                            null: false
    t.datetime "updated_at",                            null: false
    t.string   "description"
    t.index ["priority", "run_at"], name: "delayed_jobs_priority", using: :btree
  end

  create_table "events", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.string   "name"
    t.string   "tagline"
    t.string   "slug"
    t.text     "description",            limit: 65535
    t.integer  "xts_id"
    t.datetime "created_at",                           null: false
    t.datetime "updated_at",                           null: false
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
    t.string   "spark_seat_slug"
    t.date     "maintenance_debt_start"
    t.date     "staffing_debt_start"
    t.index ["season_id"], name: "index_events_on_season_id", using: :btree
    t.index ["venue_id"], name: "index_events_on_venue_id", using: :btree
  end

  create_table "fault_reports", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.string   "item"
    t.text     "description",    limit: 65535
    t.integer  "severity",                     default: 0
    t.integer  "status",                       default: 0
    t.integer  "reported_by_id"
    t.integer  "fixed_by_id"
    t.datetime "created_at",                               null: false
    t.datetime "updated_at",                               null: false
    t.index ["fixed_by_id"], name: "index_fault_reports_on_fixed_by_id", using: :btree
    t.index ["reported_by_id"], name: "index_fault_reports_on_reported_by_id", using: :btree
    t.index ["severity"], name: "index_fault_reports_on_severity", using: :btree
    t.index ["status"], name: "index_fault_reports_on_status", using: :btree
  end

  create_table "mass_mails", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.integer  "sender_id"
    t.string   "subject"
    t.text     "body",       limit: 65535
    t.datetime "send_date"
    t.boolean  "draft"
    t.datetime "created_at",               null: false
    t.datetime "updated_at",               null: false
  end

  create_table "mass_mails_users", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.integer "mass_mail_id"
    t.integer "user_id"
  end

  create_table "membership_activation_tokens", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.string   "uid"
    t.string   "token"
    t.integer  "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_membership_activation_tokens_on_user_id", using: :btree
  end

  create_table "membership_cards", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.string   "card_number"
    t.integer  "user_id"
    t.datetime "created_at",  null: false
    t.datetime "updated_at",  null: false
  end

  create_table "news", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.string   "title"
    t.text     "body",               limit: 65535
    t.string   "slug"
    t.datetime "publish_date"
    t.boolean  "show_public"
    t.datetime "created_at",                       null: false
    t.datetime "updated_at",                       null: false
    t.string   "image_file_name"
    t.string   "image_content_type"
    t.integer  "image_file_size"
    t.datetime "image_updated_at"
    t.integer  "author_id"
    t.index ["author_id"], name: "index_news_on_author_id", using: :btree
  end

  create_table "newsletter_subscribers", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.string   "email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "opportunities", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.string   "title"
    t.text     "description", limit: 65535
    t.boolean  "show_email"
    t.boolean  "approved"
    t.integer  "creator_id"
    t.integer  "approver_id"
    t.date     "expiry_date"
    t.datetime "created_at",                null: false
    t.datetime "updated_at",                null: false
  end

  create_table "pictures", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.text     "description",        limit: 65535
    t.integer  "gallery_id"
    t.string   "gallery_type"
    t.string   "image_file_name"
    t.string   "image_content_type"
    t.integer  "image_file_size"
    t.datetime "image_updated_at"
    t.datetime "created_at",                       null: false
    t.datetime "updated_at",                       null: false
    t.index ["gallery_id"], name: "index_pictures_on_gallery_id", using: :btree
    t.index ["gallery_type"], name: "index_pictures_on_gallery_type", using: :btree
  end

  create_table "reviews", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.integer  "show_id"
    t.string   "reviewer"
    t.text     "body",         limit: 65535
    t.decimal  "rating",                     precision: 2, scale: 1
    t.date     "review_date"
    t.datetime "created_at",                                         null: false
    t.datetime "updated_at",                                         null: false
    t.string   "organisation"
  end

  create_table "roles", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.string   "name"
    t.integer  "resource_id"
    t.string   "resource_type"
    t.datetime "created_at",    null: false
    t.datetime "updated_at",    null: false
    t.index ["name", "resource_type", "resource_id"], name: "index_roles_on_name_and_resource_type_and_resource_id", using: :btree
    t.index ["name"], name: "index_roles_on_name", using: :btree
  end

  create_table "team_members", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.string   "position"
    t.integer  "user_id"
    t.integer  "teamwork_id"
    t.datetime "created_at",    null: false
    t.datetime "updated_at",    null: false
    t.string   "teamwork_type"
    t.index ["teamwork_id"], name: "index_team_members_on_teamwork_id", using: :btree
    t.index ["teamwork_type"], name: "index_team_members_on_teamwork_type", using: :btree
    t.index ["user_id"], name: "index_team_members_on_user_id", using: :btree
  end

  create_table "techies", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.string   "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.string   "email",                                default: "",   null: false
    t.string   "encrypted_password",                   default: "",   null: false
    t.string   "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer  "sign_in_count",                        default: 0
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string   "current_sign_in_ip"
    t.string   "last_sign_in_ip"
    t.string   "first_name"
    t.string   "last_name"
    t.datetime "created_at",                                          null: false
    t.datetime "updated_at",                                          null: false
    t.string   "phone_number"
    t.boolean  "public_profile",                       default: true
    t.text     "bio",                    limit: 65535
    t.string   "avatar_file_name"
    t.string   "avatar_content_type"
    t.integer  "avatar_file_size"
    t.datetime "avatar_updated_at"
    t.string   "username"
    t.string   "remember_token"
    t.date     "consented"
    t.index ["email"], name: "index_users_on_email", unique: true, using: :btree
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true, using: :btree
  end

  create_table "users_roles", id: false, force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.integer "user_id"
    t.integer "role_id"
    t.index ["user_id", "role_id"], name: "index_users_roles_on_user_id_and_role_id", using: :btree
  end

  create_table "venues", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.string   "name"
    t.string   "tagline"
    t.text     "description",        limit: 65535
    t.string   "location"
    t.string   "image_file_name"
    t.string   "image_content_type"
    t.integer  "image_file_size"
    t.datetime "image_updated_at"
    t.datetime "created_at",                       null: false
    t.datetime "updated_at",                       null: false
  end

  create_table "versions", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci" do |t|
    t.string   "item_type",  limit: 191,        null: false
    t.integer  "item_id",                       null: false
    t.string   "event",                         null: false
    t.string   "whodunnit"
    t.text     "object",     limit: 4294967295
    t.datetime "created_at"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id", using: :btree
  end

  add_foreign_key "admin_debt_notifications", "users"
  add_foreign_key "membership_activation_tokens", "users"
end
