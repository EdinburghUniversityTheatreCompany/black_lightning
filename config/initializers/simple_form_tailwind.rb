# frozen_string_literal: true

# Sole SimpleForm configuration for this application.
# The generator-created simple_form.rb has been absorbed into this file.
#
# Tailwind-based SimpleForm wrappers for both the public site (vertical layout)
# and the admin site (horizontal layout).
#
# Public forms use vertical_form (and variants) as the default wrapper.
# Admin forms use tailwind_horizontal_form (and variants) via simple_horizontal_form_for.
# Public horizontal forms use horizontal_form (and variants) via simple_horizontal_form_for
# on non-admin controllers.
#
# This file is scanned as a Tailwind @source via the glob
#   @source "../../../config/initializers/**/*.rb"
# in admin.css and application.css, so Vite picks up all utility classes used here.

SimpleForm.setup do |config|
  # === Shared config ===
  config.button_class = "btn"
  config.boolean_label_class = "form-check-label"
  config.label_text = lambda { |label, required, explicit_label| "#{label} #{required}" }
  config.boolean_style = :inline
  config.item_wrapper_tag = :div
  config.include_default_input_wrapper_class = false
  config.error_notification_tag = :div
  config.error_notification_class = "alert alert-danger"
  config.error_method = :to_sentence
  config.input_field_error_class = "is-invalid"
  config.input_field_valid_class = "is-valid"
  config.browser_validations = true

  # === Vertical wrappers (public site defaults) ===
  # Use Tailwind utility classes. form-control/is-invalid/invalid-feedback are
  # shimmed in bootstrap_compat.css so they render correctly on the public site.

  input_class   = "w-full rounded border border-gray-300 px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
  label_class   = "block text-sm font-medium text-gray-700 mb-1"
  error_class   = "text-xs text-red-600 mt-1"
  hint_class    = "block mt-1 text-xs text-gray-500"
  invalid_class = "border-red-500"
  valid_class_f = "border-green-500"

  # Shared wrapper body for the vertical collection wrappers (regular + inline).
  # The two wrappers differ only in their item_wrapper_class (set on the
  # config.wrappers call); the builder steps below are identical.
  vertical_collection_body = lambda do |b|
    b.use :html5
    b.optional :readonly
    b.wrapper :legend_tag, tag: "legend", class: "block text-sm font-medium text-gray-700 mb-1" do |ba|
      ba.use :label_text
    end
    b.use :input, class: "size-4 rounded border-gray-300 accent-primary cursor-pointer shrink-0",
                  error_class: invalid_class, valid_class: valid_class_f
    b.use :full_error, wrap_with: { tag: "div", class: "#{error_class} block" }
    b.use :hint, wrap_with: { tag: "small", class: hint_class }
  end

  config.wrappers :vertical_form,
      tag: "div", class: "mb-4",
      error_class: "has-error", valid_class: "has-success" do |b|
    b.use :html5
    b.use :placeholder
    b.optional :maxlength
    b.optional :minlength
    b.optional :pattern
    b.optional :min_max
    b.optional :readonly
    b.use :label, class: label_class
    b.use :input, class: input_class, error_class: invalid_class, valid_class: valid_class_f
    b.use :full_error, wrap_with: { tag: "div", class: error_class }
    b.use :hint, wrap_with: { tag: "small", class: hint_class }
  end

  config.wrappers :vertical_boolean,
      tag: "fieldset", class: "mb-4",
      error_class: "has-error", valid_class: "has-success" do |b|
    b.use :html5
    b.optional :readonly
    b.wrapper :form_check_wrapper, tag: "div", class: "flex items-center gap-2" do |bb|
      bb.use :input, class: "size-4 rounded border-gray-300 accent-primary cursor-pointer shrink-0",
                     error_class: invalid_class, valid_class: valid_class_f
      bb.use :label, class: "text-sm text-gray-700"
      bb.use :full_error, wrap_with: { tag: "div", class: error_class }
      bb.use :hint, wrap_with: { tag: "small", class: hint_class }
    end
  end

  config.wrappers :vertical_collection,
      item_wrapper_class: "flex items-center gap-2 mb-1",
      item_label_class: "text-sm text-gray-700",
      tag: "fieldset", class: "mb-4",
      error_class: "has-error", valid_class: "has-success", &vertical_collection_body

  config.wrappers :vertical_collection_inline,
      item_wrapper_class: "inline-flex items-center gap-2 mr-4",
      item_label_class: "text-sm text-gray-700",
      tag: "fieldset", class: "mb-4",
      error_class: "has-error", valid_class: "has-success", &vertical_collection_body

  config.wrappers :vertical_file,
      tag: "div", class: "mb-4",
      error_class: "has-error", valid_class: "has-success" do |b|
    b.use :html5
    b.use :placeholder
    b.optional :maxlength
    b.optional :minlength
    b.optional :readonly
    b.use :label, class: label_class
    b.use :input,
          class: "block w-full text-sm text-gray-700 file:mr-3 file:py-1 file:px-3 file:rounded file:border-0 file:bg-gray-100 file:text-sm file:font-medium hover:file:bg-gray-200 cursor-pointer",
          error_class: invalid_class, valid_class: valid_class_f
    b.use :full_error, wrap_with: { tag: "div", class: error_class }
    b.use :hint, wrap_with: { tag: "small", class: hint_class }
  end

  config.wrappers :vertical_multi_select,
      tag: "div", class: "mb-4",
      error_class: "has-error", valid_class: "has-success" do |b|
    b.use :html5
    b.optional :readonly
    b.use :label, class: label_class
    b.wrapper tag: "div", class: "flex gap-2 items-center" do |ba|
      ba.use :input, class: input_class, error_class: invalid_class, valid_class: valid_class_f
    end
    b.use :full_error, wrap_with: { tag: "div", class: "#{error_class} block" }
    b.use :hint, wrap_with: { tag: "small", class: hint_class }
  end

  config.wrappers :vertical_range,
      tag: "div", class: "mb-4",
      error_class: "has-error", valid_class: "has-success" do |b|
    b.use :html5
    b.use :placeholder
    b.optional :readonly
    b.optional :step
    b.use :label, class: label_class
    b.use :input, class: "w-full accent-primary", error_class: invalid_class, valid_class: valid_class_f
    b.use :full_error, wrap_with: { tag: "div", class: "#{error_class} block" }
    b.use :hint, wrap_with: { tag: "small", class: hint_class }
  end

  # === Public horizontal wrappers (used via simple_horizontal_form_for on non-admin controllers) ===
  # These retain Bootstrap class names for compatibility with the public site's Bootstrap stylesheet.

  # Shared wrapper body for the horizontal collection wrappers (regular + inline).
  # The two wrappers differ only in their item_wrapper_class (set on the
  # config.wrappers call); the builder steps below are identical.
  horizontal_collection_body = lambda do |b|
    b.use :html5
    b.optional :readonly
    b.use :label, class: "col-sm-3 col-form-label pt-0"
    b.wrapper :grid_wrapper, tag: "div", class: "col-sm-9" do |ba|
      ba.use :input, class: "form-check-input", error_class: "is-invalid", valid_class: "is-valid"
      ba.use :full_error, wrap_with: { tag: "div", class: "invalid-feedback d-block" }
      ba.use :hint, wrap_with: { tag: "small", class: "form-text text-muted" }
    end
  end

  config.wrappers :horizontal_form, tag: "div", class: "form-group row", error_class: "form-group-invalid", valid_class: "form-group-valid" do |b|
    b.use :html5
    b.use :placeholder
    b.optional :maxlength
    b.optional :minlength
    b.optional :pattern
    b.optional :min_max
    b.optional :readonly
    b.use :label, class: "col-sm-3 col-form-label"
    b.wrapper :grid_wrapper, tag: "div", class: "col-sm-9" do |ba|
      ba.use :input, class: "form-control", error_class: "is-invalid", valid_class: "is-valid"
      ba.use :full_error, wrap_with: { tag: "div", class: "invalid-feedback" }
      ba.use :hint, wrap_with: { tag: "small", class: "form-text text-muted" }
    end
  end

  config.wrappers :horizontal_boolean, tag: "div", class: "form-group row", error_class: "form-group-invalid", valid_class: "form-group-valid" do |b|
    b.use :html5
    b.optional :readonly
    b.wrapper tag: "label", class: "col-sm-auto" do |ba|
      ba.use :label_text
    end
    b.wrapper :grid_wrapper, tag: "div", class: "col-sm" do |wr|
      wr.wrapper :form_check_wrapper, tag: "div", class: "form-check" do |bb|
        bb.use :input, class: "form-check-input", error_class: "is-invalid", valid_class: "is-valid"
        bb.use :full_error, wrap_with: { tag: "div", class: "invalid-feedback d-block" }
        bb.use :hint, wrap_with: { tag: "small", class: "form-text text-muted" }
      end
    end
  end

  config.wrappers :horizontal_collection, item_wrapper_class: "form-check", item_label_class: "form-check-label", tag: "div", class: "form-group row", error_class: "form-group-invalid", valid_class: "form-group-valid", &horizontal_collection_body

  config.wrappers :horizontal_collection_inline, item_wrapper_class: "form-check form-check-inline", item_label_class: "form-check-label", tag: "div", class: "form-group row", error_class: "form-group-invalid", valid_class: "form-group-valid", &horizontal_collection_body

  config.wrappers :horizontal_file, tag: "div", class: "form-group row", error_class: "form-group-invalid", valid_class: "form-group-valid" do |b|
    b.use :html5
    b.use :placeholder
    b.optional :maxlength
    b.optional :minlength
    b.optional :readonly
    b.use :label, class: "col-sm-3 col-form-label"
    b.wrapper :grid_wrapper, tag: "div", class: "col-sm-9" do |ba|
      ba.use :input, error_class: "is-invalid", valid_class: "is-valid"
      ba.use :full_error, wrap_with: { tag: "div", class: "invalid-feedback d-block" }
      ba.use :hint, wrap_with: { tag: "small", class: "form-text text-muted" }
    end
  end

  config.wrappers :horizontal_multi_select, tag: "div", class: "form-group row", error_class: "form-group-invalid", valid_class: "form-group-valid" do |b|
    b.use :html5
    b.optional :readonly
    b.use :label, class: "col-sm-3 col-form-label"
    b.wrapper :grid_wrapper, tag: "div", class: "col-sm-9" do |ba|
      ba.wrapper tag: "div", class: "d-flex flex-row justify-content-between align-items-center" do |bb|
        bb.use :input, class: "form-control", error_class: "is-invalid", valid_class: "is-valid"
      end
      ba.use :full_error, wrap_with: { tag: "div", class: "invalid-feedback d-block" }
      ba.use :hint, wrap_with: { tag: "small", class: "form-text text-muted" }
    end
  end

  config.wrappers :horizontal_range, tag: "div", class: "form-group row", error_class: "form-group-invalid", valid_class: "form-group-valid" do |b|
    b.use :html5
    b.use :placeholder
    b.optional :readonly
    b.optional :step
    b.use :label, class: "col-sm-3 col-form-label"
    b.wrapper :grid_wrapper, tag: "div", class: "col-sm-9" do |ba|
      ba.use :input, class: "form-control-range", error_class: "is-invalid", valid_class: "is-valid"
      ba.use :full_error, wrap_with: { tag: "div", class: "invalid-feedback d-block" }
      ba.use :hint, wrap_with: { tag: "small", class: "form-text text-muted" }
    end
  end

  # === Admin horizontal wrappers (used via simple_horizontal_form_for on admin/ controllers) ===
  # Tailwind utility classes; invoked by FormHelper#horizontal_form_options.

  adm_input_class   = "w-full rounded border border-gray-300 px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
  adm_label_class   = "w-full md:w-3/12 px-2 py-1.5 text-sm font-medium text-gray-700"
  adm_grid_class    = "w-full md:w-9/12 px-2"
  adm_row_class     = "flex flex-wrap mb-4 items-start"
  adm_error_class   = "block text-xs text-red-600 mt-1"
  adm_hint_class    = "block mt-1 text-xs text-gray-500"
  adm_invalid_class = "border-red-500"
  adm_valid_class   = "border-green-500"

  # Shared label + input-grid fragment for the admin Tailwind text-style wrappers
  # (used by tailwind_horizontal_form and tailwind_horizontal_range, which share
  # the same label/input/error/hint layout but differ in their preceding optionals).
  adm_label_and_input_grid = lambda do |b|
    b.use :label, class: adm_label_class
    b.wrapper :grid_wrapper, tag: "div", class: adm_grid_class do |ba|
      ba.use :input, class: adm_input_class, error_class: adm_invalid_class, valid_class: adm_valid_class
      ba.use :full_error, wrap_with: { tag: "div", class: adm_error_class }
      ba.use :hint, wrap_with: { tag: "small", class: adm_hint_class }
    end
  end

  config.wrappers :tailwind_horizontal_form,
      tag: "div", class: adm_row_class,
      error_class: "has-error", valid_class: "has-success" do |b|
    b.use :html5
    b.use :placeholder
    b.optional :maxlength
    b.optional :minlength
    b.optional :pattern
    b.optional :min_max
    b.optional :readonly
    adm_label_and_input_grid.call(b)
  end

  config.wrappers :tailwind_horizontal_boolean,
      tag: "div", class: adm_row_class,
      error_class: "has-error", valid_class: "has-success" do |b|
    b.use :html5
    b.optional :readonly
    b.wrapper tag: "label", class: adm_label_class do |ba|
      ba.use :label_text
    end
    b.wrapper :grid_wrapper, tag: "div", class: "#{adm_grid_class} py-1.5" do |wr|
      wr.wrapper :form_check_wrapper, tag: "div", class: "flex items-center gap-2" do |bb|
        bb.use :input, class: "size-4 rounded border-gray-300 accent-primary cursor-pointer shrink-0", error_class: adm_invalid_class, valid_class: adm_valid_class
        bb.use :full_error, wrap_with: { tag: "div", class: adm_error_class }
        bb.use :hint, wrap_with: { tag: "small", class: adm_hint_class }
      end
    end
  end

  config.wrappers :tailwind_horizontal_collection,
      item_wrapper_class: "flex items-center gap-2 mb-1",
      item_label_class: "text-sm text-gray-700",
      tag: "div", class: adm_row_class,
      error_class: "has-error", valid_class: "has-success" do |b|
    b.use :html5
    b.optional :readonly
    b.use :label, class: adm_label_class
    b.wrapper :grid_wrapper, tag: "div", class: adm_grid_class do |ba|
      ba.use :input, class: "size-4 rounded border-gray-300 accent-primary cursor-pointer shrink-0", error_class: adm_invalid_class, valid_class: adm_valid_class
      ba.use :full_error, wrap_with: { tag: "div", class: adm_error_class }
      ba.use :hint, wrap_with: { tag: "small", class: adm_hint_class }
    end
  end

  config.wrappers :tailwind_horizontal_file,
      tag: "div", class: adm_row_class,
      error_class: "has-error", valid_class: "has-success" do |b|
    b.use :html5
    b.optional :readonly
    b.use :label, class: adm_label_class
    b.wrapper :grid_wrapper, tag: "div", class: adm_grid_class do |ba|
      ba.use :input,
          class: "block w-full text-sm text-gray-700 file:mr-3 file:py-1 file:px-3 file:rounded file:border-0 file:bg-gray-100 file:text-sm file:font-medium hover:file:bg-gray-200 cursor-pointer",
          error_class: adm_invalid_class, valid_class: adm_valid_class
      ba.use :full_error, wrap_with: { tag: "div", class: adm_error_class }
      ba.use :hint, wrap_with: { tag: "small", class: adm_hint_class }
    end
  end

  config.wrappers :tailwind_horizontal_multi_select,
      tag: "div", class: adm_row_class,
      error_class: "has-error", valid_class: "has-success" do |b|
    b.use :html5
    b.optional :readonly
    b.use :label, class: adm_label_class
    b.wrapper :grid_wrapper, tag: "div", class: adm_grid_class do |ba|
      ba.wrapper tag: "div", class: "flex gap-2 items-center" do |bb|
        bb.use :input, class: "flex-1 rounded border border-gray-300 px-3 py-1.5 text-sm", error_class: adm_invalid_class, valid_class: adm_valid_class
      end
      ba.use :full_error, wrap_with: { tag: "div", class: adm_error_class }
      ba.use :hint, wrap_with: { tag: "small", class: adm_hint_class }
    end
  end

  config.wrappers :tailwind_horizontal_range,
      tag: "div", class: adm_row_class,
      error_class: "has-error", valid_class: "has-success" do |b|
    b.use :html5
    b.use :placeholder
    b.optional :readonly
    b.optional :step
    adm_label_and_input_grid.call(b)
  end

  # Inline wrapper — used in admin nested form fields
  config.wrappers :inline_form,
      tag: "span",
      error_class: "has-error", valid_class: "has-success" do |b|
    b.use :html5
    b.use :placeholder
    b.optional :maxlength
    b.optional :minlength
    b.optional :pattern
    b.optional :min_max
    b.optional :readonly
    b.use :label, class: "sr-only"
    b.use :input, class: adm_input_class, error_class: adm_invalid_class, valid_class: adm_valid_class
    b.use :error, wrap_with: { tag: "div", class: adm_error_class }
    b.optional :hint, wrap_with: { tag: "small", class: adm_hint_class }
  end

  # === Defaults (public site) ===
  config.default_wrapper = :vertical_form
  config.wrapper_mappings = {
    boolean:       :vertical_boolean,
    check_boxes:   :vertical_collection,
    date:          :vertical_multi_select,
    datetime:      :vertical_multi_select,
    file:          :vertical_file,
    radio_buttons: :vertical_collection,
    range:         :vertical_range,
    time:          :vertical_multi_select
  }
end

# Force HTML5 date/time inputs (overrides SimpleForm's default which falls back to
# select-based inputs). Absorbed from the generator-created simple_form.rb.
class DateTimeInput < SimpleForm::Inputs::DateTimeInput
  private

  def use_html5_inputs?
    input_options.fetch(:html5, true)
  end
end
