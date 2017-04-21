class Admin::DebtsController < AdminController

def index
  authorize! :manage, Admin::Debt

  @title = 'Users'

  @q     = User.unscoped.search(params[:q])
  @users = @q.result(distinct: true)

  if params[:show_non_members] != '1'
    @users = @users.with_role(:member)
  end

  @users = @users.paginate(page: params[:page], per_page: 15)
  @users = @users.all

  respond_to do |format|
    format.html
    format.json { render json: @users }
  end
  end

  def show
    debt = Admin::Debt.new(params[:id])
    authorize! :read, Admin::Debt
    @user = User.find(params[:id])
    authorize! :read , debt if (current_user != @user)
    @title = 'Debt status'
  end

end
