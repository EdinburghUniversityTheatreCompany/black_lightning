require "test_helper"
require "generators/chaos_rails/fixtures/fixtures_generator"

class ChaosRails::FixturesGeneratorTest < Rails::Generators::TestCase
  tests ChaosRails::FixturesGenerator
  destination Rails.root.join('tmp/generators')
  setup :prepare_destination

  test 'generator runs without errors' do
    assert_nothing_raised do
      run_generator ['Test::Fixtures', ['code:int', 'name:string']]
    end
  end
end
