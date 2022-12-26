class Admin::DebtsController < AdminController
  def index
    authorize! :index, Admin::Debt
    @title = 'All Debts'

    @q     = User.ransack(params[:q])
    @users = @q.result(distinct: true).with_role(:member)

    @users = @users.in_debt if params[:show_in_debt_only] == '1'

    @users = @users.page(params[:page]).per(15)

    respond_to do |format|
      format.html
      # TODO: This should include the debt stats and not actually the user info. Do something with a local class.
      format.json { render json: @users }
    end
  end

  def show
    debt = Admin::Debt.new(params[:id].to_i)

    authorize! :show, debt

    @user = User.find(params[:id])

    prefix = @user == current_user ? 'You are ' : "#{@user.name(current_user)} is "

    @message = prefix + @user.debt_message_suffix

    @title = "Debt status for #{@user.name(current_user)}"

    respond_to do |format|
      format.html
      # TODO: Same as above
      format.json { render json: @users }
    end
  end
end
