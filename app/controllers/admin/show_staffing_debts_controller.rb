class Admin::ShowStaffingDebtsController < AdminController
  def create
    authorize!(:create , Admin::StaffingDebt)
    show = Show.find(params[:format])
    show.create_sdebts(params[:number_of_slots_due][0].to_i)

    redirect_to admin_show_url(show), notice: 'Obligations created.'
  end

  def update
    #left in case it becomes desirable to modify all of a shows debts due dates post creation
  end
end
