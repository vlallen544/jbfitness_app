import assert from "node:assert/strict";
import { test } from "node:test";
import { byteRange } from "../src/exercise-media";
import { addDays, isoDay, mondayOf } from "../src/workout-schema";
test("workout dates remain calendar dates across leap days and week boundaries", () => {
  assert.equal(isoDay.safeParse("2026-02-30").success, false);
  assert.equal(isoDay.safeParse("2028-02-29").success, true);
  assert.equal(mondayOf("2026-11-08"), "2026-11-02");
  assert.equal(addDays("2028-02-28", 1), "2028-02-29");
  assert.equal(addDays("2026-12-31", 1), "2027-01-01");
});
test("stream ranges clamp valid requests and reject invalid or multi-range inputs", () => {
  assert.deepEqual(byteRange(undefined, 100), { start: 0, end: 99 });
  assert.deepEqual(byteRange("bytes=90-999", 100), { start: 90, end: 99 });
  assert.deepEqual(byteRange("bytes=-500", 100), { start: 0, end: 99 });
  for (const header of [
    "bytes=-0",
    "bytes=8-4",
    "bytes=100-",
    "bytes=0-1,3-4",
    "bytes=1.5-2",
    "bytes=-",
  ])
    assert.equal(byteRange(header, 100), null);
  assert.equal(byteRange(undefined, 0), null);
});
