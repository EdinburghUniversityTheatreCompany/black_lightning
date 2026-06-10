class ReplaceRoleCategoryWithDepartment < ActiveRecord::Migration[8.1]
  # Default departments, in the same order as the old category enum, so the index
  # doubles as the old category integer for backfilling.
  DEFAULTS = [
    [ "Acting",           "actor, acting, cast" ],
    [ "Directing",        "director, directing, assistant director" ],
    [ "Stage Management", "stage manager, sm, asm, stage management, deputy stage" ],
    [ "Lighting",         "light, lx, lighting" ],
    [ "Sound",            "sound, sfx, audio" ],
    [ "Set",              "set, scenic, build" ],
    [ "Costume",          "costume, wardrobe" ],
    [ "Writing",          "writer, playwright, writing, script" ],
    [ "Production",       "producer, production" ],
    [ "Marketing",        "marketing, publicity, social media" ],
    [ "Front of House",   "front of house, foh, usher, box office" ],
    [ "Other",            "" ]
  ].freeze

  # Inline model so this migration doesn't depend on the app's Department class.
  class MigrationDepartment < ActiveRecord::Base
    self.table_name = "departments"
  end

  def up
    add_reference :opportunity_roles, :department, foreign_key: true, null: true

    department_id_by_category = DEFAULTS.each_with_index.to_h do |(name, terms), index|
      dept = MigrationDepartment.create!(name: name, match_terms: terms, ordering: index)
      [ index, dept.id ]
    end

    department_id_by_category.each do |category_value, department_id|
      execute("UPDATE opportunity_roles SET department_id = #{department_id} WHERE category = #{category_value}")
    end

    remove_column :opportunity_roles, :category
  end

  def down
    add_column :opportunity_roles, :category, :integer, default: 0, null: false
    remove_reference :opportunity_roles, :department
    MigrationDepartment.delete_all
  end
end
