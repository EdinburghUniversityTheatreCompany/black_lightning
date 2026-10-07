require "application_system_test_case"

# nested-form names each inserted row by Date.getTime(). Two rows added within
# one clock tick share a key, and Rails then keeps only one of them. A browser
# that coarsens its clock (Firefox's resistFingerprinting rounds to 100ms) makes
# that tick long, so this test rounds to 50ms.
class Admin::TemplateLoaderRowKeysTest < ApplicationSystemTestCase
  COARSE_CLOCK = <<~JS
    (() => {
      const RealDate = Date
      const coarse = () => Math.floor(RealDate.now() / 50) * 50
      window.Date = class extends RealDate {
        constructor(...args) { args.length ? super(...args) : super(coarse()) }
        static now() { return coarse() }
      }
    })()
  JS

  setup do
    login_as users(:admin)
  end

  test "loading a template gives every row its own nested-attributes key" do
    page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: COARSE_CLOCK)
    template = FactoryBot.create(:staffing_template, job_count: 0)
    8.times { |i| FactoryBot.create(:unstaffed_staffing_job, staffable: template, name: "Job #{i}") }

    visit new_admin_staffing_path
    find("button[data-action=\"click->template-loader#open\"]").click
    within "#template_modal" do
      assert_selector "select option", text: template.name, wait: 5
      select template.name, from: "template_list"
      find("#template_load").click
    end

    assert_selector ".nested-fields [name$='[name]']", count: 8, wait: 15
    names = all(".nested-fields [name$='[name]']").map { |input| input[:name] }
    assert_equal names.uniq, names
  end
end
