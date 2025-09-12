class ChaosRails::FixturesGenerator < Rails::Generators::NamedBase
  source_root File.expand_path("templates", __dir__)

  argument :attributes, type: :array, default: [], banner: "field[:type][:index] field[:type][:index]"

  def create_fixture
    template "fixture.yml", File.join("test/fixtures", "#{class_name.underscore.pluralize}.yml")
  end
end
