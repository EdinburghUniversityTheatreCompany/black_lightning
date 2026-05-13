class AddUniqueIndexToNewsletterSubscribersEmail < ActiveRecord::Migration[8.1]
  def change
    add_index :newsletter_subscribers, :email, unique: true, if_not_exists: true
  end
end
