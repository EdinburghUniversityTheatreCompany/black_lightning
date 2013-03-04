
worker_processes 2
preload_app true
timeout 30

pid "/srv/bedlamtheatre.co.uk/misc/unicorn.pid"

after_fork do |server, worker|
	ActiveRecord::Base.establish_connection
end
