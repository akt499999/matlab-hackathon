# main.py - "Choir on a breadboard": the Choir receiver idea on a Pico (MicroPython)
#
# Each LED plays back what one dish heard. All three send the same telemetry
# FRAME in Morse to ONE photoresistor, taking turns. A frame is:
#
#     sync pulse | spacecraft ID "C" | counter digit | payload "MATLAB" | checksum
#
# Each round a hidden fault hits some LEDs (chosen at random, not told to the
# receiver):
#   noisy     - one LED flickers, so its frame arrives garbled
#   corrupt   - one LED's payload has wrong letters (its checksum no longer matches)
#   lookalike - TWO LEDs carry a look-alike spacecraft's frame (its own valid
#               checksum, but ID "Q" and payload "DECOY")
#
# The receiver compares two strategies, like the MATLAB Choir results:
#   majority vote - trust what the LEDs AGREE on (the SUMPLE-style idea).
#                   A look-alike on 2 of 3 LEDs wins the vote.
#   Choir         - trust only frames that VERIFY: checksum OK, ID is "C", and the
#                   counter moves forward. A look-alike can't pass, so it's rejected.
# Only after both decisions does the transmitter reveal the truth.
#
# Wiring
#   LED 1:  GP15 (pin 20) -> 330 ohm -> LED long leg (+); short leg (-) -> GND
#   LED 2:  GP14 (pin 19) -> 330 ohm -> LED long leg (+); short leg (-) -> GND
#   LED 3:  GP13 (pin 17) -> 330 ohm -> LED long leg (+); short leg (-) -> GND
#   Photoresistor: 3V3 (pin 36) -> LDR -> GP26 (pin 31) -> 10k resistor -> GND
#
# Serial output (one line per event):
#   D,<t_ms>,<raw>,<filt>,<lo>,<hi>,<rx>,<tx>  one sample (STREAM); tx = LED command, for error measurement only
#   T,<led>                     LED <led> starts its turn
#   L,<char>                    a decoded character
#   C,<led>,<frame>,<timing>    decoded frame from one LED + its timing error (units)
#   V,<frame>,<leds>            majority vote and the LEDs that agreed on it
#   Q,<led>,<OK|reason>         Choir's checks on that LED's frame
#   A,<payload>,<frame>,<leds>  frame Choir accepted and logged ("-" = none verified, nothing logged)
#   W,<w1>,<w2>,<w3>            trust per LED, learned only from verified frames
#   R,<leds>,<fault>,<frame>    transmitter reveals the truth (after the decisions)
#   K,<majority result>,<choir result>   scoring: OK / WRONG / MISSED
#   S,<info>                    status (start, calibration, sync)
#
# The receiver never reads which LED is faulty or what the transmitter sent.

import time
import random
from machine import Pin, ADC

try:
    import asyncio
except ImportError:
    import uasyncio as asyncio

# ---------------- configuration ----------------
PAYLOAD = "MATLAB"        # telemetry payload (letters A-Z, digits 0-9)
SC_ID = "C"               # our spacecraft's ID
DECOY_ID = "Q"            # the look-alike spacecraft's ID
DECOY_PAYLOAD = "DECOY"   # what the look-alike sends
LED_PINS = [15, 14, 13]   # LED 1, LED 2, LED 3 (turn order)
LDR_PIN = 26              # GP26 = ADC0
UNIT_MS = 150             # Morse unit: dot = 1, dash = 3, gaps = 1 / 3 units
SAMPLE_MS = 10            # receiver sample period (100 Hz)
FAULT = "random"          # "noisy", "corrupt", "lookalike" or "random"
ONE_SHOT = False          # True: run one round, print the result, stop
STREAM = True             # print every sample (needed by morse_gui.py)
DEBUG = False             # print every measured pulse/gap length (E lines)

FILTER_ALPHA = 0.3        # exponential smoothing, 0..1 (lower = smoother, slower)
MIN_CONTRAST = 1500       # ADC counts between dark and lit needed to trust an LED
ENV_ATTACK = 0.02         # how fast the dark/lit trackers move outward
ENV_DECAY = 0.0005        # how fast the dark/lit trackers relax inward
GLITCH_UNITS = 0.3        # pulses or gaps shorter than this are ignored as flicker
SYNC_UNITS = 6            # long pulse that starts each LED's turn
SYNC_DETECT = 4.5         # on-pulses longer than this (in units) are sync pulses
END_UNITS = 5             # silence that ends one LED's frame (longer than a 3-unit letter gap)
SLOT_GAP_UNITS = 7        # silence the transmitter leaves after each frame
ROUND_UNITS = 10          # silence that ends a round (the receiver decides)
TRUST_RATE = 0.4          # how fast trust follows verified / failed frames
CAL_ROUNDS = 3            # calibration: off/on cycles per LED
CAL_SETTLE_MS = 300       # wait after switching an LED (photoresistors are slow)
CAL_MEASURE_MS = 300      # averaging window per measurement
INVERT = False            # set automatically if light makes the reading go DOWN

MORSE = {
    "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".", "F": "..-.",
    "G": "--.", "H": "....", "I": "..", "J": ".---", "K": "-.-", "L": ".-..",
    "M": "--", "N": "-.", "O": "---", "P": ".--.", "Q": "--.-", "R": ".-.",
    "S": "...", "T": "-", "U": "..-", "V": "...-", "W": ".--", "X": "-..-",
    "Y": "-.--", "Z": "--..",
    "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
    "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.",
}
DECODE = {code: ch for ch, code in MORSE.items()}
ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
LETTERS = ALPHABET[:26]
FAULTS = ("noisy", "corrupt", "lookalike")

tx_state = 0              # current LED command (reported in D lines for error measurement only)
decision = {}             # receiver's latest decisions (used only to score them after the reveal)


def rand_index(n):
    """Random integer 0..n-1 (getrandbits exists on every MicroPython build)."""
    return random.getrandbits(16) % n


# ---------------- frames ----------------
def checksum(body):
    """Our Morse stand-in for CRC-16: one character, catches any single wrong character."""
    return ALPHABET[sum(ALPHABET.index(c) for c in body) % len(ALPHABET)]


def make_frame(sc_id, counter, payload):
    body = sc_id + str(counter % 10) + payload
    return body + checksum(body)


# ---------------- transmitter (the LEDs) ----------------
def build_schedule(text):
    """Turn a frame into a list of (led_state, units)."""
    seq = []
    for li, ch in enumerate(c for c in text if c in MORSE):
        if li:
            seq.append((0, 3))                      # letter gap
        for ei, sym in enumerate(MORSE[ch]):
            if ei:
                seq.append((0, 1))                  # gap inside a letter
            seq.append((1, 1 if sym == "." else 3))
    return seq


def corrupt_frame(frame):
    """Change 1-2 payload letters but keep the old checksum (like bit errors on the air)."""
    chars = list(frame)
    spots = [i for i in range(2, len(chars) - 1) if chars[i] in LETTERS]
    for _ in range(1 + rand_index(2)):
        i = spots[rand_index(len(spots))]
        new = chars[i]
        while new == chars[i]:
            new = LETTERS[rand_index(26)]
        chars[i] = new
    return "".join(chars)


def add_noise(seq):
    """Flickers inside long pulses and gaps (a noisy dish)."""
    out = []
    for state, units in seq:
        if units >= 3 and rand_index(100) < 50:
            a = units / 2 - 0.5
            out += [(state, a), (1 - state, 1.0), (state, units - a - 1.0)]
        else:
            out.append((state, units))
    return out


async def transmitter():
    leds = [Pin(p, Pin.OUT, value=0) for p in LED_PINS]
    n_leds = len(leds)

    async def hold(led, state, units):
        global tx_state
        tx_state = state
        led.value(state)
        await asyncio.sleep_ms(int(units * UNIT_MS))

    await hold(leds[0], 0, 4)                       # short silence before the first round
    counter = 0
    while True:
        truth = make_frame(SC_ID, counter, PAYLOAD)
        fault = FAULT if FAULT in FAULTS else FAULTS[rand_index(len(FAULTS))]
        first = 1 + rand_index(n_leds)
        if fault == "lookalike":                    # two different LEDs carry the look-alike
            second = 1 + (first + rand_index(n_leds - 1)) % n_leds
            bad = sorted([first, second])
        else:
            bad = [first]
        decision.clear()

        for n, led in enumerate(leds, 1):
            frame = truth
            if n in bad and fault == "corrupt":
                frame = corrupt_frame(truth)
            elif n in bad and fault == "lookalike":
                frame = make_frame(DECOY_ID, counter, DECOY_PAYLOAD)
            seq = build_schedule(frame)
            if n in bad and fault == "noisy":
                seq = add_noise(seq)
            print("T,%d" % n)
            await hold(led, 1, SYNC_UNITS)          # sync: "LED n's turn starts"
            await hold(led, 0, 3)
            for state, units in seq:
                await hold(led, state, units)
            await hold(led, 0, SLOT_GAP_UNITS)
        # stay dark long enough for the receiver to decide first
        await hold(leds[0], 0, ROUND_UNITS + 4 - SLOT_GAP_UNITS)

        print("R,%s,%s,%s" % ("+".join(str(n) for n in bad), fault, truth))
        voted, accepted = decision.get("voted"), decision.get("accepted", "")
        maj = "OK" if voted == truth else "WRONG"
        choir = "OK" if accepted == truth else ("MISSED" if not accepted else "WRONG")
        print("K,%s,%s" % (maj, choir))
        counter += 1
        if ONE_SHOT:
            return


# ---------------- receiver: deciding what to trust ----------------
def majority(texts):
    """Frame most LEDs agree on: one shared by 2+ copies, else a character-by-character vote."""
    for t in texts:
        if texts.count(t) >= 2:
            return t
    out = ""
    for i in range(max(len(t) for t in texts)):
        votes = {}
        for t in texts:
            if i < len(t):
                votes[t[i]] = votes.get(t[i], 0) + 1
        out += max(votes, key=lambda c: votes[c])
    return out


def check_frame(text, last_counter):
    """Choir's three checks. Returns "OK" or why the frame is rejected."""
    if len(text) < 4:
        return "too short"
    if any(c not in ALPHABET for c in text):
        return "unreadable characters"
    if checksum(text[:-1]) != text[-1]:
        return "checksum failed"
    if text[0] != SC_ID:
        return "wrong spacecraft ID " + text[0]
    if not text[1].isdigit():
        return "no frame counter"
    if last_counter is not None:
        step = (int(text[1]) - last_counter) % 10
        if not 1 <= step <= 3:
            return "counter %s not after %d" % (text[1], last_counter)
    return "OK"


def decide(copies, state):
    """Both strategies on the same copies. state holds the counter and trust between rounds."""
    leds = list(range(1, len(LED_PINS) + 1))
    texts = [copies[n][0] for n in leds if n in copies]

    voted = majority(texts) if texts else ""
    agree = [n for n in leds if n in copies and copies[n][0] == voted]
    print("V,%s,%s" % (voted or "-", "+".join(str(n) for n in agree) or "-"))

    checks = {n: check_frame(copies[n][0], state["counter"]) if n in copies else "no frame received"
              for n in leds}
    for n in leds:
        print("Q,%d,%s" % (n, checks[n]))
    good = [n for n in leds if checks[n] == "OK"]
    if good:
        frame = copies[good[0]][0]
        state["counter"] = int(frame[1])
        print("A,%s,%s,%s" % (frame[2:-1], frame, "+".join(str(n) for n in good)))
    else:
        frame = ""
        print("A,-,-,none verified - nothing logged")

    for n in leds:                                  # trust learned only from verification
        ok = 1.0 if checks[n] == "OK" else 0.0
        state["trust"][n - 1] += TRUST_RATE * (ok - state["trust"][n - 1])
    print("W," + ",".join("%.2f" % w for w in state["trust"]))

    decision["voted"] = voted
    decision["accepted"] = frame


# ---------------- receiver (photoresistor) ----------------
async def receiver(cal):
    dark, lits = cal
    base_hi = min(lits)                 # dimmest LED: every LED's sync can cross the threshold
    adc = ADC(LDR_PIN)
    filt = read_light(adc)
    lo, hi = dark, base_hi
    state = 0
    t_edge = time.ticks_ms()
    symbol = ""                         # dots and dashes of the current character
    text = ""                           # decoded text of the current frame
    synced = False                      # inside an LED's turn
    slot = 0                            # whose turn it is (1..N), counted by sync pulses
    copies = {}                         # led -> (frame, timing error)
    memory = {"counter": None, "trust": [1.0] * len(LED_PINS)}
    dev_sum, dev_n = 0.0, 0             # timing error of the current frame
    on_sum, on_n = 0, 0                 # average level of the current "on" pulse
    next_t = time.ticks_ms()

    while True:
        t = time.ticks_ms()
        raw = read_light(adc)
        filt += FILTER_ALPHA * (raw - filt)
        hi += (filt - hi) * (ENV_ATTACK if filt > hi else ENV_DECAY)
        lo += (filt - lo) * (ENV_ATTACK if filt < lo else ENV_DECAY)
        contrast = hi - lo

        # On/off decision with hysteresis (60% to turn on, 40% to turn off)
        new = state
        if contrast < MIN_CONTRAST:
            new = 0
        else:
            frac = (filt - lo) / contrast
            if state == 0 and frac > 0.6:
                new = 1
            elif state == 1 and frac < 0.4:
                new = 0
        if state:
            on_sum += filt
            on_n += 1

        if new != state:
            units = time.ticks_diff(t, t_edge) / UNIT_MS
            t_edge = t
            if DEBUG:
                print("E,%s,%.2f units,lo=%d,hi=%d" % ("on" if state else "off", units, lo, hi))
            if state == 1 and units >= GLITCH_UNITS:        # an "on" pulse just ended
                if units > SYNC_DETECT:                     # sync: the next LED's turn
                    slot += 1
                    symbol, text, synced = "", "", True
                    dev_sum, dev_n = 0.0, 0
                    if on_n:
                        hi = on_sum / on_n                  # this LED's own brightness
                    print("S,SYNC,%d" % slot)
                elif synced:
                    symbol += "." if units < 2 else "-"
                    dev_sum += min(abs(units - 1), abs(units - 3))
                    dev_n += 1
            elif state == 0 and synced and units >= GLITCH_UNITS and (symbol or text):
                dev_sum += min(abs(units - 1), abs(units - 3))
                dev_n += 1                                  # a gap inside the frame ended
            if new == 1:
                on_sum, on_n = 0, 0
            state = new
        elif state == 0:                                    # still dark: check gap length
            units = time.ticks_diff(t, t_edge) / UNIT_MS
            if symbol and units > 2:                        # character finished
                ch = DECODE.get(symbol, "?")
                text += ch
                symbol = ""
                print("L," + ch)
            if synced and units > END_UNITS:                # this LED's frame finished
                timing = dev_sum / dev_n if dev_n else 0.0
                copies[slot] = (text, timing)
                print("C,%d,%s,%.2f" % (slot, text or "-", timing))
                text, symbol, synced = "", "", False
                hi = base_hi                                # ready for the next (maybe dimmer) LED
            if slot and units > ROUND_UNITS:                # round finished: decide
                decide(copies, memory)
                copies, slot = {}, 0

        if STREAM:
            # tx_state is only reported for error measurement; decoding above never uses it
            print("D,%d,%d,%d,%d,%d,%d,%d" % (t, raw, int(filt), int(lo), int(hi), state, tx_state))

        next_t = time.ticks_add(next_t, SAMPLE_MS)
        await asyncio.sleep_ms(max(0, time.ticks_diff(next_t, time.ticks_ms())))


# ---------------- calibration ----------------
def read_light(adc):
    """ADC reading where higher always means brighter."""
    raw = adc.read_u16()
    return 65535 - raw if INVERT else raw


def average(adc, ms):
    total, n = 0, 0
    end = time.ticks_add(time.ticks_ms(), ms)
    while time.ticks_diff(end, time.ticks_ms()) > 0:
        total += adc.read_u16()
        n += 1
        time.sleep_ms(5)
    return total // n


def calibrate():
    """Blink each LED alone a few times. Blocks until every LED is clearly seen,
    then returns (dark level, [lit level of each LED])."""
    global INVERT
    leds = [Pin(p, Pin.OUT, value=0) for p in LED_PINS]
    adc = ADC(LDR_PIN)
    while True:
        darks, lits, diffs = [], [], []
        for led in leds:
            lit, d_led = 0, []
            for _ in range(CAL_ROUNDS):
                led.off()
                time.sleep_ms(CAL_SETTLE_MS)
                d = average(adc, CAL_MEASURE_MS)
                led.on()
                time.sleep_ms(CAL_SETTLE_MS)
                l = average(adc, CAL_MEASURE_MS)
                darks.append(d)
                lit += l
                d_led.append(l - d)
            led.off()
            lits.append(lit // CAL_ROUNDS)
            diffs.append(d_led)
        dark = sum(darks) // len(darks)
        for n, (lit, d_led) in enumerate(zip(lits, diffs), 1):
            print("S,CAL,LED%d,dark=%d,lit=%d,round_diffs=%s" % (n, dark, lit, d_led))

        # Every round of every LED must agree; one shadow can't pass.
        if all(x >= MIN_CONTRAST for d_led in diffs for x in d_led):
            INVERT = False
            return dark, lits
        if all(x <= -MIN_CONTRAST for d_led in diffs for x in d_led):
            INVERT = True                   # sensor wired the other way: flip readings
            print("S,CAL,inverted wiring detected, flipping readings")
            return 65535 - dark, [65535 - l for l in lits]
        unseen = [n for n, d_led in enumerate(diffs, 1)
                  if not all(abs(x) >= MIN_CONTRAST for x in d_led)]
        print("S,NO_LIGHT,LED(s) %s not reaching the sensor (pins %s). Check the LED "
              "direction and wiring, point it at the photoresistor, block room light."
              % (unseen, [LED_PINS[n - 1] for n in unseen]))
        time.sleep_ms(1000)


# ---------------- main ----------------
async def main(cal):
    print("S,START,leds=%d,unit_ms=%d,id=%s" % (len(LED_PINS), UNIT_MS, SC_ID))
    tx = asyncio.create_task(transmitter())
    asyncio.create_task(receiver(cal))
    if ONE_SHOT:
        await tx
        return
    while True:
        await asyncio.sleep(10)


asyncio.run(main(calibrate()))
