require "test_helper"
require "#{Rails.root}/lib/tasks/logic/markdown_heading_fix"

# Tests the markdown:fix_heading_spaces task logic.
#
# The pure `fix_text` transform is the risky part (heading heuristic + fenced-code
# tracking), so it gets exhaustive unit coverage. `run` gets a couple of DB-backed
# tests to prove the dry-run/apply distinction and the update_columns write path.
class MarkdownHeadingFixTest < ActiveSupport::TestCase
  Logic = Tasks::Logic::MarkdownHeadingFix

  # --- fix_text: the pure transform ---------------------------------------

  test "inserts a space in a bare ATX heading missing one" do
    result, changes, skipped = Logic.fix_text("##Description")

    assert_equal "## Description", result
    assert_equal 1, changes.size
    assert_equal({ line_no: 1, before: "##Description", after: "## Description" }, changes.first)
    assert_empty skipped
  end

  test "handles every heading level 1 through 6" do
    (1..6).each do |level|
      hashes = "#" * level
      result, changes, = Logic.fix_text("#{hashes}Title")
      assert_equal "#{hashes} Title", result, "level #{level} should be fixed"
      assert_equal 1, changes.size
    end
  end

  test "leaves an already-correct heading untouched" do
    result, changes, skipped = Logic.fix_text("## Foo")

    assert_equal "## Foo", result
    assert_empty changes
    assert_empty skipped
  end

  test "allows up to three leading spaces but treats four as indented code" do
    result, changes, = Logic.fix_text("   ##Indented three")
    assert_equal "   ## Indented three", result
    assert_equal 1, changes.size

    result, changes, skipped = Logic.fix_text("    ##Indented four")
    assert_equal "    ##Indented four", result, "four-space indent is a code block, leave it"
    assert_empty changes
    assert_empty skipped
  end

  test "does not touch seven or more hashes" do
    result, changes, skipped = Logic.fix_text("#######TooMany")

    assert_equal "#######TooMany", result
    assert_empty changes
    assert_empty skipped
  end

  test "skips candidates whose text does not start with a letter" do
    [ "#1 rule of the show", "#!bang", "#-dash", "#(paren" ].each do |line|
      result, changes, skipped = Logic.fix_text(line)

      assert_equal line, result, "#{line.inspect} should be left alone"
      assert_empty changes
      assert_equal 1, skipped.size
      assert_match(/letter/, skipped.first[:reason])
    end
  end

  test "skips over-length headings as prose" do
    long = "##" + ("a" * 65)
    result, changes, skipped = Logic.fix_text(long)

    assert_equal long, result
    assert_empty changes
    assert_equal 1, skipped.size
    assert_match(/too long/, skipped.first[:reason])
  end

  test "respects a custom max_len" do
    _result, changes, skipped = Logic.fix_text("##Short heading", max_len: 3)
    assert_empty changes
    assert_match(/too long/, skipped.first[:reason])
  end

  test "skips headings that end in a sentence period" do
    line = "##This is really a sentence."
    result, changes, skipped = Logic.fix_text(line)

    assert_equal line, result
    assert_empty changes
    assert_match(/period/, skipped.first[:reason])
  end

  test "allows question and exclamation endings" do
    assert_equal "## Really?", Logic.fix_text("##Really?").first
    assert_equal "## Wow!", Logic.fix_text("##Wow!").first
  end

  test "never touches lines inside a fenced code block" do
    input = "##Real heading\n\n```\n##not a heading\n### also code\n```\n\n##Another real"
    result, changes, = Logic.fix_text(input)

    expected = "## Real heading\n\n```\n##not a heading\n### also code\n```\n\n## Another real"
    assert_equal expected, result
    assert_equal 2, changes.size
    assert_equal [ 1, 8 ], changes.map { |c| c[:line_no] }
  end

  test "handles tilde fences too" do
    input = "~~~\n##code\n~~~\n##heading"
    result, changes, = Logic.fix_text(input)

    assert_equal "~~~\n##code\n~~~\n## heading", result
    assert_equal 1, changes.size
    assert_equal 4, changes.first[:line_no]
  end

  test "fixes multiple broken headings across a multi-line string" do
    input = "##One\n\nSome body text.\n\n###Two\n\nMore text\n\n####Three"
    result, changes, = Logic.fix_text(input)

    assert_equal "## One\n\nSome body text.\n\n### Two\n\nMore text\n\n#### Three", result
    assert_equal 3, changes.size
  end

  test "preserves trailing content and blank lines exactly" do
    input = "##Heading with trailing spaces   \nbody\n"
    result, = Logic.fix_text(input)

    assert_equal "## Heading with trailing spaces   \nbody\n", result
  end

  test "returns blank input unchanged with no changes" do
    assert_equal [ nil, [], [] ], Logic.fix_text(nil)
    assert_equal [ "", [], [] ], Logic.fix_text("")
    assert_equal [ "   ", [], [] ], Logic.fix_text("   ")
  end

  # --- run: DB-backed dry-run / apply -------------------------------------

  test "dry-run reports changes but writes nothing" do
    opp = FactoryBot.create(:opportunity, description: "##Description\n\nBody")
    original_updated_at = opp.updated_at

    summary = capture_io { Logic.run(dry_run: true, only: "Opportunity") }.then { Logic.last_summary }

    assert_operator summary[:headings_fixed], :>=, 1
    assert_equal "##Description\n\nBody", opp.reload.description, "dry-run must not write"
    assert_equal original_updated_at.to_i, opp.updated_at.to_i
  end

  test "apply writes the fix and bumps updated_at" do
    opp = FactoryBot.create(:opportunity, description: "##Description\n\nBody")
    opp.update_columns(updated_at: 2.days.ago)
    stale = opp.reload.updated_at

    capture_io { Logic.run(dry_run: false, only: "Opportunity") }

    opp.reload
    assert_equal "## Description\n\nBody", opp.description
    assert_operator opp.updated_at, :>, stale, "updated_at should be bumped to bust caches"
  end

  test "apply leaves records without broken headings alone" do
    opp = FactoryBot.create(:opportunity, description: "## Already fine")
    opp.update_columns(updated_at: 2.days.ago)
    stale = opp.reload.updated_at

    capture_io { Logic.run(dry_run: false, only: "Opportunity") }

    opp.reload
    assert_equal "## Already fine", opp.description
    assert_equal stale.to_i, opp.updated_at.to_i, "untouched record keeps its updated_at"
  end
end
