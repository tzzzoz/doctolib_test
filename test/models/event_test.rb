require 'test_helper'
require 'benchmark'

class EventTest < ActiveSupport::TestCase
  setup do
    @opening_event = Event.create kind: 'opening',
      starts_at: DateTime.parse("2014-08-04 09:30"),
      ends_at: DateTime.parse("2014-08-04 12:30"),
      weekly_recurring: true
    @appointment_event = Event.create kind: 'appointment',
      starts_at: DateTime.parse("2014-08-11 10:30"),
      ends_at: DateTime.parse("2014-08-11 11:30")
  end

  teardown do
    Event.destroy_all
  end

  # 1. Opening event with weekly_recurring
  test "one simple test example" do
    availabilities = Event.availabilities DateTime.parse("2014-08-10")
    assert_equal Date.new(2014, 8, 10), availabilities[0][:date]
    assert_equal [], availabilities[0][:slots]
    assert_equal Date.new(2014, 8, 11), availabilities[1][:date]
    assert_equal ["9:30", "10:00", "11:30", "12:00"], availabilities[1][:slots]
    assert_equal [], availabilities[2][:slots]
    assert_equal Date.new(2014, 8, 16), availabilities[6][:date]
    assert_equal 7, availabilities.length
  end

  test "start date of input is more than 7 days before the earliest opening event" do
    availabilities = Event.availabilities DateTime.parse("2014-07-20")
    assert_equal Date.new(2014, 7, 20), availabilities[0][:date]
    assert_equal [], availabilities[0][:slots]
    assert_equal Date.new(2014, 7, 21), availabilities[1][:date]
    assert_equal [], availabilities[1][:slots]
    assert_equal [], availabilities[2][:slots]
    assert_equal Date.new(2014, 7, 26), availabilities[6][:date]
    assert_equal 7, availabilities.length
  end

  test "start date of input is less than 7 days before the earliest opening event" do
    availabilities = Event.availabilities DateTime.parse("2014-07-29")
    assert_equal Date.new(2014, 7, 29), availabilities[0][:date]
    assert_equal [], availabilities[0][:slots]
    assert_equal Date.new(2014, 7, 30), availabilities[1][:date]
    assert_equal [], availabilities[1][:slots]
    assert_equal [], availabilities[2][:slots]
    assert_equal Date.new(2014, 8, 04), availabilities[6][:date]
    assert_equal ["9:30", "10:00", "10:30", "11:00", "11:30", "12:00"], availabilities[6][:slots]
    assert_equal 7, availabilities.length
  end

  test "start date of input is more than 7 days behind the opening event" do
    availabilities = Event.availabilities DateTime.parse("2014-08-20")
    assert_equal Date.new(2014, 8, 20), availabilities[0][:date]
    assert_equal [], availabilities[0][:slots]
    assert_equal Date.new(2014, 8, 21), availabilities[1][:date]
    assert_equal [], availabilities[1][:slots]
    assert_equal [], availabilities[2][:slots]
    assert_equal Date.new(2014, 8, 25), availabilities[5][:date]
    assert_equal ["9:30", "10:00", "10:30", "11:00", "11:30", "12:00"], availabilities[5][:slots]
    assert_equal 7, availabilities.length
  end

  test "opening period is fully filled by appointments (w/ weekly_recurring)" do
    Event.create kind: 'appointment',
      starts_at: DateTime.parse("2014-08-11 09:30"),
      ends_at: DateTime.parse("2014-08-11 10:30")
    Event.create kind: 'appointment',
      starts_at: DateTime.parse("2014-08-11 11:30"),
      ends_at: DateTime.parse("2014-08-11 12:30")

    availabilities = Event.availabilities DateTime.parse("2014-08-10")
    assert_equal Date.new(2014, 8, 10), availabilities[0][:date]
    assert_equal [], availabilities[0][:slots]
    assert_equal Date.new(2014, 8, 11), availabilities[1][:date]
    assert_equal [], availabilities[1][:slots]
    assert_equal Date.new(2014, 8, 16), availabilities[6][:date]
    assert_equal 7, availabilities.length
  end

  # 2. Abnormal cases: opening period doesn't totally cover appointment period
  # 2.1 partially overlap
  test "appointment's starts_at time is earlier than the opening event's starts_at time" do
    Event.create kind: 'appointment',
      starts_at: DateTime.parse("2014-08-11 08:30"),
      ends_at: DateTime.parse("2014-08-11 10:00")

    availabilities = Event.availabilities DateTime.parse("2014-08-10")
    assert_equal Date.new(2014, 8, 10), availabilities[0][:date]
    assert_equal [], availabilities[0][:slots]
    assert_equal Date.new(2014, 8, 11), availabilities[1][:date]
    assert_equal ["10:00", "11:30", "12:00"], availabilities[1][:slots]
    assert_equal Date.new(2014, 8, 16), availabilities[6][:date]
    assert_equal 7, availabilities.length
  end

  # 2.2-1 do not overlap at all
  test "appointment's ends_at time is earlier than the opening event's starts_at time" do
    Event.create kind: 'appointment',
      starts_at: DateTime.parse("2014-08-11 08:30"),
      ends_at: DateTime.parse("2014-08-11 09:00")

    availabilities = Event.availabilities DateTime.parse("2014-08-10")
    assert_equal Date.new(2014, 8, 10), availabilities[0][:date]
    assert_equal [], availabilities[0][:slots]
    assert_equal Date.new(2014, 8, 11), availabilities[1][:date]
    assert_equal ["9:30", "10:00", "11:30", "12:00"], availabilities[1][:slots]
    assert_equal Date.new(2014, 8, 16), availabilities[6][:date]
    assert_equal 7, availabilities.length
  end

  # 2.2-2 do not overlap at all
  test "appointment's starts_at time is later than the opening event's ends_at time" do
    Event.create kind: 'appointment',
      starts_at: DateTime.parse("2014-08-11 14:30"),
      ends_at: DateTime.parse("2014-08-11 15:00")

    availabilities = Event.availabilities DateTime.parse("2014-08-10")
    assert_equal Date.new(2014, 8, 10), availabilities[0][:date]
    assert_equal [], availabilities[0][:slots]
    assert_equal Date.new(2014, 8, 11), availabilities[1][:date]
    assert_equal ["9:30", "10:00", "11:30", "12:00"], availabilities[1][:slots]
    assert_equal Date.new(2014, 8, 16), availabilities[6][:date]
    assert_equal 7, availabilities.length
  end

  # 3. Opening event without weekly_recurring, to make sure the weekly_recurring option is taken into account
  test "opening period doesn't overlap with appointment event at all (w/o weekly_recurring)" do
    @opening_event.update(weekly_recurring: false)

    availabilities = Event.availabilities DateTime.parse("2014-08-10")
    assert_equal Date.new(2014, 8, 10), availabilities[0][:date]
    assert_equal [], availabilities[0][:slots]
    assert_equal Date.new(2014, 8, 11), availabilities[1][:date]
    assert_equal [], availabilities[1][:slots]
    assert_equal Date.new(2014, 8, 16), availabilities[6][:date]
    assert_equal 7, availabilities.length
  end

  test "opening period covers appointment period (w/o weekly_recurring)" do
    @opening_event.update(weekly_recurring: false)
    @appointment_event.update(
      starts_at: DateTime.parse("2014-08-04 10:00"),
      ends_at: DateTime.parse("2014-08-04 11:30")
    )

    availabilities = Event.availabilities DateTime.parse("2014-08-03")
    assert_equal Date.new(2014, 8, 3), availabilities[0][:date]
    assert_equal [], availabilities[0][:slots]
    assert_equal Date.new(2014, 8, 4), availabilities[1][:date]
    assert_equal ["9:30", "11:30", "12:00"], availabilities[1][:slots]
    assert_equal Date.new(2014, 8, 9), availabilities[6][:date]
    assert_equal 7, availabilities.length
  end

  test "opening period is fully filled by appointments (w/o weekly_recurring)" do
    @opening_event.update(weekly_recurring: false)
    Event.create kind: 'appointment',
      starts_at: DateTime.parse("2014-08-04 09:30"),
      ends_at: DateTime.parse("2014-08-04 11:30")
    Event.create kind: 'appointment',
      starts_at: DateTime.parse("2014-08-04 11:30"),
      ends_at: DateTime.parse("2014-08-04 12:30")

    availabilities = Event.availabilities DateTime.parse("2014-08-03")
    assert_equal Date.new(2014, 8, 3), availabilities[0][:date]
    assert_equal [], availabilities[0][:slots]
    assert_equal Date.new(2014, 8, 4), availabilities[1][:date]
    assert_equal [], availabilities[1][:slots]
    assert_equal Date.new(2014, 8, 9), availabilities[6][:date]
    assert_equal 7, availabilities.length
  end

  # 4. More complicated case
  test "mixing opening events (w/ weekly_recurring and w/o weekly_recurring) and valid appointment events" do
    Event.create kind: 'opening',
      starts_at: DateTime.parse("2014-09-08 14:00"),
      ends_at: DateTime.parse("2014-09-08 16:30"),
      weekly_recurring: false
    Event.create kind: 'opening',
      starts_at: DateTime.parse("2014-09-09 10:00"),
      ends_at: DateTime.parse("2014-09-09 12:00"),
      weekly_recurring: true
    Event.create kind: 'appointment',
      starts_at: DateTime.parse("2014-09-08 15:30"),
      ends_at: DateTime.parse("2014-09-08 16:00")

    availabilities = Event.availabilities DateTime.parse("2014-09-07")
    assert_equal Date.new(2014, 9, 7), availabilities[0][:date]
    assert_equal [], availabilities[0][:slots]
    assert_equal Date.new(2014, 9, 8), availabilities[1][:date]
    assert_equal ["9:30", "10:00", "10:30", "11:00", "11:30", "12:00",
                  "14:00", "14:30", "15:00", "16:00"], availabilities[1][:slots]
    assert_equal Date.new(2014, 9, 9), availabilities[2][:date]
    assert_equal ["10:00", "10:30", "11:00", "11:30"], availabilities[2][:slots]
    assert_equal 7, availabilities.length
  end

  # 5. Benchmark test
  test "benchmark on Event.availabilities" do
    Event.create kind: 'opening',
      starts_at: DateTime.parse("2014-09-08 14:00"),
      ends_at: DateTime.parse("2014-09-08 16:30"),
      weekly_recurring: false
    Event.create kind: 'opening',
      starts_at: DateTime.parse("2014-09-09 10:00"),
      ends_at: DateTime.parse("2014-09-09 12:00"),
      weekly_recurring: true
    Event.create kind: 'appointment',
      starts_at: DateTime.parse("2014-09-08 15:30"),
      ends_at: DateTime.parse("2014-09-08 16:00")

    benchmark_result = Benchmark.measure {
      1000.times do
        availabilities = Event.availabilities DateTime.parse("2014-09-07")
      end
    }
    puts
    puts "Benckmark result(1000 times):"
    puts benchmark_result
    assert_operator benchmark_result.real, :<, 30
  end

  # 6. Tests for support helper methods
  # 6.1 Tests for Event private instance method :mask_for_time_slots
  test "mask_for_time_slots returns the correct binary_mask for an event" do
    # @opening_event starts_at: "2014-08-04 09:30", ends_at "2014-08-04 12:30"
    binary_mask = @opening_event.send(:mask_for_time_slots)

    assert_equal 24 * 2 - (9 * 2 + 1), binary_mask.bit_length
    assert_equal 0b11111100000000000000000000000, binary_mask
  end

  # 6.2 Tests for Event private class method :time_slots_from_mask
  test "time_slots_from_mask converts correctly the binary_mask to time slots" do
    binary_mask = 0b11001100000000000000000000000
    time_slots = Event.send(:time_slots_from_mask, binary_mask)

    assert_equal ["9:30", "10:00", "11:30", "12:00"], time_slots
  end
end
