# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # Guards against calling `.html_safe` on the result of `.join` or `.to_sentence`,
      # which bypasses XSS escaping. Use `safe_join` or the `to_sentence` view helper instead.
      #
      # @example
      #   # bad
      #   items.join(", ").html_safe
      #   items.to_sentence.html_safe
      #
      #   # good
      #   safe_join(items, ", ")
      #   to_sentence(items)
      class UnsafeHtmlSafe < RuboCop::Cop::Base
        extend RuboCop::Cop::AutoCorrector

        MSG_JOIN = "Use `safe_join(array, separator)` instead of `array.join(...).html_safe`."
        MSG_TO_SENTENCE = "Use the `to_sentence(array)` view helper instead of `array.to_sentence.html_safe`."

        # @!method join_html_safe?(node)
        def_node_matcher :join_html_safe?, <<~PATTERN
          (send (send _ :join ...) :html_safe)
        PATTERN

        # @!method to_sentence_html_safe?(node)
        def_node_matcher :to_sentence_html_safe?, <<~PATTERN
          (send (send _ :to_sentence ...) :html_safe)
        PATTERN

        def on_send(node)
          if join_html_safe?(node)
            add_offense(node, message: MSG_JOIN) do |corrector|
              corrector.replace(node, autocorrected(node, :safe_join))
            end
          elsif to_sentence_html_safe?(node)
            add_offense(node, message: MSG_TO_SENTENCE) do |corrector|
              corrector.replace(node, autocorrected(node, :to_sentence))
            end
          end
        end

        private

        def autocorrected(node, helper)
          inner = node.receiver  # the .join / .to_sentence call
          receiver = inner.receiver.source
          args = inner.arguments.map(&:source)

          "#{helper_prefix(node)}#{helper}(#{([ receiver ] + args).join(', ')})"
        end

        # ViewComponents don't include view helpers directly; helpers must be accessed via
        # the `helpers` proxy. Plain helpers need `ActionController::Base.helpers.` to
        # call these methods outside of a request context.
        def helper_prefix(node)
          path = node.location.expression&.source_buffer&.name.to_s
          if path.include?("/components/")
            "helpers."
          elsif path.include?("/helpers/") || path.include?("/models/")
            "ActionController::Base.helpers."
          else
            ""
          end
        end
      end
    end
  end
end
