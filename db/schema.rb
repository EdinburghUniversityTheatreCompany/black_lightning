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
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20150506155951) do

  create_table "admin_answers", force: :cascade do |t|
    t.integer  "question_id",       limit: 4
    t.integer  "answerable_id",     limit: 4
    t.text     "answer",            limit: 65535
    t.datetime "created_at",                      null: false
    t.datetime "updated_at",                      null: false
    t.string   "answerable_type",   limit: 255
    t.string   "file_file_name",    limit: 255
    t.string   "file_content_type", limit: 255
    t.integer  "file_file_size",    limit: 4
    t.datetime "file_updated_at"
  end

  add_index "admin_answers", ["answerable_id"], name: "index_admin_answers_on_answerable_id", using: :btree
  add_index "admin_answers", ["answerable_id"], name: "index_admin_proposals_answers_on_proposal_id", using: :btree
  add_index "admin_answers", ["answerable_type"], name: "index_admin_answers_on_answerable_type", using: :btree
  add_index "admin_answers", ["question_id"], name: "index_admin_proposals_answers_on_question_id", using: :btree

  create_table "admin_editable_blocks", force: :cascade do |t|
    t.string   "name",       limit: 255
    t.text     "content",    limit: 65535
    t.datetime "created_at",               null: false
    t.datetime "updated_at",               null: false
    t.boolean  "admin_page", limit: 1
    t.string   "group",      limit: 255
  end

  create_table "admin_feedbacks", force: :cascade do |t|
    t.integer  "show_id",    limit: 4
    t.text     "body",       limit: 65535
    t.datetime "created_at",               null: false
    t.datetime "updated_at",               null: false
  end

  create_table "admin_permissions", force: :cascade do |t|
    t.string   "name",          limit: 255
    t.string   "description",   limit: 255
    t.string   "action",        limit: 255
    t.string   "subject_class", limit: 255
    t.datetime "created_at",                null: false
    t.datetime "updated_at",                null: false
  end

  create_table "admin_permissions_roles", force: :cascade do |t|
    t.integer "role_id",       limit: 4
    t.integer "permission_id", limit: 4
  end

  add_index "admin_permissions_roles", ["role_id"], name: "index_admin_permissions_roles_on_role_id", using: :btree

  create_table "admin_proposals_call_question_templates", force: :cascade do |t|
    t.string   "name",       limit: 255
    t.datetime "created_at",             null: false
    t.datetime "updated_at",             null: false
  end

  create_table "admin_proposals_calls", force: :cascade do |t|
    t.datetime "deadline"
    t.string   "name",       limit: 255
    t.boolean  "open",       limit: 1
    t.datetime "created_at",             null: false
    t.datetime "updated_at",             null: false
    t.boolean  "archived",   limit: 1
  end

  create_table "admin_proposals_proposals", force: :cascade do |t|
    t.integer  "call_id",        limit: 4
    t.string   "show_title",     limit: 255
    t.text     "publicity_text", limit: 65535
    t.text     "proposal_text",  limit: 65535
    t.datetime "created_at",                   null: false
    t.datetime "updated_at",                   null: false
    t.boolean  "late",           limit: 1
    t.boolean  "approved",       limit: 1
    t.boolean  "successful",     limit: 1
  end

  add_index "admin_proposals_proposals", ["call_id"], name: "index_admin_proposals_proposals_on_call_id", using: :btree

  create_table "admin_questionnaires_questionnaire_templates", force: :cascade do |t|
    t.string   "name",       limit: 255
    t.datetime "created_at",             null: false
    t.datetime "updated_at",             null: false
  end

  create_table "admin_questionnaires_questionnaires", force: :cascade do |t|
    t.integer  "show_id",    limit: 4
    t.datetime "created_at",             null: false
    t.datetime "updated_at",             null: false
    t.string   "name",       limit: 255
  end

  create_table "admin_questions", force: :cascade do |t|
    t.text     "question_text",     limit: 65535
    t.string   "response_type",     limit: 255
    t.datetime "created_at",                      null: false
    t.datetime "updated_at",                      null: false
    t.integer  "questionable_id",   limit: 4
    t.string   "questionable_type", limit: 255
  end

  add_index "admin_questions", ["questionable_id"], name: "index_admin_questions_on_questionable_id", using: :btree
  add_index "admin_questions", ["questionable_type"], name: "index_admin_questions_on_questionable_type", using: :btree

  create_table "admin_staffing_jobs", force: :cascade do |t|
    t.string   "name",           limit: 255
    t.integer  "staffable_id",   limit: 4
    t.integer  "user_id",        limit: 4
    t.datetime "created_at",                 null: false
    t.datetime "updated_at",                 null: false
    t.string   "staffable_type", limit: 255
  end

  add_index "admin_staffing_jobs", ["staffable_id"], name: "index_admin_staffing_jobs_on_staffable_id", using: :btree
  add_index "admin_staffing_jobs", ["staffable_id"], name: "index_admin_staffing_jobs_on_staffing_id", using: :btree
  add_index "admin_staffing_jobs", ["staffable_type"], name: "index_admin_staffing_jobs_on_staffable_type", using: :btree
  add_index "admin_staffing_jobs", ["user_id"], name: "index_admin_staffing_jobs_on_user_id", using: :btree

  create_table "admin_staffing_templates", force: :cascade do |t|
    t.string   "name",       limit: 255
    t.datetime "created_at",             null: false
    t.datetime "updated_at",             null: false
  end

  create_table "admin_staffings", force: :cascade do |t|
    t.datetime "start_time"
    t.string   "show_title",      limit: 255
    t.datetime "created_at",                  null: false
    t.datetime "updated_at",                  null: false
    t.integer  "reminder_job_id", limit: 4
    t.datetime "end_time"
  end

  add_index "admin_staffings", ["reminder_job_id"], name: "index_admin_staffings_on_reminder_job_id", using: :btree

  create_table "attachments", force: :cascade do |t|
    t.integer  "editable_block_id", limit: 4
    t.string   "name",              limit: 255
    t.string   "file_file_name",    limit: 255
    t.string   "file_content_type", limit: 255
    t.integer  "file_file_size",    limit: 4
    t.datetime "file_updated_at"
    t.datetime "created_at",                    null: false
    t.datetime "updated_at",                    null: false
  end

  add_index "attachments", ["editable_block_id"], name: "index_attachments_on_editable_block_id", using: :btree

  create_table "children_techies", force: :cascade do |t|
    t.integer  "techie_id",  limit: 4
    t.integer  "child_id",   limit: 4
    t.datetime "created_at",           null: false
    t.datetime "updated_at",           null: false
  end

  add_index "children_techies", ["techie_id"], name: "index_children_techies_on_techie_id", using: :btree

  create_table "delayed_jobs", force: :cascade do |t|
    t.integer  "priority",    limit: 4,     default: 0
    t.integer  "attempts",    limit: 4,     default: 0
    t.text     "handler",     limit: 65535
    t.text     "last_error",  limit: 65535
    t.datetime "run_at"
    t.datetime "locked_at"
    t.datetime "failed_at"
    t.string   "locked_by",   limit: 255
    t.string   "queue",       limit: 255
    t.datetime "created_at",                            null: false
    t.datetime "updated_at",                            null: false
    t.string   "description", limit: 255
  end

  add_index "delayed_jobs", ["priority", "run_at"], name: "delayed_jobs_priority", using: :btree

  create_table "events", force: :cascade do |t|
    t.string   "name",               limit: 255
    t.string   "tagline",            limit: 255
    t.string   "slug",               limit: 255
    t.text     "description",        limit: 65535
    t.integer  "xts_id",             limit: 4
    t.datetime "created_at",                       null: false
    t.datetime "updated_at",                       null: false
    t.boolean  "is_public",          limit: 1
    t.string   "image_file_name",    limit: 255
    t.string   "image_content_type", limit: 255
    t.integer  "image_file_size",    limit: 4
    t.datetime "image_updated_at"
    t.date     "start_date"
    t.date     "end_date"
    t.integer  "venue_id",           limit: 4
    t.integer  "season_id",          limit: 4
    t.string   "author",             limit: 255
    t.string   "type",               limit: 255
    t.string   "price",              limit: 255
    t.string   "spark_seat_slug",    limit: 255
  end

  add_index "events", ["season_id"], name: "index_events_on_season_id", using: :btree
  add_index "events", ["venue_id"], name: "index_events_on_venue_id", using: :btree

  create_table "mass_mails", force: :cascade do |t|
    t.integer  "sender_id",  limit: 4
    t.string   "subject",    limit: 255
    t.text     "body",       limit: 65535
    t.datetime "send_date"
    t.boolean  "draft",      limit: 1
    t.datetime "created_at",               null: false
    t.datetime "updated_at",               null: false
  end

  create_table "mass_mails_users", force: :cascade do |t|
    t.integer "mass_mail_id", limit: 4
    t.integer "user_id",      limit: 4
  end

  create_table "membership_cards", force: :cascade do |t|
    t.string   "card_number", limit: 255
    t.integer  "user_id",     limit: 4
    t.datetime "created_at",              null: false
    t.datetime "updated_at",              null: false
  end

  create_table "news", force: :cascade do |t|
    t.string   "title",              limit: 255
    t.text     "body",               limit: 65535
    t.string   "slug",               limit: 255
    t.datetime "publish_date"
    t.boolean  "show_public",        limit: 1
    t.datetime "created_at",                       null: false
    t.datetime "updated_at",                       null: false
    t.string   "image_file_name",    limit: 255
    t.string   "image_content_type", limit: 255
    t.integer  "image_file_size",    limit: 4
    t.datetime "image_updated_at"
    t.integer  "author_id",          limit: 4
  end

  add_index "news", ["author_id"], name: "index_news_on_author_id", using: :btree

  create_table "newsletter_subscribers", force: :cascade do |t|
    t.string   "email",      limit: 255
    t.datetime "created_at",             null: false
    t.datetime "updated_at",             null: false
  end

  create_table "opportunities", force: :cascade do |t|
    t.string   "title",       limit: 255
    t.text     "description", limit: 65535
    t.boolean  "show_email",  limit: 1
    t.boolean  "approved",    limit: 1
    t.integer  "creator_id",  limit: 4
    t.integer  "approver_id", limit: 4
    t.date     "expiry_date"
    t.datetime "created_at",                null: false
    t.datetime "updated_at",                null: false
  end

  create_table "pictures", force: :cascade do |t|
    t.text     "description",        limit: 65535
    t.integer  "gallery_id",         limit: 4
    t.string   "gallery_type",       limit: 255
    t.string   "image_file_name",    limit: 255
    t.string   "image_content_type", limit: 255
    t.integer  "image_file_size",    limit: 4
    t.datetime "image_updated_at"
    t.datetime "created_at",                       null: false
    t.datetime "updated_at",                       null: false
  end

  add_index "pictures", ["gallery_id"], name: "index_pictures_on_gallery_id", using: :btree
  add_index "pictures", ["gallery_type"], name: "index_pictures_on_gallery_type", using: :btree

  create_table "reviews", force: :cascade do |t|
    t.integer  "show_id",      limit: 4
    t.string   "reviewer",     limit: 255
    t.text     "body",         limit: 65535
    t.decimal  "rating",                     precision: 2, scale: 1
    t.date     "review_date"
    t.datetime "created_at",                                         null: false
    t.datetime "updated_at",                                         null: false
    t.string   "organisation", limit: 255
  end

  create_table "roles", force: :cascade do |t|
    t.string   "name",          limit: 255
    t.integer  "resource_id",   limit: 4
    t.string   "resource_type", limit: 255
    t.datetime "created_at",                null: false
    t.datetime "updated_at",                null: false
  end

  add_index "roles", ["name", "resource_type", "resource_id"], name: "index_roles_on_name_and_resource_type_and_resource_id", using: :btree
  add_index "roles", ["name"], name: "index_roles_on_name", using: :btree

  create_table "team_members", force: :cascade do |t|
    t.string   "position",      limit: 255
    t.integer  "user_id",       limit: 4
    t.integer  "teamwork_id",   limit: 4
    t.datetime "created_at",                null: false
    t.datetime "updated_at",                null: false
    t.string   "teamwork_type", limit: 255
    t.integer  "display_order", limit: 4
  end

  add_index "team_members", ["teamwork_id"], name: "index_team_members_on_teamwork_id", using: :btree
  add_index "team_members", ["teamwork_type"], name: "index_team_members_on_teamwork_type", using: :btree
  add_index "team_members", ["user_id"], name: "index_team_members_on_user_id", using: :btree

  create_table "techies", force: :cascade do |t|
    t.string   "name",       limit: 255
    t.datetime "created_at",             null: false
    t.datetime "updated_at",             null: false
  end

  create_table "users", force: :cascade do |t|
    t.string   "email",                  limit: 255,   default: "",   null: false
    t.string   "encrypted_password",     limit: 255,   default: "",   null: false
    t.string   "reset_password_token",   limit: 255
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer  "sign_in_count",          limit: 4,     default: 0
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string   "current_sign_in_ip",     limit: 255
    t.string   "last_sign_in_ip",        limit: 255
    t.string   "first_name",             limit: 255
    t.string   "last_name",              limit: 255
    t.datetime "created_at",                                          null: false
    t.datetime "updated_at",                                          null: false
    t.string   "phone_number",           limit: 255
    t.boolean  "public_profile",         limit: 1,     default: true
    t.text     "bio",                    limit: 65535
    t.string   "avatar_file_name",       limit: 255
    t.string   "avatar_content_type",    limit: 255
    t.integer  "avatar_file_size",       limit: 4
    t.datetime "avatar_updated_at"
  end

  add_index "users", ["email"], name: "index_users_on_email", unique: true, using: :btree
  add_index "users", ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true, using: :btree

  create_table "users_roles", id: false, force: :cascade do |t|
    t.integer "user_id", limit: 4
    t.integer "role_id", limit: 4
  end

  add_index "users_roles", ["user_id", "role_id"], name: "index_users_roles_on_user_id_and_role_id", using: :btree

  create_table "venues", force: :cascade do |t|
    t.string   "name",               limit: 255
    t.string   "tagline",            limit: 255
    t.text     "description",        limit: 65535
    t.string   "location",           limit: 255
    t.string   "image_file_name",    limit: 255
    t.string   "image_content_type", limit: 255
    t.integer  "image_file_size",    limit: 4
    t.datetime "image_updated_at"
    t.datetime "created_at",                       null: false
    t.datetime "updated_at",                       null: false
  end

end
