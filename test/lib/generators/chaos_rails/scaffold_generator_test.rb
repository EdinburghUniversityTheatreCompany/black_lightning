require 'test_helper'
require 'generators/chaos_rails/scaffold/scaffold_generator'

class ChaosRails::ScaffoldGeneratorTest < Rails::Generators::TestCase
  tests ChaosRails::ScaffoldGenerator
  destination Rails.root.join('tmp/generators')
  setup :prepare_destination

  test 'generator runs without errors' do
    assert_nothing_raised do
      run_generator ['Test::Scaffold', ['name:string']]
    end
  end
end
