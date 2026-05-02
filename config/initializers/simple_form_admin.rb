# frozen_string_literal: true

# Tailwind-based SimpleForm wrappers for the admin site.
# Used exclusively via simple_horizontal_form_for (see FormHelper#horizontal_form_options).
# The public-facing site continues to use the Bootstrap wrappers in simple_form_bootstrap.rb.
#
# This file is listed as a Tailwind @source in admin_new.css so Vite picks up all utility classes.

SimpleForm.setup do |config|
  input_class   = "w-full rounded border border-gray-300 px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
  label_class   = "w-3/12 px-2 py-1.5 text-sm font-medium text-gray-700 shrink-0"
  grid_class    = "w-9/12 px-2"
  row_class     = "flex flex-wrap mb-4 items-start"
  error_class   = "block text-xs text-red-600 mt-1"
  hint_class    = "block mt-1 text-xs text-gray-500"
  invalid_class = "border-red-500"
  valid_class   = "border-green-500"

  config.wrappers :tailwind_horizontal_form,
      tag: "div", class: row_class,
      error_class: "has-error", valid_class: "has-success" do |b|
    b.use :html5
    b.use :placeholder
    b.optional :maxlength
    b.optional :minlength
    b.optional :pattern
    b.optional :min_max
    b.optional :readonly
    b.use :label, class: label_class
    b.wrapper :grid_wrapper, tag: "div", class: grid_class do |ba|
      ba.use :input, class: input_class, error_class: invalid_class, valid_class: valid_class
      ba.use :full_error, wrap_with: { tag: "div", class: error_class }
      ba.use :hint, wrap_with: { tag: "small", class: hint_class }
    end
  end

  config.wrappers :tailwind_horizontal_boolean,
      tag: "div", class: row_class,
      error_class: "has-error", valid_class: "has-success" do |b|
    b.use :html5
    b.optional :readonly
    b.wrapper tag: "label", class: label_class do |ba|
      ba.use :label_text
    end
    b.wrapper :grid_wrapper, tag: "div", class: "#{grid_class} py-1.5" do |wr|
      wr.wrapper :form_check_wrapper, tag: "div", class: "flex items-center gap-2" do |bb|
        bb.use :input, class: "size-4 rounded border-gray-300 accent-primary cursor-pointer shrink-0", error_class: invalid_class, valid_class: valid_class
        bb.use :full_error, wrap_with: { tag: "div", class: error_class }
        bb.use :hint, wrap_with: { tag: "small", class: hint_class }
      end
    end
  end

  config.wrappers :tailwind_horizontal_collection,
      item_wrapper_class: "flex items-center gap-2 mb-1",
      item_label_class: "text-sm text-gray-700",
      tag: "div", class: row_class,
      error_class: "has-error", valid_class: "has-success" do |b|
    b.use :html5
    b.optional :readonly
    b.use :label, class: label_class
    b.wrapper :grid_wrapper, tag: "div", class: grid_class do |ba|
      ba.use :input, class: "size-4 rounded border-gray-300 accent-primary cursor-pointer shrink-0", error_class: invalid_class, valid_class: valid_class
      ba.use :full_error, wrap_with: { tag: "div", class: error_class }
      ba.use :hint, wrap_with: { tag: "small", class: hint_class }
    end
  end

  config.wrappers :tailwind_horizontal_file,
      tag: "div", class: row_class,
      error_class: "has-error", valid_class: "has-success" do |b|
    b.use :html5
    b.optional :readonly
    b.use :label, class: label_class
    b.wrapper :grid_wrapper, tag: "div", class: grid_class do |ba|
      ba.use :input,
          class: "block w-full text-sm text-gray-700 file:mr-3 file:py-1 file:px-3 file:rounded file:border-0 file:bg-gray-100 file:text-sm file:font-medium hover:file:bg-gray-200 cursor-pointer",
          error_class: invalid_class, valid_class: valid_class
      ba.use :full_error, wrap_with: { tag: "div", class: error_class }
      ba.use :hint, wrap_with: { tag: "small", class: hint_class }
    end
  end

  config.wrappers :tailwind_horizontal_multi_select,
      tag: "div", class: row_class,
      error_class: "has-error", valid_class: "has-success" do |b|
    b.use :html5
    b.optional :readonly
    b.use :label, class: label_class
    b.wrapper :grid_wrapper, tag: "div", class: grid_class do |ba|
      ba.wrapper tag: "div", class: "flex gap-2 items-center" do |bb|
        bb.use :input, class: "flex-1 rounded border border-gray-300 px-3 py-1.5 text-sm", error_class: invalid_class, valid_class: valid_class
      end
      ba.use :full_error, wrap_with: { tag: "div", class: error_class }
      ba.use :hint, wrap_with: { tag: "small", class: hint_class }
    end
  end

  config.wrappers :tailwind_horizontal_range,
      tag: "div", class: row_class,
      error_class: "has-error", valid_class: "has-success" do |b|
    b.use :html5
    b.use :placeholder
    b.optional :readonly
    b.optional :step
    b.use :label, class: label_class
    b.wrapper :grid_wrapper, tag: "div", class: grid_class do |ba|
      ba.use :input, class: input_class, error_class: invalid_class, valid_class: valid_class
      ba.use :full_error, wrap_with: { tag: "div", class: error_class }
      ba.use :hint, wrap_with: { tag: "small", class: hint_class }
    end
  end
end
