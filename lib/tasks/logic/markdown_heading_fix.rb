# Backfill fix for Markdown headings authored without the space after the `#`s
# (e.g. `##Description` -> `## Description`) and/or with a decorative closing
# sequence of `#`s (e.g. `## Week 5##` -> `## Week 5`). Under the CommonMark spec
# used by MdHelper#render_markdown, `##Description` is not a heading at all (it
# renders as literal text), and a closing `##` not preceded by a space renders
# literally too. See lib/tasks/markdown.rake for the runnable task.
class Tasks::Logic::MarkdownHeadingFix
  # Cap on cleaned heading-text length: guards against turning a long paragraph
  # that merely starts with `#` into a heading. Overridable per-run.
  MAX_HEADING_LEN = 133

  # A fenced code block opener/closer: up to 3 leading spaces then 3+ ` or ~.
  FENCE_RE = /\A {0,3}(`{3,}|~{3,})/
  # Line-start ATX heading: 0-3 leading spaces, 1-6 `#`, then anything NOT a 7th
  # `#`. 4+ spaces is indented code and 7+ `#` is never a heading — both fail to
  # match. `\#` is escaped so `#{` is not read as string interpolation.
  HEADING_RE = /\A( {0,3})(\#{1,6})(?!#)(.*)\z/
  # The gap between the hashes and the title — a normal space, tab, or the
  # non-breaking space that some pasted content uses (which CommonMark does NOT
  # accept as the heading space, so it must be normalised too).
  LEAD_GAP = /\A[ \t ]+/
  # How to strip a closing sequence once we've decided a line needs changing.
  # Safe: `#`s preceded by whitespace (CommonMark's own rule) or a run of 2+.
  # Aggressive (strip_all): any trailing run, including a single glued `#`.
  TRAILING_SAFE = /(?:[ \t]+#+|\#{2,})[ \t]*\z/
  TRAILING_ALL = /[ \t]*#+[ \t]*\z/
  # Whether a line's tail renders a closing `#` LITERALLY (glued, no space before
  # it) and so is worth fixing. Space-preceded closers render clean already, and a
  # lone glued `#` (safe mode) is spared to protect words like `C#`/`F#`.
  TRAILING_BAD_SAFE = /(?:[^ \t#]|\A)\#{2,}[ \t]*\z/
  TRAILING_BAD_ALL = /(?:[^ \t#]|\A)#+[ \t]*\z/

  # Every Markdown-authored column in the app, keyed by model name. Kept as
  # strings so the file can be required outside a fully-booted autoload context.
  #
  # CarouselItem#tagline is intentionally absent: it is authored in the Markdown
  # editor but rendered as PLAIN text, so a fix there would change the literal
  # string users see rather than repair a heading (see plans/off-topic-improvements.md).
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

    # Pure transform. Returns [new_string, changes, skipped, glued] where:
    #   changes = [{ line_no:, before:, after: }]  (a space inserted / tail trimmed)
    #   skipped = [{ line_no:, text:, reason: }]   (heading-shaped but over the cap)
    #   glued   = [{ line_no:, text: }]            (heading left ending in a lone `#`,
    #                                               e.g. `C#` — spared in safe mode)
    # No database access — this is the unit-tested core.
    def fix_text(str, max_len: MAX_HEADING_LEN, strip_all: false)
      return [ str, [], [], [] ] if str.blank?

      changes = []
      skipped = []
      glued = []
      in_fence = false
      fence_char = nil

      # split("\n", -1) keeps trailing empty fields so join round-trips exactly.
      new_lines = str.split("\n", -1).each_with_index.map do |line, idx|
        if (fence = line.match(FENCE_RE))
          char = fence[1][0]
          fence_char, in_fence = toggle_fence(in_fence, fence_char, char)
          next line
        end
        next line if in_fence

        res = classify_heading(line, max_len, strip_all)
        next line unless res

        record(res, idx + 1, line, changes, skipped, glued)
      end

      [ new_lines.join("\n"), changes, skipped, glued ]
    end

    # :nocov:
    # Iterate the target columns, print what would change, and (unless dry_run) write it.
    def run(dry_run: true, only: nil, max_len: MAX_HEADING_LEN, strip_all: false)
      targets = only ? TARGETS.slice(only) : TARGETS
      warn "No target model named #{only.inspect}." if only && targets.empty?

      counts = Hash.new(0)
      glued_all = []

      targets.each do |model_name, columns|
        klass = model_name.constantize
        has_updated_at = klass.column_names.include?("updated_at")

        klass.find_each do |record|
          counts[:scanned] += 1
          scan_record(record, model_name, columns, max_len, strip_all, dry_run, has_updated_at, counts, glued_all)
        end
      end

      print_glued(glued_all)
      @last_summary = counts.merge(dry_run: dry_run, glued: glued_all.size)
      print_summary(@last_summary)
      @last_summary
    end
    # :nocov:

    private

    def toggle_fence(in_fence, fence_char, char)
      if in_fence
        char == fence_char ? [ nil, false ] : [ fence_char, true ]
      else
        [ char, true ]
      end
    end

    # Returns nil (not a heading) or a hash describing what to do with the line.
    def classify_heading(line, max_len, strip_all)
      cr = line.end_with?("\r") ? "\r" : ""
      body = cr.empty? ? line : line[0...-1]
      m = body.match(HEADING_RE)
      return nil unless m

      tail = m[3]
      content = tail.sub(LEAD_GAP, "").sub(strip_all ? TRAILING_ALL : TRAILING_SAFE, "").strip
      return nil if content.empty?

      glued = content.end_with?("#")
      # Only rewrite lines that actually render wrong: a missing/non-ASCII leading
      # gap, or a literal (glued) trailing `#`. Cosmetic-only differences (trailing
      # whitespace, a space-preceded closer) render fine and are left as-is.
      leading_ok = tail.start_with?(" ", "\t")
      trailing_bad = tail.match?(strip_all ? TRAILING_BAD_ALL : TRAILING_BAD_SAFE)
      return { type: :clean, glued: glued } if leading_ok && !trailing_bad
      return { type: :skip, reason: "too long (#{content.length} > #{max_len} chars)" } if content.length > max_len

      new_line = "#{m[1]}#{m[2]} #{content}#{cr}"
      new_line == line ? { type: :clean, glued: glued } : { type: :fix, after: new_line, glued: glued }
    end

    # Records a classification into the collections and returns the line to emit.
    def record(res, line_no, line, changes, skipped, glued)
      case res[:type]
      when :fix
        changes << { line_no: line_no, before: line, after: res[:after] }
        glued << { line_no: line_no, text: res[:after] } if res[:glued]
        res[:after]
      when :skip
        skipped << { line_no: line_no, text: line, reason: res[:reason] }
        line
      else # :clean
        glued << { line_no: line_no, text: line } if res[:glued]
        line
      end
    end

    # :nocov:
    def scan_record(record, model_name, columns, max_len, strip_all, dry_run, has_updated_at, counts, glued_all)
      touched = false
      columns.each do |col|
        value = record.public_send(col)
        next if value.blank?

        fixed, changes, skipped, glued = fix_text(value, max_len: max_len, strip_all: strip_all)
        glued.each { |g| glued_all << "#{model_name}##{record.id}.#{col} L#{g[:line_no]}  #{g[:text].inspect}" }
        if skipped.any?
          counts[:skipped] += skipped.size
          print_skipped(model_name, record.id, col, skipped)
        end
        next if changes.empty?

        counts[:columns_changed] += 1
        counts[:headings_fixed] += changes.size
        touched = true
        print_changes(model_name, record.id, col, changes)
        write(record, col, fixed, has_updated_at) unless dry_run
      end
      counts[:records_changed] += 1 if touched
    end

    def write(record, col, fixed, has_updated_at)
      attrs = { col => fixed }
      attrs[:updated_at] = Time.current if has_updated_at
      record.update_columns(attrs)
    end

    def print_changes(model_name, id, col, changes)
      puts "== #{model_name}##{id}.#{col} =="
      changes.each do |c|
        puts "  L#{c[:line_no]}  - #{c[:before].inspect}"
        puts "  L#{c[:line_no]}  + #{c[:after].inspect}"
      end
    end

    def print_skipped(model_name, id, col, skipped)
      skipped.each do |s|
        puts "  SKIP #{model_name}##{id}.#{col} L#{s[:line_no]}  #{s[:text].inspect}   (#{s[:reason]})"
      end
    end

    def print_glued(glued_all)
      return if glued_all.empty?

      puts "\n== REVIEW: headings left ending in a single '#' (spared in safe mode) =="
      puts "   If any is really a closing decoration rather than e.g. C#/F#, re-run with STRIP_ALL=1."
      glued_all.each { |g| puts "  #{g}" }
    end

    def print_summary(summary)
      puts
      puts "== Summary (#{summary[:dry_run] ? 'DRY RUN' : 'APPLIED'}) =="
      puts "  records scanned:    #{summary[:scanned]}"
      puts "  records changed:    #{summary[:records_changed]}"
      puts "  columns changed:    #{summary[:columns_changed]}"
      puts "  headings fixed:     #{summary[:headings_fixed]}"
      puts "  skipped (too long): #{summary[:skipped]}"
      puts "  glued '#' to review: #{summary[:glued]}"
    end
    # :nocov:
  end
end
