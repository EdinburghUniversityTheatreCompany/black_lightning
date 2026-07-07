# Backfill fix for Markdown headings authored without the space after the `#`s
# (e.g. `##Description` -> `## Description`). Such lines are NOT headings under the
# CommonMark spec used by MdHelper#render_markdown, so they currently render as
# literal `##Description` text. See lib/tasks/markdown.rake for the runnable task.
class Tasks::Logic::MarkdownHeadingFix
  # Cap on heading-text length: prose lines are long, real headings are short.
  MAX_HEADING_LEN = 64

  # Line-start ATX heading with the space missing: 0-3 leading spaces, 1-6 `#`,
  # then a non-space non-`#` char. 4+ spaces is indented code; 7+ `#` is never a
  # heading — both fail to match and are left alone. `\#` is escaped to avoid `#{`
  # being read as string interpolation.
  HEADING_RE = /\A( {0,3})(\#{1,6})([^\s#].*)\z/

  # Every Markdown-authored column in the app, keyed by model name. Kept as strings
  # so the file can be required outside a fully-booted autoload context.
  #
  # CarouselItem#tagline is intentionally absent: it is authored in the Markdown
  # editor but rendered as PLAIN text, so a fix there would change the literal string
  # users see rather than repair a heading (see plans/off-topic-improvements.md).
  TARGETS = {
    "FaultReport" => [ :description ],
    "PictureTag" => [ :description ],
    "MassMail" => [ :body ],
    "Complaint" => [ :description, :comments ],
    "MarketingCreatives::CategoryInfo" => [ :description ],
    "MarketingCreatives::Profile" => [ :about, :contact ],
    "Admin::Feedback" => [ :body ],
    "EventTag" => [ :description ],
    "Review" => [ :body ],
    "Admin::Proposals::Proposal" => [ :publicity_text, :proposal_text ],
    "Venue" => [ :address, :description ],
    "News" => [ :body ],
    "Opportunity" => [ :description ],
    "Admin::EditableBlock" => [ :content ],
    "AttachmentTag" => [ :description ],
    "User" => [ :bio ],
    "Event" => [ :publicity_text, :content_warnings, :members_only_text ],
    "Admin::Answer" => [ :answer ],
    "Admin::Question" => [ :question_text ]
  }.freeze

  class << self
    # Summary of the most recent `run`, for callers/tests that need the counts.
    attr_reader :last_summary

    # Pure transform. Returns [new_string, changes, skipped] where:
    #   changes = [{ line_no:, before:, after: }]  (lines a space was inserted into)
    #   skipped = [{ line_no:, text:, reason: }]   (heading-shaped lines left alone, for review)
    # No database access — this is the unit-tested core.
    def fix_text(str, max_len: MAX_HEADING_LEN)
      return [ str, [], [] ] if str.blank?

      changes = []
      skipped = []
      in_fence = false
      fence_char = nil

      # split("\n", -1) keeps trailing empty fields so join round-trips exactly.
      new_lines = str.split("\n", -1).each_with_index.map do |line, idx|
        if (fence = line.match(/\A {0,3}(`{3,}|~{3,})/))
          char = fence[1][0]
          if in_fence
            in_fence = false if char == fence_char
          else
            in_fence = true
            fence_char = char
          end
          next line
        end

        next line if in_fence

        m = line.match(HEADING_RE)
        next line unless m

        leading, hashes, rest = m[1], m[2], m[3]
        if (reason = skip_reason(rest, max_len))
          skipped << { line_no: idx + 1, text: line, reason: reason }
          next line
        end

        fixed = "#{leading}#{hashes} #{rest}"
        changes << { line_no: idx + 1, before: line, after: fixed }
        fixed
      end

      [ new_lines.join("\n"), changes, skipped ]
    end

    # :nocov:
    # Iterate the target columns, print what would change, and (unless dry_run) write it.
    def run(dry_run: true, only: nil, max_len: MAX_HEADING_LEN)
      targets = only ? TARGETS.slice(only) : TARGETS
      warn "No target model named #{only.inspect}." if only && targets.empty?

      scanned = 0
      records_changed = 0
      columns_changed = 0
      headings_fixed = 0
      skipped_total = 0

      targets.each do |model_name, columns|
        klass = model_name.constantize
        has_updated_at = klass.column_names.include?("updated_at")

        klass.find_each do |record|
          scanned += 1
          record_touched = false

          columns.each do |col|
            value = record.public_send(col)
            next if value.blank?

            fixed, changes, skipped = fix_text(value, max_len: max_len)

            if changes.any?
              columns_changed += 1
              headings_fixed += changes.size
              record_touched = true
              print_changes(model_name, record.id, col, changes)

              unless dry_run
                attrs = { col => fixed }
                attrs[:updated_at] = Time.current if has_updated_at
                record.update_columns(attrs)
              end
            end

            if skipped.any?
              skipped_total += skipped.size
              print_skipped(model_name, record.id, col, skipped)
            end
          end

          records_changed += 1 if record_touched
        end
      end

      @last_summary = {
        dry_run: dry_run,
        scanned: scanned,
        records_changed: records_changed,
        columns_changed: columns_changed,
        headings_fixed: headings_fixed,
        skipped: skipped_total
      }
      print_summary(@last_summary)
      @last_summary
    end

    private

    def skip_reason(rest, max_len)
      text = rest.strip
      return "starts with a non-letter" unless text.match?(/\A[[:alpha:]]/)
      return "too long (#{text.length} > #{max_len} chars)" if text.length > max_len
      return "ends with a period" if text.end_with?(".")

      nil
    end

    def print_changes(model_name, id, col, changes)
      puts "#{model_name}##{id}.#{col}"
      changes.each do |c|
        puts "  L#{c[:line_no]}  - #{c[:before]}"
        puts "  L#{c[:line_no]}  + #{c[:after]}"
      end
    end

    def print_skipped(model_name, id, col, skipped)
      puts "#{model_name}##{id}.#{col}  skipped (review by hand):"
      skipped.each do |s|
        puts "  L#{s[:line_no]}  #{s[:text]}   (#{s[:reason]})"
      end
    end

    def print_summary(summary)
      puts
      puts "== Summary (#{summary[:dry_run] ? 'DRY RUN' : 'APPLIED'}) =="
      puts "  records scanned:  #{summary[:scanned]}"
      puts "  records changed:  #{summary[:records_changed]}"
      puts "  columns changed:  #{summary[:columns_changed]}"
      puts "  headings fixed:   #{summary[:headings_fixed]}"
      puts "  candidates skipped: #{summary[:skipped]}"
    end
    # :nocov:
  end
end
