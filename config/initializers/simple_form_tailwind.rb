# frozen_string_literal: true

# Sole SimpleForm configuration (the generator's simple_form.rb is absorbed here): Tailwind
# wrappers for the public site (vertical, the default) and the admin (horizontal).
# Admin forms use tailwind_horizontal_form and variants via simple_horizontal_form_for; public
# horizontal forms use horizontal_form and variants through the same helper on non-admin controllers.
#
# Scanned as a Tailwind @source (`@source "../../../config/initializers/**/*.rb"` in admin.css and
# application.css), so Vite picks up every utility class used here.

# The one place the admin's form control classes are written down. The wrappers below read them,
# and so do the hand-rolled `form_with url:` forms (FormHelper#input_classes, shared/form/_field),
# so controls on different pages can't drift apart. Defined here, not in lib/, because an
# initializer cannot autoload a reloadable constant.
module FormStyles
  # INPUT_BASE carries no width so a caller can size a control (a table cell's amount, a search
  # box) without two width utilities fighting; INPUT is the full-width default.
  INPUT_BASE = "rounded border border-gray-300 px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
  INPUT      = "w-full #{INPUT_BASE}"
  LABEL      = "block text-sm font-medium text-gray-700 mb-1"
  HINT       = "block mt-1 text-xs text-gray-500"
  ERROR      = "block text-xs text-red-600 mt-1"
  INVALID    = "border-red-500"
  VALID      = "border-green-500"
  CHECKBOX   = "size-4 rounded border-gray-300 accent-primary cursor-pointer shrink-0"
  FILE_INPUT = "block w-full text-sm text-gray-700 file:mr-3 file:py-1 file:px-3 file:rounded file:border-0 file:bg-gray-100 file:text-sm file:font-medium hover:file:bg-gray-200 cursor-pointer"
end

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

  input_class   = FormStyles::INPUT
  label_class   = FormStyles::LABEL
  error_class   = FormStyles::ERROR
  hint_class    = FormStyles::HINT
  invalid_class = FormStyles::INVALID
  valid_class_f = FormStyles::VALID

  # Body shared by the vertical collection wrappers; they differ only in item_wrapper_class.
  vertical_collection_body = lambda do |b|
    b.use :html5
    b.optional :readonly
    b.wrapper :legend_tag, tag: "legend", class: "block text-sm font-medium text-gray-700 mb-1" do |ba|
      ba.use :label_text
    end
    b.use :input, class: FormStyles::CHECKBOX,
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
      bb.use :input, class: FormStyles::CHECKBOX,
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
          class: FormStyles::FILE_INPUT,
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

  # === Public horizontal wrappers (simple_horizontal_form_for on non-admin controllers) ===
  # These keep Bootstrap class names, which bootstrap_compat.css styles.

  # Body shared by the horizontal collection wrappers; they differ only in item_wrapper_class.
  horizontal_collection_body = lambda do |b|
    b.use :html5
    b.optional :readonly
    b.use :label, class: "col-sm-3 col-form-label pt-0"
    b.wrapper :grid_wrapper, tag: "div", class: "col-sm-9" do |ba|
      ba.use :input, class: "form-check-input", error_class: "is-invalid", valid_class: "is-valid"
      ba.use :full_error, wrap_with: { tag: "div", class: "invalid-feedback d-block" }
      ba.use :hint, wrap_with: { tag: "small", class: "form-text" }
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
      ba.use :hint, wrap_with: { tag: "small", class: "form-text" }
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
        bb.use :hint, wrap_with: { tag: "small", class: "form-text" }
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
      ba.use :hint, wrap_with: { tag: "small", class: "form-text" }
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
      ba.use :hint, wrap_with: { tag: "small", class: "form-text" }
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
      ba.use :hint, wrap_with: { tag: "small", class: "form-text" }
    end
  end

  # === Admin horizontal wrappers (simple_horizontal_form_for on admin controllers) ===
  # Chosen by FormHelper#horizontal_form_options.

  adm_input_class   = FormStyles::INPUT
  adm_label_class   = "w-full md:w-3/12 px-2 py-1.5 text-sm font-medium text-gray-700"
  adm_grid_class    = "w-full md:w-9/12 px-2"
  adm_row_class     = "flex flex-wrap mb-4 items-start"
  adm_error_class   = FormStyles::ERROR
  adm_hint_class    = FormStyles::HINT
  adm_invalid_class = FormStyles::INVALID
  adm_valid_class   = FormStyles::VALID

  # Label + input grid shared by tailwind_horizontal_form and tailwind_horizontal_range, which
  # differ only in their preceding optionals.
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
    # :label, not a bare <label> wrapper around :label_text, so the label carries for="<input id>"
    # and clicking its text toggles the checkbox.
    b.use :label, class: adm_label_class
    b.wrapper :grid_wrapper, tag: "div", class: "#{adm_grid_class} py-1.5" do |wr|
      wr.wrapper :form_check_wrapper, tag: "div", class: "flex items-center gap-2" do |bb|
        bb.use :input, class: FormStyles::CHECKBOX, error_class: adm_invalid_class, valid_class: adm_valid_class
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
      ba.use :input, class: FormStyles::CHECKBOX, error_class: adm_invalid_class, valid_class: adm_valid_class
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
          class: FormStyles::FILE_INPUT,
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

  # Inline wrapper for admin nested form fields
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

# HTML5 date/time inputs instead of SimpleForm's select-based default.
class DateTimeInput < SimpleForm::Inputs::DateTimeInput
  private

  def use_html5_inputs?
    input_options.fetch(:html5, true)
  end
end
