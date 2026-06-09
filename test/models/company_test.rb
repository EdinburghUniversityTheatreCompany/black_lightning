require "test_helper"

class CompanyTest < ActiveSupport::TestCase
  test "requires a name" do
    company = Company.new(name: nil)
    assert_not company.valid?
    assert company.errors[:name].present?
  end

  test "name is unique case-insensitively" do
    duplicate = Company.new(name: "gutter theatre")
    assert_not duplicate.valid?
    assert duplicate.errors[:name].present?
  end

  test "generates a slug from the name" do
    company = Company.create!(name: "Brand New Society")
    assert_equal "brand-new-society", company.slug
  end

  test "internal_first orders internal companies before external ones" do
    ordered = Company.internal_first.to_a
    assert ordered.index(companies(:eutc)) < ordered.index(companies(:gutter_theatre))
  end

  test "defaults to external" do
    assert_not Company.new.internal
  end
end
