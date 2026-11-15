# Venues, Programs, and Bookings

[Back to Posebook](../../README.md)

Anyone with a venue link can view its address, Instagram, and recurring programs; choose **Photos** for the venue gallery. A program link opens its details; choose **Calendar** to view the public schedule. Signed-in participants can also open their **History**. Venue and program lists and booking actions require sign-in and the appropriate access. Public calendars show only active participants' public names and opted-in Instagram handles; private profiles appear as **To be announced**.

As a participant, choose an available date and confirm the date and time to make a booking. You can have one upcoming booking per recurring program, including multiple programs at the same venue. Invitations are program-specific, with no additional cross-program date/time conflict restriction. Use **Change Date** or **Cancel Booking** on your booking to update plans, and provide a short explanation when prompted. Dates and times follow the program's time zone. All accounts require a private gender selection; programs may additionally enable gender rules.

When an end time is provided, the calendar and booking details show the duration, and the booking completes at that time. An overnight session can end the next day. Without an end time, a booking completes at the end of its local date.

Your homepage lists your upcoming bookings in date/time order, with the venue's primary photo, address, and Google Maps link inside each booking card. The same date, attendance status, and booking buttons appear on the program's View and Calendar pages. **Change Date** and **Cancel Booking** retain their existing explanations and deadlines; attendance confirmation appears when its window opens.

Location pages use `/venues/:slug`; calendars and bookings use `/sessions/:slug`. Previous slugs remain valid within those paths. Old root shortcuts and venue-nested calendar/booking links are not redirected.

Starting seven days before your booking, confirm that you will attend. Until five days before the booking, you can report that you can no longer make it and follow the rescheduling steps. After that cutoff, contact an organizer to reschedule; you can still confirm attendance or cancel.
