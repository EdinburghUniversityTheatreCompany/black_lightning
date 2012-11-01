desc "Converts a proposal to a show"
task :convert_proposal_to_show, [:proposal_id] => :environment do |t, args|
  proposal_id = args.proposal_id
  
  puts "Converting proposal #{proposal_id} "
  
  @proposal = Admin::Proposals::Proposal.find(proposal_id)
  
  puts @proposal.show_title
  
  @show = Show.new()
  @show.name = @proposal.show_title
  @show.description = @proposal.publicity_text
  
  @show.slug = @show.name.gsub(/\s+/,'-').gsub(/[^a-zA-Z0-9\-]/,'').downcase.gsub(/\-{2,}/,'-')
  
  @proposal.successful = true
  
  if not @show.save then
    @show.errors.full_messages.each do |error|
      puts error
    end
    abort("Couldn't save the new show")
  end
  
  if not @proposal.save then
    puts "Couldn't set the 'successful' flag on the proposal. This will need to be done manually"
  end
  
  puts "Created Show:"
  puts "Name: #{@show.name}"
  puts "Slug: #{@show.slug}"
end