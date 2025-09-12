class Admin::TestsController < AdminController
    def index
        authorize! :index, :tests
    end

    def test_alerts
        authorize! :alerts, :tests

        if params[:type] == "error" || params[:type] == "all"
            helpers.append_to_flash(:error, "This is an error message.")
            helpers.append_to_flash(:error, "This is another error message.")
            helpers.append_to_flash(:alert, "This is an alert message that should be added to the errors")
        end

        if params[:type] == "success" || params[:type] == "all"
            helpers.append_to_flash(:success, "This is a success message.")
            helpers.append_to_flash(:success, "This is another success message")
            helpers.append_to_flash(:notice, "This is a notice message that should be added to the success messages.")
        end

        if params[:type] == "warning" || params[:type] == "all"
            helpers.append_to_flash(:warning, "This is a warning message.")
            helpers.append_to_flash(:warning, "This is another warning message.")
        end

        if params[:type] == "info" || params[:type] == "all"
            helpers.append_to_flash(:info, "This is an info message.")
            helpers.append_to_flash(:info, "This is another info message.")
        end

        redirect_to admin_tests_path
    end

    def test_404
        authorize! 404, :tests

        raise ActiveRecord::RecordNotFound.new("This is a test not found error.")
    end

    def test_500
        authorize! 500, :tests

        flash[:error] = "This is a bonus error."
        flash[:success] = "This is a bonus success."

        raise ArgumentError.new("This is a test server error.")
    end

    def test_access_denied
        authorize! :access_denied, :tests
    end
end
