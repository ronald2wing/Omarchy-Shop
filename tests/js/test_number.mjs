// js/number.mjs: the finite-number test and the rounding to cents.
import assert from "node:assert/strict"
import * as N from "../../js/number.mjs"

assert.deepEqual([1, 0, -2.5, NaN, Infinity, "1", null].map(N.isNum), [true, true, true, false, false, false, false])
assert.deepEqual([N.cents(4.095), N.cents(1.004), N.cents(-2.5), N.cents(0.1 + 0.2)], [4.1, 1, -2.5, 0.3])
