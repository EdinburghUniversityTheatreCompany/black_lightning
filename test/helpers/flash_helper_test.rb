require "test_helper"

class FlashHelperTest < ActionView::TestCase
  test "append to flash" do
    assert_nil flash[:error]

    append_to_flash(:error, "Pineapple")
    assert_equal flash[:error], [ "Pineapple" ]

    append_to_flash(:error, "Hexagon")
    assert_equal flash[:error], %w[Pineapple Hexagon]

    flash[:error] = "Viking"
    assert_equal flash[:error], "Viking"

    append_to_flash(:error, "Donkey")
    assert_equal flash[:error], %w[Viking Donkey]
  end


  test "merge flash notice and alert when error and success do not exist" do
    flash[:notice] = "Pineapple"
    flash[:alert] = "Hexagon"

    standardise_flash

    assert_nil flash[:notice]
    assert_nil flash[:alert]

    assert_equal [ "Pineapple" ], flash[:success]
    assert_equal [ "Hexagon" ], flash[:error]
  end

  # If this test fails, that might be because the flash hash no longer has the keys as symbols, but as strings.
  test "flash_as_alert_hash orders keys" do
    flash[:success] = [ "Donkey" ]
    flash[:info] = [ "Hexagon" ]
    flash[:error] = [ "Pineapple" ]
    flash[:warning] = [ "Viking" ]

    alert_hash = flash_as_alert_hash

    assert_equal %i[error info warning success], alert_hash.keys
  end

  test "flash_as_alert_hash converts messages to html" do
    flash[:error] = [ "Pineapple", "Hexagon" ]
    flash[:success] = [ "Donkey" ]

    alert_hash = flash_as_alert_hash

    assert_equal "<ul><li>Pineapple</li><li>Hexagon</li></ul>", alert_hash[:error]
    assert_equal "Donkey", alert_hash[:success]
  end
end
