class Admin::DebtsController < AdminController
  # Debts permissions are a bit weird, because in the cancancan ability file everyone is allowed to read their own debt page.
  # This means can? :read, Admin::Debt will be true, even if someone cannot read all debt.
  # Thus, :manage is used to define if someone can access the index. Both here and on the admin layout page.

  def index
    authorize! :manage, Admin::Debt

    @title = 'Users'

    @q     = User.unscoped.ransack(params[:q])
    @users = @q.result(distinct: true).with_role(:member)

    @users = @users.in_debt if params[:show_in_debt_only] == '1'

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
    @title = "Debt Status for #{@user.name}"
  end
end
