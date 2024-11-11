class NormalizeEmailDomainsToEdAcUk < ActiveRecord::Migration[7.1]
  def change
    User.where(email: /^\s*s\d{7}@sms\.ed\.ac\.uk\s*$/).find_each do |user|
      user.update(email: user.email.gsub("@sms.ed.ac.uk", "@ed.ac.uk"))
    end
  end
end