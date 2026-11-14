# Organizing Venues and Programs

[Back to Posebook](../../README.md)

System administrators create physical venues, invite or promote **Venue Coordinators**, and manage accounts. Venue coordinators edit their location, photos, and Instagram, create recurring programs, manage every program there, and invite or promote **Program Coordinators**. Coordinator assignment does not expose a global user directory.

On **Venue Coordinators** or **Program Coordinators**, enter the recipient's email and choose **Continue**. If they already have an active account, Posebook offers **Grant Coordinator Access** for confirmation instead of creating another account. Their other memberships and booking permissions are retained. If they are new, create a private registration link and optionally send it by email. The link can be accepted only with the invited email, expires in 30 days, and can be revoked from the coordinator list. Copy it when created; it is not displayed again.

Venue coordinator access includes all programs at that venue; program coordinator access includes only that program. Neither promotion grants system admin access. An outstanding invitation stops working if its sender becomes inactive or loses the authority to delegate that venue/program.

Use **Create Program** on a venue for a recurring program. New programs default to Mondays at 9 AM UTC and zero pay; choose the actual weekdays, start time, time zone, pay, and instructions in settings. Each program has separate rules, invitations, roster, and calendar. Program coordinators edit only their assigned programs and cannot edit the venue, manage siblings, or assign coordinator roles. Venue coordinators inherit those capabilities across all programs at their venue.

Program settings include **Program Label** and **Participant Label**, defaulting to **Program** and **Participant**. Use singular labels such as **Workshop** and **Instructor** to specialize the interface. Calendars, rosters, invitations, and booking controls use those labels; **Pay** stays unchanged. Labels do not change booking rules: one person per date, one upcoming booking per person per program, and organizer permission for repeat bookings. Gender rules are optional and disabled by default; only programs with those rules require a gender selection to book. Attendee registration is not implemented.

Program coordinators can invite participants, review their program's roster and booking history, schedule or update bookings, confirm attendance, and manage dated schedule exceptions when a booking is added, moved, or closed.

Invitations provide private, single-use registration links. A participant must accept an invitation to join a program. Joining grants an initial booking; coordinators can invite participants to book again after they complete a booking. A paused participant can keep an existing booking and cancel it, but cannot book or reschedule until resumed. Memberships and invitations are independent across programs.

Email is used for account recovery and optional invitation delivery. Posebook does not yet send automated booking reminders or booking notifications.
