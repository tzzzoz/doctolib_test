class Event < ApplicationRecord
  # set days_to_week for each event to make it easy to group by days_to_week_start
  before_save :complete_days_to_week_start
  APPOINTMENT_INTERVAL = 30.minutes
  AVAILABILITY_WINDOW = 7.days

  def self.availabilities(start_date)
    [].tap do |availabilities|
      # cache all concerned events for the next 7 days
      # group events by days_to_week
      concerned_events = Event
        .where("starts_at <= ?", start_date.end_of_day + AVAILABILITY_WINDOW)
        .group_by(&:days_to_week)
      # since concerned_events grouped by days_to_week
      # To fetch the events for each day,
      # it should convert the date of day to the days_to_week
      start_days = start_date.days_to_week_start
      (0...AVAILABILITY_WINDOW / 1.day).each do |day_index|
        current_date = start_date + day_index
        current_days_to_week = (start_days + day_index) % 7
        events = concerned_events[current_days_to_week]
        availabilities << {
          date: current_date.to_date,
          slots: time_slots_from_mask(availabilities_for(current_date, events))
        }
      end
    end
  end

  # convert the representation of binary mask to time slots
  # ex. mask is 0b11001100000000000000000000000, bit_length 29
  # the starts_at is 24:00 - 29 * 00:30 = 9:30,
  # from left to right, the first 1 represents the slot 09:30
  # the second 1 represents the slot 10:00
  # the third 1 represents the slot 11:30 (= 10:00 + 3 * 00:30)
  # the fourth 1 represents the slot 12:00
  # so the output will be ["9:30", "10:00", "11:30", "12:00"]
  def self.time_slots_from_mask(mask)
    [].tap do |slots|
      left_padding_time = (1.day / APPOINTMENT_INTERVAL - mask.bit_length) * APPOINTMENT_INTERVAL
      mask.to_s(2).each_char.with_index do |char, index|
        slot_time = left_padding_time + index * APPOINTMENT_INTERVAL
        slot_hour = slot_time / 60.minutes
        slot_min = (slot_time - slot_hour * 60.minutes) / 1.minute
        if char == '1'
          slots << "#{slot_hour}:#{slot_min.to_s.rjust(2, '0')}"
        end
      end
    end
  end

  # Availabilities for a specific date, in the format of binary mask
  def self.availabilities_for(current_date, events)
    # fetch all opening events that impact on current_date
    # including the events with weekly_recurring &
    # without weekly_recurring (only the opening event happenning on current_date)
    opening_events = events&.find_all do |event|
      event.kind == 'opening' && (event.weekly_recurring || event.starts_at.to_date == current_date)
    end
    # opening_events is blank means that it's not necessary to do further calculation
    return 0 if opening_events.blank?
    appointment_events = events&.find_all { |event| event.kind == 'appointment' && event.starts_at.to_date == current_date }
    opening_mask = 0
    # the bitwise OR operator will gather all opening slots together
    # opening_mask would like be 0b11111100000000000000000000000
    # in the opening_mask, 0 means no availability, 1 means availability
    # each bit stands for an appointment interval (30 minutes).
    # we could infer the starts_at time according to the number of bit,
    # in this example, it takes 29 bits, so the starts_at time is 09:30 (= 24:00 - 29 * 00:30)
    # we count from the right ending, in this example,
    # there is 23 zeros on the right side,
    # it means that there is not availability for the last 11 hours 30 minutes (= 23 * 30 minutes) of the day,
    # the 6 ones on the left side, it means from 09:30 to 12:30 (= 09:30 + 6 * 00:30), it's availabile.
    # by using bitwise representation, it simplifies the problem, and it would be time effective.
    opening_events&.each do |event|
      opening_mask = opening_mask | event.send(:mask_for_time_slots)
    end
    appointment_mask = 0
    # the bitwise OR operator will gather all appointment slots together
    # for example, 0b110000000000000000000000000, bit_length 27
    # which means that there is already appointments
    # from 10:30 (= 24:00 - 27 * 00:30 ) to 11:30 (= 10:30 + 00:30 * 2)
    appointment_events&.each do |event|
      appointment_mask = appointment_mask | event.send(:mask_for_time_slots)
    end
    # Firstly, the bitwise AND between opening_mask and appointment_mask will eliminate the invalid bits from appointment_mask,
    # the invalid bits stands for the time slots which are not covered by opening_mask.
    # Ex. appointment_mask: 0b1111110000000000000000000000000, bit_length: 31
    #         opening_mask:   0b11111100000000000000000000000, bit_length: 29
    # The appointment_mask is larger than opening_mask,
    # which means the two leftmost bits of appointment_mask are definitly invalid.
    # With the bitwise AND operator, we can eliminate this kind of invalid bits.
    # appointment_mask & opening_mask
    # will let us get the valid appointment_mask 0b11110000000000000000000000000, bit_length: 29
    # Then by using the bitwise XOR operator between the valid appointment_mask and opening_mask.
    # the bitwise XOR operator will erase the '1' from opening_mask with the '1' of valid appointment_mask
    # and keep the '1' in opening_mask with the '0' of valid appointment_mask
    # In the example above, we get 0b1100000000000000000000000, bit_length: 29
    opening_mask & appointment_mask ^ opening_mask
  end

  private_class_method :availabilities_for, :time_slots_from_mask

  private

  def complete_days_to_week_start
    self.days_to_week = self.starts_at.days_to_week_start
  end

  # convert the event to binary mask
  # ex. opening from 09:30 to 12:30
  # would become 0b11111100000000000000000000000, bit_length 29
  def mask_for_time_slots
    offset = (ends_at.next_day.beginning_of_day - ends_at) / APPOINTMENT_INTERVAL
    slots_number = (ends_at - starts_at) / APPOINTMENT_INTERVAL
    ('1' * slots_number).to_i(2) << offset
  end
end
