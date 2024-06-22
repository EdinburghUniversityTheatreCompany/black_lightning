# This controller is only used in development and local. Not in production.
class TestsController < ApplicationController
    def test_500
        flash[:error] = 'This is a bonus error.'
        flash[:success] = 'This is a bonus success.'

        raise ArgumentError.new('This is a test server error.')
    end
end
