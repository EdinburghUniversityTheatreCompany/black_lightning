namespace :staffing do
  task :fix_bedfest => :environment do
    Admin::Staffing.where(show_title: "Bedlam Festival 2013").each do |s|
      s.end_time = case
      when s.start_time.hour == 10
        DateTime.civil(s.start_time.year, s.start_time.month, s.start_time.day, 14, 15)
      when s.start_time.hour == 14
        DateTime.civil(s.start_time.year, s.start_time.month, s.start_time.day, 17, 45)
      when s.start_time.hour == 17
        DateTime.civil(s.start_time.year, s.start_time.month, s.start_time.day, 21, 45)
      when s.start_time.hour == 21
        DateTime.civil(s.start_time.year, s.start_time.month, s.start_time.day + 1, 0, 0)
      end
      s.save
    end
  end
end
