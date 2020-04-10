class Admin::DebtsController < AdminController
  def index
    authorize! :manage, Admin::Debt

    @title = 'Users'

    @q     = User.unscoped.ransack(params[:q])
    @users = @q.result(distinct: true)
    @users = @users.with_role(:member)

    @users = @users.in_debt if params[:show_in_debt_only] == '1'

    @users = @users.paginate(page: params[:page], per_page: 15)
    @users = @users.all

    respond_to do |format|
      format.html
      format.json { render json: @users }
    end
  end

  def show
    authorize! :show, Admin::Debt

    debt = Admin::Debt.new(params[:id].to_i)
    authorize! :read, debt
    @user = User.find(params[:id])
    @title = "Debt Status for #{@user.name}"
  end
end
