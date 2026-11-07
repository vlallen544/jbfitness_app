import assert from "node:assert/strict";
import { test } from "node:test";
import { plans } from "../src/plans";
test("catalogue matches client prices and total session allowances", () => {
  assert.deepEqual(
    plans.map(({ priceInPaise, durationMonths, videoSessions }) => [
      priceInPaise,
      durationMonths,
      videoSessions,
    ]),
    [
      [300000, 1, 0],
      [1000000, 1, 10],
      [2000000, 1, 25],
    ],
  );
  assert.equal(new Set(plans.map(({ id }) => id)).size, 3);
});
