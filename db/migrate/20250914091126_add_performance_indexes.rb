class AddPerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    # Critical missing foreign key indexes for User associations
    add_index :admin_maintenance_debts, :user_id, name: "index_admin_maintenance_debts_on_user_id" unless index_exists?(:admin_maintenance_debts, :user_id)
    add_index :admin_staffing_debts, :user_id, name: "index_admin_staffing_debts_on_user_id" unless index_exists?(:admin_staffing_debts, :user_id)
    add_index :maintenance_attendances, :maintenance_session_id, name: "index_maintenance_attendances_on_maintenance_session_id" unless index_exists?(:maintenance_attendances, :maintenance_session_id)
    add_index :membership_cards, :user_id, name: "index_membership_cards_on_user_id" unless index_exists?(:membership_cards, :user_id)

    # Date-based query optimizations for debt calculations (User model lines 204-216)
    add_index :admin_maintenance_debts, [ :due_by, :state ], name: "index_admin_maintenance_debts_on_due_by_and_state" unless index_exists?(:admin_maintenance_debts, [ :due_by, :state ])
    add_index :admin_staffing_debts, [ :due_by, :state ], name: "index_admin_staffing_debts_on_due_by_and_state" unless index_exists?(:admin_staffing_debts, [ :due_by, :state ])

    # Event date range queries (Event model lines 92-94, 114)
    add_index :events, [ :end_date, :is_public ], name: "index_events_on_end_date_and_is_public" unless index_exists?(:events, [ :end_date, :is_public ])
    add_index :events, [ :start_date, :end_date ], name: "index_events_on_date_range" unless index_exists?(:events, [ :start_date, :end_date ])

    # Team membership queries optimization (User model lines 253-259)
    add_index :team_members, [ :teamwork_type, :teamwork_id ], name: "index_team_members_on_teamwork_type_and_id" unless index_exists?(:team_members, [ :teamwork_type, :teamwork_id ])

    # Admin debt notifications query (User model line 248)
    add_index :admin_debt_notifications, :sent_on, name: "index_admin_debt_notifications_on_sent_on" unless index_exists?(:admin_debt_notifications, :sent_on)

    # Show/Event specific debt queries (Show model line 60)
    add_index :admin_maintenance_debts, [ :show_id, :converted_from_staffing_debt ], name: "index_admin_maintenance_debts_on_show_and_converted" unless index_exists?(:admin_maintenance_debts, [ :show_id, :converted_from_staffing_debt ])
    add_index :admin_staffing_debts, :show_id, name: "index_admin_staffing_debts_on_show_id" unless index_exists?(:admin_staffing_debts, :show_id)

    # Polymorphic association optimizations
    add_index :admin_staffing_jobs, [ :staffable_type, :staffable_id ], name: "index_admin_staffing_jobs_on_staffable" unless index_exists?(:admin_staffing_jobs, [ :staffable_type, :staffable_id ])

    # News slug lookups (News model line 97)
    add_index :news, :slug, name: "index_news_on_slug" unless index_exists?(:news, :slug)


    # Opportunity queries (Opportunity model line 28) - Skip if table doesn't exist
    if table_exists?(:opportunities)
      add_index :opportunities, [ :approved, :expiry_date ], name: "index_opportunities_on_approved_and_expiry" unless index_exists?(:opportunities, [ :approved, :expiry_date ])
    end
  end
end
