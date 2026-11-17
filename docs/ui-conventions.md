# UI Conventions

Posebook pages are server-rendered Rails views with small progressive-enhancement scripts. New screens should reuse these patterns before introducing new markup, styles, or scripts, and every page must keep working without JavaScript.

## Wording

Use Title Case for headings, tabs, buttons, and links that act as buttons, for example "Save Program" or "Copy Link". Keep explanation text short: prefer a one-line `<small>` hint next to the control it explains and move secondary details into a `<details>` disclosure. Use each program's `program_label` and `participant_label` instead of hard-coding "Program" or "Participant".

## Navigation

Render Home breadcrumbs and tabs with `shared/page_navigation`, which uses `shared/page_tabs` for each navigation level. Tab bars are hidden for signed-out visitors. Venue primary tabs are Venue, Programs, Photos, and authorized Settings; program primary tabs are Program, Calendar, Photos, the configured plural participant label, and authorized Settings. Managers get secondary sections for Calendar, the participant group, and Settings; ordinary participants retain only Program, Calendar, and Photos. Pass the selected primary group as `active` and the current section as `secondary_active`, with a distinct `secondary_label` for its navigation landmark. Both levels set `aria-current` and wrap on narrow screens. Other pages retain their existing information/action separator. Manager-only blocks depend on permissions such as `@program_coordinator`, never on hidden markup.

Use `shared/photo_series` inside a card's `data-photo-series` container to open its public primary photo and navigate the owner's remaining public photos. Use `shared/photo_thumbnail` inside `.photo-gallery` for gallery navigation. Both reuse the accessible photo-preview dialog, with wrapping previous/next buttons and arrow keys; placeholders remain ordinary links to their owner page.

## Actions

Plain `button`, `input[type=submit]`, and `.button-link` elements are primary actions with a comfortable touch target. Use `.secondary-action` for less important actions; buttons inside tables are compact automatically. Group related actions in `.participant-actions`. `pending-controls.js` marks submitted forms busy and disables their buttons, so do not add per-page loading code.

Keep New Program at the bottom of the venue Programs page, after the program cards or empty-state message. Keep Invite a Coordinator at the bottom of program coordinator lists; on venue coordinator lists it remains beside the heading in `.title-row`. Do not make creation actions primary tabs.

Put personal participant invitation links and Invite All Available after their lists and pagination, including empty states.

## Status and Identity

Show states with the `status_label` helper, which maps statuses to success, danger, warning, and neutral tones. Show a person with `participant_contact_label`, which renders `Name <email> (Gender)` or only the email when nothing else is known.

Reuse `shared/participant_identity` for roster, applicant, invitee, and Applications History participant columns, with `shared/participant_portrait` supplying the portrait or placeholder. Link known accounts to their profile and retain invitation details as the fallback for invitees without a linked account; never match accounts by invitation email. Preserve application and invitation identity snapshots and do not expose additional live account details through these snapshots. Coordinator tables also reuse the portrait and link names to profiles, never email addresses to mail links. Keep Revoke in its own invitation column and put a plain-text View link in the rightmost column.

## Dates and Times

Render human-readable HTML dates with `shared/date`, passing `value:` as a `Date`, `Time`, or `DateTime` and `zone:` as the program's IANA time zone. Use the booking's saved time zone for booking dates and UTC for administrator audit history. Never convert civil dates to artificial midnight timestamps.

Dates use Today, Yesterday, or Tomorrow, then Last/Next weekday within six calendar days of the local current date. Other dates use abbreviated months and omit the current year; relative labels also work across year boundaries. Default labels include weekdays, such as `Wed, Dec 16`, while `format: :compact` uses `Dec 16` or `Next Wed` for tables. Timestamps show a minute-precision 12-hour clock on the same line as the date. Date columns have a 10rem minimum width and expand to fit longer labels inside the table's scrolling region. Use `show_time: false` only when an adjacent booking range or dedicated Time column already supplies the clock; preserve those ranges, overnight markers, duration, and zone.

Application details show Submitted On using the submission timestamp, falling back to creation for older records without it. Invitation details show Submitted On using the invitation's creation timestamp. Both use the program time zone.

Administrator account details include Account Created and Account Updated timestamps in UTC; ordinary account detail views do not expose this metadata.

Every rendered date has a semantic `datetime`, complete hover `title`, and matching accessible label. Hover details show the full date, time to the minute, and local time zone abbreviation, without seconds, fractional seconds, or numeric UTC offsets. The machine-readable value retains full precision and its offset. Dates remain ordinary text, without a custom cursor, click expansion, or additional tab stops. Calendar `format: :day` and `format: :month` retain day-number and month labels with full hover details and date/month machine precision.

Keep editable date/time fields, route parameters, provider payloads, and durable email/event descriptions in their existing absolute formats. Copyright years are not date instances.

## Tables

Wrap tables in `.table-scroll` with `role="region"`, an `aria-label`, and `tabindex="0"`, preceded by a `.scroll-hint` that appears on narrow screens. Render an empty-state paragraph instead of an empty table, and paginate long lists with `CursorPage` and `shared/pagination`, which renders `nav.participant-pagination` with First/Previous/Next links. Keep navigation outside the nonempty-results block so emptied cursor ranges still have a First link. Do not display page numbers or absolute row ranges: insertions and deletions change those positions. Preserve the cursor in table actions and redirects, and reset it when changing filters. See `app/views/program_invitations/index.html.erb` for the canonical example. Table cells are vertically centered, except calendar days, which align to the top.

Standard data tables inherit the same body font size, and identity columns have a 22rem minimum width so contact information stays readable inside the scrolling region. The participant roster uses an 18rem identity minimum, tighter cell padding, and a compact arrow column to leave more room for its separate actions. Keep Invite to Book in its own roster column and separate application Review and View Profile actions. A native disclosure arrow opens roster pause notes and Applications History reviewer notes in a separate row spanning the rightmost three columns, including without JavaScript. Fade the border between the expanded parent and detail rows to a faint divider, retaining the detail row's normal bottom boundary. Omit arrows for events without notes and show history events as plain text, not status badges. Keep ordinary booking timestamps and urgent follow-up copy off the roster while retaining calendar warnings.

Program and account booking histories reuse the native arrow and fading-border treatment. Keep explanations, time changes, attendance changes, and authorized manager details in a left-aligned row spanning the content columns. Omit empty disclosures, preserve existing manager-only visibility and edit eligibility, and keep the controls usable with keyboard and without JavaScript.

Use the shared GET table filter with in-place updates and a no-JavaScript submit fallback. Roster status options include program-wide counts; invitation status and application history event filters default to All. Preserve filters through pagination and mutation return paths, reset cursors on filter changes, and keep private draft events out of history filters.

## Forms and Feedback

Venue and program descriptions are public; program descriptions also appear on both application forms. Program instructions remain private to participants and coordinators. All three fields support Markdown through `render_markdown`: it preserves plain-text line breaks, sanitizes output, and excludes raw HTML and embedded images. Use `shared/description` for public descriptions, omitting blank sections. Label public/private visibility and show a short formatting hint beside each editor. Markdown code blocks and long words must fit narrow viewports. Pay stays member-only; booking horizon belongs in settings, not the overview or application forms.

Forms without a table, gallery, or tabs narrow automatically to a readable width. Public application preparation is an exception: its heading and breadcrumbs use full page width while its email form is capped at 28rem and fits smaller screens. Render validation errors with `shared/_errors`, which uses `role="alert"`. Flash messages use `role="alert"` or `role="status"` and float over the top of the page without shifting layout; notices dismiss after three seconds, alerts stay until dismissed. Scripts that update a page in place replace the contents of `[data-flash-messages]`.

## Copying Links

Use `shared/_copy_button` (with `show_link: true` to display the URL) or the `copy_button` helper. The visible link can be copied by hand without JavaScript, and copy failures tell the user to copy it manually.

## Layout

Pages must fit desktop (1280px), phone (390px), and narrow (320px) widths without horizontal page overflow; only `.table-scroll` regions scroll sideways. Responsive breakpoints are 40rem and 50rem. Long URLs and names must wrap.

## Verifying Interface Changes

Cover interface changes with system specs in `spec/system`, which drive headless Chrome through Capybara and Cuprite. `spec/support/browser_helpers.rb` provides `sign_in_through_browser`, `each_viewport`, `resize_to`, `expect_no_horizontal_overflow`, `without_javascript`, `stub_clipboard`, `copied_text`, and `capture_screenshot`. See [Contributing](../CONTRIBUTING.md#browser-tests) for running them and capturing screenshots for PRs.
