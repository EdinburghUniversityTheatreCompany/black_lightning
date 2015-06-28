require 'net/ldap'

class LDAPMigration
  def initialize(ldap_params)
    @conn = Net::LDAP.new(ldap_params)
    @fields = {}
    load_all_usernames!
  end

  def filters
    [
      :user_fields,
      :sanitize_name,
      :generate_username,
      :set_name,
      :set_contacts,
      :dump
     ]
  end

  def user_fields(user, remote)
    @fields[user.id] = {}

    return user, remote
  end

  def sanitize_name(user, remote)
    user.first_name = (user.first_name || '').strip.titleize.gsub(/ - /, '-').gsub('  ', ' ')
    user.last_name  = (user.last_name  || '').strip.titleize.gsub(/ - /, '-').gsub('  ', ' ')

    user.first_name = 'Unknown' if user.first_name.blank?
    user.last_name  = 'Unknown' if user.last_name.blank?

    return user, remote
  end

  def fetch_by_email(email)
    filter = Net::LDAP::Filter.eq(:mail, email)
    result = @conn.search(filter: filter, return_result: true)

    result.first if result
  end

  def generate_username(user, remote)
    username = I18n.transliterate(user.name)
    username = username.downcase.gsub(/[^a-z' ]/, '').gsub(' ', '.')

    if remote
      # Remote user already has a username
      @fields[user.id][:username] = remote[:uid].first
      @fields[user.id][:action] = :modify
    else
      # Try appending a number
      c = 0
      t = username

      while @usernames.include? t
        c += 1
        t = "#{username}#{c}"
      end

      username = t
      @usernames << username
      @fields[user.id][:username] = username
      @fields[user.id][:action] = :create
    end

    return user, remote
  end

  def set_name(user, remote)
    @fields[user.id][:first]    = user.first_name
    @fields[user.id][:last]     = user.last_name
    @fields[user.id][:cn]       = user.name
    @fields[user.id][:gecos]    = user.name
    @fields[user.id][:initials] = user.name.split(/\W/).map { |w| w[0] }.join.upcase

    return user, remote
  end

  def set_contacts(user, remote)
    @fields[user.id][:phone] = user.phone_number if user.phone_number
    @fields[user.id][:email] = user.email if user.email

    return user, remote
  end

  def dump(user, remote)
    fields = @fields[user.id]
    action = fields[:action]
    username = fields[:username]

    fields = fields \
      .except(:action, :username)
      .map { |k, v| "--#{k}=\"#{v}\"" }
      .join(' ')

    action = case action
             when :create then 'user-add'
             when :modify then 'user-mod'
             else nil
             end

    if action
      command = "ipa #{action} #{username} #{fields}"

      if action == 'user-add'
        command += " --noprivate --random | grep -E 'Random password|User login' | sed -e 's/^.*: //' | tr '\\n' ':' >> ~/temporary_passwords"
      end

      puts command

    else
      puts "# No action specified for id=#{user.id}"
    end

    return user, remote
  end

  private

  def load_all_usernames!
    result = @conn.search(return_result: true)

    @usernames = result.map { |e| e[:uid].first }.compact
  end
end
