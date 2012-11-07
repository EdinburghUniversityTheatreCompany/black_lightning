class Admin::Proposals::Proposal < ActiveRecord::Base
  belongs_to :call, :class_name => "Admin::Proposals::Call"
  
  has_many :questions, :through => :answers
  has_many :answers, :class_name => "Admin::Proposals::Answer"
  has_many :team_members
  has_many :users, :through => :team_members
  
  accepts_nested_attributes_for :answers, :team_members
  
  validates :show_title, :proposal_text, :publicity_text, :presence => true
  validates :team_members, :presence => { :message => "You must add at least one team member" }
  
  ################################################################################
  # NOTE                                                                         #
  #                                                                              #
  # If a proposal has the approved attribute set to false, it has been REJECTED. #
  # A proposal still waiting for approval should have approved set to NULL       #
  ################################################################################
  
  attr_accessible :proposal_text, :publicity_text, :show_title, :answers, :answers_attributes, :team_members, :team_members_attributes, :late, :approved, :successful
  
  def convert_to_show
    puts self.show_title
    
    if not self.approved == true then
      abort("This proposal has not been approved")
    end
    
    @show = Show.new()
    @show.name = self.show_title
    @show.description = self.publicity_text
    
    @show.slug = @show.name.gsub(/\s+/,'-').gsub(/[^a-zA-Z0-9\-]/,'').downcase.gsub(/\-{2,}/,'-')
     
    self.successful = true
      
    if not @show.save then
      @show.errors.full_messages.each do |error|
        puts error
      end
      abort("Couldn't save the new show")
    end
      
    if not self.save then
      puts "Couldn't set the 'successful' flag on the proposal. This will need to be done manually"
    end
      
    puts "Created Show:"
    puts "Name: #{@show.name}"
    puts "Slug: #{@show.slug}"
  end
  handle_asynchronously :convert_to_show
end
