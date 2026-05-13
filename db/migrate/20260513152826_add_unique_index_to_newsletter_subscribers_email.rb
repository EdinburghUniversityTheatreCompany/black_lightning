class AddUniqueIndexToNewsletterSubscribersEmail < ActiveRecord::Migration[8.1]
  def change
    # Remove duplicate emails, keeping the most recently created record
    execute <<~SQL
      DELETE ns1 FROM newsletter_subscribers ns1
      INNER JOIN newsletter_subscribers ns2
      WHERE ns1.id < ns2.id AND ns1.email = ns2.email
    SQL

    add_index :newsletter_subscribers, :email, unique: true, if_not_exists: true
  end
end
