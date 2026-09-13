/* Regression tests run against the production distance and speed helpers.
 * cc -std=c11 -Wall -Wextra -Werror tests/movement.c -lm -o /tmp/ss-movement
 * /tmp/ss-movement
 */
#include "../SSMovement.h"
#include <assert.h>
#include <stdio.h>

static void near(double a, double b) { assert(fabs(a - b) < 1e-6); }

static int feed(SSMovement *movement, double distance, int samples,
                double speed, bool words) {
    int result = 0;
    for (int i = 0; i < samples; i++)
        result += SSTakeMovementSteps(movement, distance / samples, speed, words);
    return result;
}

static void check_sampling(double speed, bool words) {
    // Equal drags with high-frequency movement events and coalesced selection
    // events must end at the same cursor step, including direction changes.
    const double path[] = {73.75, 151.40, -88.30, -137.25, 67.83};
    SSMovement frequent, combined;
    SSResetMovement(&frequent);
    SSResetMovement(&combined);
    int a = 0, b = 0;
    for (unsigned i = 0; i < sizeof(path) / sizeof(path[0]); i++) {
        a += feed(&frequent, path[i], 401, speed, words);
        b += feed(&combined, path[i], 3, speed, words);
        assert(a == b);
        near(frequent.remainder, combined.remainder);
    }
}

int main(void) {
    for (int hundredths = 10; hundredths <= 200; hundredths++) {
        double speed = hundredths / 100.0, decoded = 0;
        assert(SSDecodeSpeed(SSEncodeSpeed(speed), &decoded));
        near(decoded, speed);
        check_sampling(speed, false);
        check_sampling(speed, true);
    }
    double ignored;
    assert(!SSDecodeSpeed(0, &ignored));
    assert(!SSDecodeSpeed(100, &ignored));
    assert(!SSDecodeSpeed(UINT64_C(0x5353504400000009), &ignored));
    assert(!SSDecodeSpeed(UINT64_C(0x53535044000000c9), &ignored));
    assert(!SSDecodeSpeed(UINT64_C(0x1234567800000064), &ignored));
    near(SSNormalizeSpeed(NAN), 1.0);
    near(SSNormalizeSpeed(INFINITY), 1.0);
    near(SSNormalizeSpeed(-INFINITY), 1.0);
    near(SSNormalizeSpeed(0), .1);
    near(SSNormalizeSpeed(5), 2.0);
    near(SSNormalizeSpeed(1.234), 1.23);

    const double speeds[] = {.1, .5, 1, 2};
    const int characters[] = {2, 10, 20, 40};
    for (int i = 0; i < 4; i++) {
        SSMovement movement;
        SSResetMovement(&movement);
        assert(feed(&movement, 200, 1000, speeds[i], false) == characters[i]);
        near(movement.remainder, 0);
        SSResetMovement(&movement);
        assert(feed(&movement, -200, 7, speeds[i], false) == -characters[i]);
        SSResetMovement(&movement);
        assert(feed(&movement, 200, 19, speeds[i], true) == characters[i] / 2);
    }
    SSMovement movement;
    SSResetMovement(&movement);
    assert(SSTakeMovementSteps(&movement, 9, 1, false) == 0);
    assert(SSTakeMovementSteps(&movement, 1, 1, false) == 1);
    assert(SSTakeMovementSteps(&movement, -10, 1, false) == -1);
    assert(SSTakeMovementSteps(&movement, 9, 1, false) == 0);
    // Changing granularity must not convert leftover character distance into
    // an unexpected word jump (or vice versa).
    assert(SSTakeMovementSteps(&movement, 12, 1, true) == 0);
    assert(SSTakeMovementSteps(&movement, 8, 1, true) == 1);
    assert(SSTakeMovementSteps(&movement, 19, 1, true) == 0);
    assert(SSTakeMovementSteps(&movement, 1, 1, false) == 0);
    near(movement.remainder, 1);
    assert(SSTakeMovementSteps(&movement, NAN, 1, false) == 0);
    assert(SSTakeMovementSteps(&movement, INFINITY, 1, false) == 0);
    near(movement.remainder, 1);
    assert(SSTakeMovementSteps(&movement, 1e100, 2, false) == SS_MAX_STEPS_PER_EVENT);
    near(movement.remainder, 0);
    assert(SSTakeMovementSteps(&movement, -1e100, 2, false) == -SS_MAX_STEPS_PER_EVENT);
    SSResetMovement(&movement);
    assert(SSTakeMovementSteps(&movement, 1, 1, false) == 0);
    puts("PASS: all 191 speeds, event coalescing, reversals, word mode, bounds, and transport encoding");
    return 0;
}
