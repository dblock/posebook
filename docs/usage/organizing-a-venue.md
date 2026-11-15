# Organizing Venues and Programs

[Back to Posebook](../../README.md)

System administrators create physical venues, invite or promote **Venue Coordinators**, and manage accounts. Venue coordinators edit their location, photos, and Instagram, create recurring programs, manage every program there, and invite or promote **Program Coordinators**. Coordinator assignment does not expose a global user directory.

Use the venue's **Edit**, **Photos**, **Create Program**, and **Coordinators** tabs for permitted management actions. Programs provide **Edit** and **Google Calendar** tabs alongside Calendar, History, and participant/coordinator management. Breadcrumbs show the current venue, program, and section.

On **Venue Coordinators** or **Program Coordinators**, leave email blank and choose **Continue** to generate a private link for one person, or enter an email to restrict acceptance to that address. If that email already has an active account, Posebook offers **Grant Coordinator Access** for confirmation instead of creating another account. Their other memberships and booking permissions are retained. For a new account, create a private registration link and optionally send it by email. No email is sent when the address is blank. The link expires in 30 days and can be revoked from the coordinator list. Copy it when created; it is not displayed again.

Venue coordinator access includes all programs at that venue; program coordinator access includes only that program. Neither promotion grants system admin access. An outstanding invitation stops working if its sender becomes inactive or loses the authority to delegate that venue/program.

Use **Create Program** on a venue for a recurring program. New programs default to Mondays at 9 AM UTC, no end time, and zero pay; choose the actual weekdays, times, time zone, pay, and instructions in settings. An optional end time earlier than the start means the next day. Use **Manage Schedule** to set or clear times for a single date. End times determine booking completion; without one, bookings complete at the end of the local date. Each program has separate rules, invitations, roster, and calendar. Program coordinators edit only their assigned programs and cannot edit the venue, manage siblings, or assign coordinator roles. Venue coordinators inherit those capabilities across all programs at their venue.

Program settings include **Program Label** and **Participant Label**, defaulting to **Program** and **Participant**. Use singular labels such as **Workshop** and **Instructor** to specialize the interface. Calendars, rosters, invitations, and booking controls use those labels; **Pay** stays unchanged. Labels do not change booking rules: one person per date, one upcoming booking per person per program, and organizer permission for repeat bookings. Gender rules are optional and disabled by default; all accounts require a gender selection. Attendee registration is not implemented.

Program coordinators use the program navigation to open the calendar, booking history, and participant roster and invitations. From the calendar they can schedule or update bookings, confirm attendance, and manage dated schedule exceptions. Venue coordinators and system admins can also open the program's coordinator page. Pending participant invitations can be revoked beside their status on the roster page.

Invitations provide private, single-use registration links with the same optional-email policy for participants and coordinators. A specified email restricts acceptance to that account; leave it blank for a link one recipient can accept with any account. A participant must accept an invitation to join a program. Joining grants an initial booking; coordinators can invite participants to book again after they complete a booking. A paused participant can keep an existing booking and cancel it, but cannot book or reschedule until resumed. Memberships and invitations are independent across programs.

Email is used for account recovery and optional invitation delivery. Posebook does not yet send automated booking reminders or booking notifications.
