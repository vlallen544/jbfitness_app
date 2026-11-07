import assert from "node:assert/strict";
import { test } from "node:test";
import { oneCalendarMonthAfter } from "../src/membership-policy";
test("calendar-month boundaries clamp shorter months without changing time", () => {
  for (const [from, to] of [
    ["2027-01-31T13:45:30.000Z", "2027-02-28T13:45:30.000Z"],
    ["2028-01-31T13:45:30.000Z", "2028-02-29T13:45:30.000Z"],
    ["2026-12-15T10:00:00.000Z", "2027-01-15T10:00:00.000Z"],
    ["2026-03-31T10:00:00.000Z", "2026-04-30T10:00:00.000Z"],
  ]) {
    const date = new Date(from);
    assert.equal(oneCalendarMonthAfter(date).toISOString(), to);
    assert.equal(date.toISOString(), from);
  }
  assert.throws(() => oneCalendarMonthAfter(new Date("invalid")));
});
