namespace :import do
  task :shows => :environment do
    Rails.logger = Logger.new("#{Rails.root}/log/import.log")
    Rails.logger.level = Logger::DEBUG

    shows_uri = "http://old.bedlamtheatre.co.uk/shows.xml"
    show_uri = "http://old.bedlamtheatre.co.uk/shows/p"

    uri = URI.parse(shows_uri)

    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)
    xml_data = response.body

    doc = Nokogiri::XML(xml_data)

    Rails.logger.info "Collecting show ids"

    shows = {}
    doc.xpath('/search/results/Production/id').each do |element|
      show_id = element.text
      shows[show_id] = {}
    end

    shows.each do |id, details|
      Rails.logger.info "------"
      Rails.logger.info "Collecting data for show #{id}"

      uri = URI.parse(show_uri + id + '.xml')

      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(request)
      xml_data = response.body

      doc = Nokogiri::XML(xml_data)

      # Find the "Production" element, and read data.
      doc.xpath('/Production').each do |element|
        begin
          title = element.children.search('title').first.text

          begin
            blurb = element.children.search('blurb').first.text
          rescue
            blurb = ""
          end

          begin
            description = element.children.search('description').first.text
          rescue
            description = "No description available"
          end

          start_date  = Time.at(element.children.search('start').first.text.to_i).to_date
          finish_date = Time.at(element.children.search('finish').first.text.to_i).to_date

          Rails.logger.info "Start Date: #{start_date}"
          if start_date.year == 1970
            Rails.logger.info "  Using season date instead"

            start_date = Date.parse(element.children.search('Season/start').first.text)
            finish_date = Date.parse(element.children.search('Season/finish').first.text)
            Rails.logger.info "  Start Date: #{start_date}"
          end

          details = {
                      name:         title,
                      tagline:      blurb,
                      description:  description,
                      start_date:   start_date,
                      end_date:     finish_date,
                      team_members: []
                    }

          # Add team member details:
          element.children.search('role').each do |role_element|
            user_full_name = role_element.children.search('Agent/name').text
            position = role_element.children.search('position/displayname').text

            user = find_or_create_user_by_full_name(user_full_name)
            details[:team_members] << TeamMember.new(user_id: user.id, position: position)
          end

          element.children.search('Portrayal').each do |role_element|
            user_full_name = role_element.children.search('Agent/name').first.text
            position = role_element.children.search('Agent/name').last.text

            user = find_or_create_user_by_full_name(user_full_name)
            details[:team_members] << TeamMember.new(user_id: user.id, position: position)
          end

          show = Show.new(details)
          show.slug = show.name.gsub(/\s+/,'-').gsub(/[^a-zA-Z0-9\-]/,'').downcase.gsub(/\-{2,}/,'-') + "-#{show.start_date.year}"
          show.is_public = true

          show.save!

          Rails.logger.info "Imported #{details[:name]}"
        rescue => e
          Rails.logger.error "Couldn't import #{details[:name]}"
          Rails.logger.error e.message
        end
      end

      Rails.logger.info "Sleeping for 2 seconds."

      sleep(2)
    end

    Rails.logger.info "--------------------------"
    Rails.logger.info "Finished Importing Data."
  end

  def find_or_create_user_by_full_name(name)
    Rails.logger.info "Finding user #{name}"

    user_broken = name.split(" ")

    if user_broken.count == 2 then
      user_first_name = user_broken[0]
      user_last_name = user_broken[1]

      user = User.where({ first_name: user_first_name, last_name: user_last_name }).first
    elsif user_broken.count == 1 then
      user_first_name = user_broken[0]
    else
      # Guess what the user's name really is.
      Rails.logger.warn "  WARNING: User's name may have been incorrectly parsed"

      user_first_name = user_broken[0]
      user_last_name = user_broken[1] + " " + user_broken[2]

      user = User.where({ first_name: user_first_name, last_name: user_last_name }).first
    end

    if user.nil?
      Rails.logger.info "  User #{name} not found. Creating..."

      user = User.create_user(first_name: user_first_name, last_name: user_last_name, email: "unknown_#{SecureRandom.hex(8)}@bedlamtheatre.co.uk")
      user.save!
    end

    return user
  end
end