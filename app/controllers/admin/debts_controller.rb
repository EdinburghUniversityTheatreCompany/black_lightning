class Admin::DebtsController < AdminController

def index
  authorize! :manage, Admin::Debt

  @title = 'Users'

  @q     = User.unscoped.search(params[:q])
  @users = @q.result(distinct: true)
  @users = @users.with_role(:member)

  if params[:show_in_debt_only] == '1'
    @users = @users.in_debt
  end

  @users = @users.paginate(page: params[:page], per_page: 15)
  @users = @users.all

  respond_to do |format|
    format.html
    format.json { render json: @users }
  end
  end

  def show
    debt = Admin::Debt.new(params[:id].to_i)
    authorize! :read, debt
    @user = User.find(params[:id])

    prefix = (@user == current_user)? "You are ": "#{@user.name} is "

    @message = prefix+@user.debt_message_suffix

    @title = "Debt status for #{@user.name}"
  end

end
