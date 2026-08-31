class AddNotificationRoleToReimbursementsCostCentres < ActiveRecord::Migration[8.1]
  # Who gets this cost centre's operator reminders (the nightly's stale-pending
  # and ready-to-batch emails).
  #
  # Until now there was one global list: every user holding the
  # `manage`/`reimbursements_finance` grid permission. That is fine while Fringe
  # (F40) is the only live centre and wrong the moment termtime (BED) joins it,
  # since every Fringe admin would get termtime's reminders and vice versa. The
  # permission still gates the finance SCREENS globally — only who gets TOLD
  # becomes per centre.
  #
  # A Role rather than a join table or an address column: roles are the
  # committee-membership machinery this society already runs on, so a handover is
  # the same gesture as every other handover, and the members are real accounts
  # that cannot rot into someone who has left. These finance roles are
  # deliberately NOT part of the annual Role#archive sweep.
  #
  # roles.id is a legacy INTEGER primary key, not a bigint. A default bigint
  # reference aborts the FK migration with a column-type mismatch. The FK itself
  # is added in the next migration per the multi-step convention
  # strong_migrations asks for.
  def up
    add_reference :reimbursements_cost_centres, :notification_role,
                  type: :integer, null: true, index: true

    # Raw SQL rather than the models, as the eusa_actuals cost-centre backfill
    # does: a migration that calls Role or CostCentre breaks the day either
    # class changes, and going through the models here would also have to dodge
    # the presence validation the next commit adds.
    #
    # Production already has this role (id 59) with its members chosen by hand,
    # so find it rather than seeding it, and add NOBODY to it — inventing
    # members from the permission grid would email people who were not chosen.
    # On a developer's migrated database the name does not exist yet, so it is
    # created empty; that centre then trips the empty-role warning until someone
    # fills it in, which is the intended signal rather than a silent default.
    #
    # safety_assured: strong_migrations cannot inspect an execute, so it refuses
    # to judge it. What is inside is one INSERT of a single row into roles and
    # one UPDATE of reimbursements_cost_centres, which holds a single row in
    # production — neither takes a lock worth worrying about.
    safety_assured do
      role_id = select_value("SELECT id FROM roles WHERE name = 'Fringe Finance Admin' LIMIT 1")
      if role_id.nil?
        execute(<<~SQL.squish)
          INSERT INTO roles (name, created_at, updated_at)
          VALUES ('Fringe Finance Admin', NOW(), NOW())
        SQL
        role_id = select_value("SELECT id FROM roles WHERE name = 'Fringe Finance Admin' LIMIT 1")
      end

      update("UPDATE reimbursements_cost_centres SET notification_role_id = #{role_id.to_i} " \
             "WHERE notification_role_id IS NULL")
    end
  end

  def down
    remove_reference :reimbursements_cost_centres, :notification_role
  end
end
