# UI Conventions

Posebook pages are server-rendered Rails views with small progressive-enhancement scripts. New screens should reuse these patterns before introducing new markup, styles, or scripts, and every page must keep working without JavaScript.

## Wording

Use Title Case for headings, tabs, buttons, and links that act as buttons, for example "Save Program" or "Copy Link". Keep explanation text short: prefer a one-line `<small>` hint next to the control it explains and move secondary details into a `<details>` disclosure. Use each program's `program_label` and `participant_label` instead of hard-coding "Program" or "Participant".

## Navigation

Render Home breadcrumbs and tabs with `shared/page_navigation`. Tab bars are hidden for signed-out visitors. Program members see Program and Calendar, with Exceptions and History available to managers, followed by a separator and scoped management actions. The active tab sets `aria-current`. Manager-only blocks depend on controller-computed permissions such as `@program_coordinator`, never on hidden markup.

Use `shared/photo_series` inside a card's `data-photo-series` container to open its public primary photo and navigate the owner's remaining public photos. Use `shared/photo_thumbnail` inside `.photo-gallery` for gallery navigation. Both reuse the accessible photo-preview dialog, with wrapping previous/next buttons and arrow keys; placeholders remain ordinary links to their owner page.

## Actions

Plain `button`, `input[type=submit]`, and `.button-link` elements are primary actions with a comfortable touch target. Use `.secondary-action` for less important actions; buttons inside tables are compact automatically. Group related actions in `.participant-actions`. `pending-controls.js` marks submitted forms busy and disables their buttons, so do not add per-page loading code.

## Status and Identity

Show states with the `status_label` helper, which maps statuses to success, danger, warning, and neutral tones. Show a person with `participant_contact_label`, which renders `Name <email> (Gender)` or only the email when nothing else is known.

## Tables

Wrap tables in `.table-scroll` with `role="region"`, an `aria-label`, and `tabindex="0"`, preceded by a `.scroll-hint` that appears on narrow screens. Render an empty-state paragraph instead of an empty table, and paginate long lists with `nav.participant-pagination`. See `app/views/program_invitations/index.html.erb` for the canonical example. Table cells are vertically centered, except calendar days, which align to the top.

## Forms and Feedback

Forms without a table, gallery, or tabs narrow automatically to a readable width. Render validation errors with `shared/_errors`, which uses `role="alert"`. Flash messages use `role="alert"` or `role="status"` and float over the top of the page without shifting layout; notices dismiss after three seconds, alerts stay until dismissed. Scripts that update a page in place replace the contents of `[data-flash-messages]`.

## Copying Links

Use `shared/_copy_button` (with `show_link: true` to display the URL) or the `copy_button` helper. The visible link can be copied by hand without JavaScript, and copy failures tell the user to copy it manually.

## Layout

Pages must fit desktop (1280px), phone (390px), and narrow (320px) widths without horizontal page overflow; only `.table-scroll` regions scroll sideways. Responsive breakpoints are 40rem and 50rem. Long URLs and names must wrap.

## Verifying Interface Changes

Cover interface changes with system specs in `spec/system`, which drive headless Chrome through Capybara and Cuprite. `spec/support/browser_helpers.rb` provides `sign_in_through_browser`, `each_viewport`, `resize_to`, `expect_no_horizontal_overflow`, `without_javascript`, `stub_clipboard`, `copied_text`, and `capture_screenshot`. See [Contributing](../CONTRIBUTING.md#browser-tests) for running them and capturing screenshots for PRs.
