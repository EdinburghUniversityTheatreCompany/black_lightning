# Black Lightning - Claude Code Guidelines


## Packages
Ruby on Rails 8.1 

Use pnpm for package management rather than npm, yarn, or bun.

We use minitest for testing.

The entire site currently uses Tailwind v4

Use stimulus for all JavaScript sprinkles. We use Vite rather than jsbundling, cssbundling and importmaps. We use propshaft too to serve some images and JavaScript files that are only used on a few pages

## JavaScript
Prefer writing Stimulus controllers that go into the `app/javascript/controllers` folder. Custom modules go into the `app/javascript/lib folder`.

JavaScript that is only used on specific pages should go into the `app/assets` folder so it can be loaded by Propshaft.

Stylesheets also live in `app/javascript/styles` so they can be handled by Vite.

## Maintain Documentation

If you learn something about the project that would be useful context for other agents looking at the codebase, add it to this file at the end of your to do list.

## URL as state
Always maintain the URL as state with readable parameters where possible for GET actions.

## Button Styling

`ButtonComponent` (`app/components/button_component.rb`) is the single source of truth for all button styles. **Never use Bootstrap `btn btn-*` classes** — those shims have been removed.

### Variants: `:primary`, `:secondary`, `:danger`, `:success`, `:warning`, `:info`, `:link`
### Sizes: `:sm`, `:md` (default), `:lg`

### How to render a button

**Model resource links — use `get_link` (handles permissions + path generation):**
```erb
<%= get_link(@user, :edit) %>
<%= get_link(@user, :destroy) %>
<%= get_link(User, :new) %>
<%# Override variant explicitly %>
<%= get_link(@user, :show, variant: :primary) %>
<%# Custom link target for nested routes %>
<%= get_link(Admin::Feedback, :new, link_text: "Submit Feedback", link_target: new_admin_show_feedback_path(@show)) %>
```

**Non-model links — use `link_to` with `btn_classes`:**
```erb
<%= link_to "Cancel", some_path, class: btn_classes(:secondary) %>
<%= link_to "Import", new_admin_membership_import_path, class: btn_classes(:primary, :sm) %>
```

**Form submits — use `btn_classes`:**
```erb
<%= f.submit "Save", class: btn_classes(:primary) %>
<%= f.button :submit, "Agree", class: btn_classes(:success) %>
```

**Inside ViewComponent templates — use `ButtonComponent.classes_for` directly** (components don't get helpers auto-included):
```erb
<%= link_to "Cancel", @cancel_path, class: ButtonComponent.classes_for(variant: :secondary) %>
<%= f.submit "Save", class: ButtonComponent.classes_for(variant: :primary, size: :sm) %>
```

**To change a colour or add a variant, edit only `ButtonComponent::VARIANT_CLASSES`.**

## Link Helper

**Use `get_link` from `LinkHelper` for button-style links to model resources.**

The `get_link` helper provides:
- Consistent styling via `ButtonComponent` based on action type (auto-detected)
- Automatic CanCanCan permission checking
- Automatic path generation for model resources

## ViewComponents
When writing a ViewComponent, check for an applicable skill, and make sure to create a preview to pass the cop.

# Testing
Start the test database using `docker start /mysql8` before running any tests.