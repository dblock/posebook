# frozen_string_literal: true

# Synthetic promo data for a disposable posebook_promo database. Model names are fictional.
abort 'refusing: not the promo database' unless Mongoid.default_client.database.name == 'posebook_promo'
PASSWORD = 'promo demo password 2026'
def person(name, display, email, gender)
  User.where(email: email).first ||
    User.create!(name: name, display_name: display, email: email, gender: gender,
                 phone: '+12025550100', password: PASSWORD, password_confirmation: PASSWORD)
end
admin = User.where(email: 'organizer@example.test').first ||
        User.bootstrap(name: 'Robin Organizer', display_name: 'Robin', email: 'organizer@example.test', gender: 'other',
                       phone: '+12025550199', password: PASSWORD, password_confirmation: PASSWORD).tap(&:save!)
venue = Venue.where(name: "Enoch's").first || Venue.create!(name: "Enoch's",
                                                            address: '480 10th Avenue, New York, NY 10018')
program = Program.where(name: "Figure Drawing at Enoch's").first || Program.create!(
  name: "Figure Drawing at Enoch's", venue: venue, participant_label: 'Model', time_zone: 'America/New_York',
  available_weekdays: %w[1], start_time: '18:30', end_time: '21:00', pay: 140,
  description: 'Monday night figure drawing. $20 at the door, no RSVP required, BYOB.'
)
VenueMembership.grant_coordinator_access(venue, admin)
models = [
  ['Avery Lane', 'Avery', 'female'], ['Jordan Pike', 'Jordan', 'male'], ['Sam Ortiz', 'Sam O.', 'other'],
  ['Riley Chen', 'Riley', 'female'], ['Morgan Hale', 'Morgan', 'male'], ['Casey Brook', 'Casey', 'female'],
  ['Quinn Avila', 'Quinn', 'other']
].map.with_index { |(n, d, g), i| person(n, d, "model#{i}@example.test", g) }
models.each do |m|
  next if program.participant?(m)

  ParticipantInvitation.with_session { |s| ProgramMembership.grant_participant_access(program, m, session: s) }
end
ProgramScheduleException.where(program: program, date: Date.new(2026, 12, 28)).first ||
  ProgramScheduleException.create!(program: program, date: Date.new(2026, 12, 28), mode: 'closed',
                                   reason: 'Holiday closure')
dates = %w[2026-11-30 2026-12-07 2026-12-14 2027-01-04 2027-01-11 2027-01-18]
models.first(6).zip(dates).each do |m, d|
  next if Booking.exists?(program_id: program.id, user_id: m.id)

  BookingMutation.new(program: program.reload, user: m).book(date: d)
end
models.first(2).each do |m|
  b = Booking.where(program_id: program.id, user_id: m.id).first
  AttendanceMutation.new(program: program.reload, user: m).confirm(b.id, version: b.lock_version)
rescue BookingMutation::Invalid => e
  puts "attendance #{m.name}: #{e.message}"
end
# Placeholder connection so the organizer's Google Calendar page shows its connected state.
# No worker runs in this demo, so nothing is ever sent to Google.
GoogleCalendarConnection.where(program_id: program.id).first ||
  GoogleCalendarConnection.create!(program: program, connected_by: admin,
                                   calendar_id: 'figure-drawing-at-enochs@group.calendar.google.com',
                                   refresh_token: 'placeholder-not-a-real-token')
puts({ program: program.slug, bookings: Booking.where(program_id: program.id).map do |x|
  [x.date.to_s, x.user.name, x.status]
end }.inspect)
