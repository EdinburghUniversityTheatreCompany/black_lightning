require "test_helper"
require "#{Rails.root}/lib/tasks/logic/markdown_heading_fix"

# Tests the markdown:fix_heading_spaces task logic.
#
# The pure `fix_text` transform is the risky part (heading heuristic, fenced-code
# tracking, and trailing closing-sequence stripping), so it gets exhaustive unit
# coverage. `run` gets DB-backed tests to prove the dry-run/apply distinction, the
# update_columns write path, and that every print branch works.
class MarkdownHeadingFixTest < ActiveSupport::TestCase
  Logic = Tasks::Logic::MarkdownHeadingFix

  # --- fix_text: leading space insertion ----------------------------------

  test "inserts a space in a bare ATX heading missing one" do
    result, changes, skipped, glued = Logic.fix_text("##Description")

    assert_equal "## Description", result
    assert_equal 1, changes.size
    assert_equal({ line_no: 1, before: "##Description", after: "## Description" }, changes.first)
    assert_empty skipped
    assert_empty glued
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

  test "leaves cosmetic-only differences alone (they render identically)" do
    # extra spaces after the hashes, and trailing whitespace, render the same
    assert_empty Logic.fix_text("##   Foo").second
    assert_equal "### Set   ", Logic.fix_text("### Set   ").first
    assert_empty Logic.fix_text("### Set   ").second
  end

  test "allows up to three leading spaces but treats four as indented code" do
    assert_equal "   ## Indented three", Logic.fix_text("   ##Indented three").first

    result, changes, = Logic.fix_text("    ##Indented four")
    assert_equal "    ##Indented four", result, "four-space indent is a code block, leave it"
    assert_empty changes
  end

  test "does not touch seven or more hashes" do
    result, changes, skipped = Logic.fix_text("#######TooMany")

    assert_equal "#######TooMany", result
    assert_empty changes
    assert_empty skipped
  end

  test "treats a non-breaking space after the hashes as a missing space" do
    assert_equal "## Selected", Logic.fix_text("## Selected").first
  end

  # --- fix_text: loosened content rules -----------------------------------

  test "fixes headings that start with markdown emphasis, quotes or digits" do
    assert_equal "## **Synopsis**", Logic.fix_text("##**Synopsis**").first
    assert_equal "# “Well done”", Logic.fix_text("#“Well done”").first
    assert_equal "## 2017/18 Committee", Logic.fix_text("##2017/18 Committee").first
  end

  test "allows headings that end in a period" do
    assert_equal "###### The King.", Logic.fix_text("######The King.").first
  end

  test "skips only lines longer than the cap" do
    long = "##" + ("a" * 134)
    _result, changes, skipped = Logic.fix_text(long)
    assert_empty changes
    assert_equal 1, skipped.size
    assert_match(/too long/, skipped.first[:reason])

    ok = "##" + ("a" * 100)
    _r, changes2, = Logic.fix_text(ok)
    assert_equal 1, changes2.size
  end

  test "measures length on the cleaned content, not the raw hashes" do
    # trailing ## would push a 3-char heading over a tiny cap if counted raw
    _result, changes, skipped = Logic.fix_text("##Foo##", max_len: 3)
    assert_equal 1, changes.size, "content 'Foo' is 3 chars, within the cap"
    assert_empty skipped
  end

  # --- fix_text: fenced code ----------------------------------------------

  test "never touches lines inside a fenced code block" do
    input = "##Real\n\n```\n##not a heading\n### also code\n```\n\n##Also real"
    result, changes, = Logic.fix_text(input)

    assert_equal "## Real\n\n```\n##not a heading\n### also code\n```\n\n## Also real", result
    assert_equal [ 1, 8 ], changes.map { |c| c[:line_no] }
  end

  test "handles tilde fences too" do
    result, changes, = Logic.fix_text("~~~\n##code\n~~~\n##heading")
    assert_equal "~~~\n##code\n~~~\n## heading", result
    assert_equal 1, changes.size
    assert_equal 4, changes.first[:line_no]
  end

  # --- fix_text: trailing closing-sequence stripping ----------------------

  test "strips a trailing closing sequence of two or more hashes" do
    assert_equal "## Week 5", Logic.fix_text("##Week 5##").first
    assert_equal "### Overview:", Logic.fix_text("###Overview:###").first
    assert_equal "## Publicity Text", Logic.fix_text("## Publicity Text##").first
  end

  test "leaves a space-preceded closing sequence alone (CommonMark already strips it)" do
    # renders "Foo" as-is, so no rewrite — but if the line is touched for another
    # reason (here a missing leading space) the closer is cleaned up too.
    assert_empty Logic.fix_text("## Foo ##").second
    assert_equal "## Foo", Logic.fix_text("##Foo #").first
  end

  test "safe mode spares a single hash glued to the text (e.g. C#) and flags it" do
    # already a valid heading, only the glued # — must stay byte-for-byte identical
    result, changes, _skipped, glued = Logic.fix_text("## Programming in C#")
    assert_equal "## Programming in C#", result
    assert_empty changes
    assert_equal 1, glued.size
    assert_equal "## Programming in C#", glued.first[:text]
  end

  test "safe mode still fixes the leading space but leaves a glued single hash, flagging it" do
    result, changes, _skipped, glued = Logic.fix_text("#Tech#")
    assert_equal "# Tech#", result
    assert_equal 1, changes.size
    assert_equal 1, glued.size
  end

  test "strip_all removes even a single glued trailing hash" do
    assert_equal "# Tech", Logic.fix_text("#Tech#", strip_all: true).first
    result, _changes, _skipped, glued = Logic.fix_text("## Programming in C#", strip_all: true)
    assert_equal "## Programming in C", result
    assert_empty glued, "nothing left to flag once everything is stripped"
  end

  # --- fix_text: misc ------------------------------------------------------

  test "fixes multiple broken headings across a multi-line string" do
    input = "##One\n\nBody.\n\n###Two##\n\nMore\n\n####Three"
    result, changes, = Logic.fix_text(input)

    assert_equal "## One\n\nBody.\n\n### Two\n\nMore\n\n#### Three", result
    assert_equal 3, changes.size
  end

  test "ignores an empty heading" do
    assert_equal "##", Logic.fix_text("##").first
    assert_equal "## ", Logic.fix_text("## ").first
  end

  test "returns blank input unchanged with empty collections" do
    assert_equal [ nil, [], [], [] ], Logic.fix_text(nil)
    assert_equal [ "", [], [], [] ], Logic.fix_text("")
    assert_equal [ "   ", [], [], [] ], Logic.fix_text("   ")
  end

  # --- run: DB-backed dry-run / apply -------------------------------------

  test "dry-run reports changes but writes nothing" do
    opp = FactoryBot.create(:opportunity, description: "##Description\n\nBody")
    original = opp.updated_at

    capture_io { Logic.run(dry_run: true, only: "Opportunity") }

    assert_operator Logic.last_summary[:headings_fixed], :>=, 1
    assert_equal "##Description\n\nBody", opp.reload.description, "dry-run must not write"
    assert_equal original.to_i, opp.updated_at.to_i
  end

  test "apply writes the fix, strips a trailing sequence, and bumps updated_at" do
    opp = FactoryBot.create(:opportunity, description: "##Overview##\n\nBody")
    opp.update_columns(updated_at: 2.days.ago)
    stale = opp.reload.updated_at

    capture_io { Logic.run(dry_run: false, only: "Opportunity") }

    opp.reload
    assert_equal "## Overview\n\nBody", opp.description
    assert_operator opp.updated_at, :>, stale, "updated_at should be bumped to bust caches"
  end

  test "apply leaves records without broken headings alone" do
    opp = FactoryBot.create(:opportunity, description: "## Already fine")
    opp.update_columns(updated_at: 2.days.ago)
    stale = opp.reload.updated_at

    capture_io { Logic.run(dry_run: false, only: "Opportunity") }

    opp.reload
    assert_equal "## Already fine", opp.description
    assert_equal stale.to_i, opp.updated_at.to_i
  end

  test "run exercises the skip, glued and summary output branches" do
    long_line = "##" + ("z" * 200)
    FactoryBot.create(:opportunity, description: "#Tech#\n\n#{long_line}")

    out, = capture_io { Logic.run(dry_run: true, only: "Opportunity") }

    assert_match(/too long/, out)
    assert_match(/single '#'/, out)
    assert_match(/Summary/, out)
    assert_operator Logic.last_summary[:skipped], :>=, 1
    assert_operator Logic.last_summary[:glued], :>=, 1
  end
end
