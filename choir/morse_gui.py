"""morse_gui.py - live Pygame view of the Pico multi-LED Morse link.

Plots the photoresistor signal as it arrives, shows each LED's decoded copy,
the majority vote, which LED the receiver flagged as bad, and - once the Pico
reveals it - whether the receiver was right.

Setup (on the laptop):
    pip install pygame pyserial numpy

Run:
    1. Save "MatLab Hackathon.py" onto the Pico as main.py (STREAM = True).
    2. Close Thonny - only one program can use the Pico's USB port at a time.
    3. python morse_gui.py          (finds the Pico automatically)
       python morse_gui.py COM5     (or name the port)

Keys:  R = restart the Pico (recalibrates)   C = clear statistics   Esc = quit
"""

import sys
import time
import queue
import threading
from collections import deque

import numpy as np
import pygame
import serial
from serial.tools import list_ports

BAUD = 115200
SAMPLE_HZ = 100                 # matches SAMPLE_MS = 10 on the Pico
WINDOW_S = 10                   # seconds of signal on screen
WIN = WINDOW_S * SAMPLE_HZ
ON_FRAC, OFF_FRAC = 0.6, 0.4    # matches the Pico's hysteresis
MAX_LAG = 60                    # samples (600 ms) searched when lining RX up with TX
W, H = 1320, 780
PANEL_W = 460

BG = (18, 20, 26)
GRID = (45, 50, 60)
TEXT = (220, 224, 232)
DIM = (130, 136, 150)
RAW_C = (110, 110, 120)
FILT_C = (80, 160, 255)
ON_C = (90, 200, 120)
OFF_C = (240, 160, 60)
TX_C = (90, 200, 120)
RX_C = (80, 160, 255)
ERR_C = (230, 70, 70)
OK_C = (90, 200, 120)
WAIT_C = (200, 180, 90)


# ---------------- serial ----------------
def find_port():
    ports = list(list_ports.comports())
    for p in ports:
        if p.vid == 0x2E8A:             # Raspberry Pi (Pico) USB vendor ID
            return p.device
    return ports[-1].device if ports else None


def reader(ser, lines, stop):
    """Background thread: push every line from the Pico into a queue."""
    while not stop.is_set():
        try:
            raw = ser.readline()
        except (serial.SerialException, OSError, TypeError):
            if not stop.is_set():               # TypeError = port closed mid-read on exit
                lines.put("X,serial port disconnected")
            return
        if raw:
            lines.put(raw.decode(errors="ignore").strip())


# ---------------- metrics ----------------
def edit_distance(a, b):
    """Levenshtein distance: insertions + deletions + substitutions."""
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


class Link:
    """Everything received from the Pico, plus signal and detection statistics."""

    def __init__(self):
        self.t = deque(maxlen=WIN)
        self.raw = deque(maxlen=WIN)
        self.filt = deque(maxlen=WIN)
        self.lo = deque(maxlen=WIN)
        self.hi = deque(maxlen=WIN)
        self.rx = deque(maxlen=WIN)
        self.tx = deque(maxlen=WIN)
        self.status = "waiting for the Pico..."
        self.n_leds = 3
        self.cal = {}                   # "LED1" -> "lit=..., diff ..."
        self.lag = 0                    # samples between TX command and RX decision
        self.win_err = None             # aligned sample error over the window
        self.new_round()
        self.reset_stats()

    def new_round(self):
        self.active = 0                 # LED whose turn it is
        self.rx_live = ""
        self.copies = {}                # led -> (frame, timing error)
        self.voted = None               # (frame, agreeing LEDs)
        self.checks = {}                # led -> "OK" or reason
        self.accepted = None            # (payload, frame, LEDs)
        self.reveal = None              # (bad LEDs, fault, true frame)
        self.result = None              # (majority result, choir result)

    def reset_stats(self):
        self.compared = 0
        self.errors = 0
        self.rounds = []                # (fault, bad LEDs, majority result, choir result)
        self.trust = [1.0] * self.n_leds

    def handle(self, line):
        p = line.split(",")
        kind = p[0]
        try:
            if kind == "D" and len(p) >= 8:
                self.add_sample(*(int(x) for x in p[1:8]))
            elif kind == "T":
                led = int(p[1])
                if led == 1:
                    self.new_round()
                self.active = led
                self.rx_live = ""
            elif kind == "L" and len(p) > 1:
                self.rx_live += p[1]
            elif kind == "C" and len(p) >= 4:
                self.copies[int(p[1])] = (",".join(p[2:-1]), float(p[-1]))
                self.rx_live = ""
            elif kind == "V" and len(p) >= 3:
                self.voted = (p[1], p[2])
                self.active = 0
            elif kind == "Q" and len(p) >= 3:
                self.checks[int(p[1])] = ",".join(p[2:])
            elif kind == "A" and len(p) >= 4:
                self.accepted = (p[1], p[2], ",".join(p[3:]))
            elif kind == "W":
                self.trust = [float(x) for x in p[1:]]
            elif kind == "R" and len(p) >= 4:
                self.reveal = (p[1], p[2], p[3])
            elif kind == "K" and len(p) >= 3:
                self.result = (p[1], p[2])
                if self.reveal:
                    self.rounds.append((self.reveal[1], self.reveal[0], p[1], p[2]))
            elif kind == "S" and len(p) > 1:
                self.status = ", ".join(p[1:])
                if p[1] == "START":
                    for kv in p[2:]:
                        if kv.startswith("leds="):
                            self.n_leds = int(kv[5:])
                elif p[1] == "CAL" and len(p) > 2 and p[2].startswith("LED"):
                    lit = next((kv for kv in p[3:] if kv.startswith("lit=")), "")
                    self.cal[p[2]] = lit
            elif kind == "X":
                self.status = p[1]
        except (ValueError, IndexError):
            pass                                    # half a line at startup: ignore

    def add_sample(self, t, raw, filt, lo, hi, rx, tx):
        for buf, v in ((self.t, t), (self.raw, raw), (self.filt, filt), (self.lo, lo),
                       (self.hi, hi), (self.rx, rx), (self.tx, tx)):
            buf.append(v)
        # running sample error, RX compared with TX from `lag` samples earlier
        if len(self.tx) > self.lag:
            self.compared += 1
            self.errors += rx != self.tx[-1 - self.lag]

    def update_lag(self):
        """Find the shift that best lines RX up with TX (the sensor's delay)."""
        if len(self.tx) < 2 * MAX_LAG:
            return
        tx = np.array(self.tx, dtype=np.int8)
        rx = np.array(self.rx, dtype=np.int8)
        if tx.sum() == 0:
            return
        errs = [np.mean(rx[s:] != tx[:len(tx) - s]) for s in range(MAX_LAG + 1)]
        self.lag = int(np.argmin(errs))
        self.win_err = float(errs[self.lag])


# ---------------- drawing ----------------
def draw_series(surf, rect, values, ymin, ymax, color, width=1):
    n = len(values)
    if n < 2:
        return
    dx = rect.w / (WIN - 1)
    x0 = rect.right - (n - 1) * dx
    span = (ymax - ymin) or 1
    pts = [(x0 + i * dx, rect.bottom - (v - ymin) / span * rect.h) for i, v in enumerate(values)]
    pygame.draw.lines(surf, color, False, pts, width)


def draw_frame(surf, rect, title, font):
    pygame.draw.rect(surf, GRID, rect, 1)
    for k in range(1, WINDOW_S):
        x = rect.x + rect.w * k / WINDOW_S
        pygame.draw.line(surf, GRID, (x, rect.y), (x, rect.bottom))
    surf.blit(font.render(title, True, TEXT), (rect.x, rect.y - 22))


def legend(surf, x, y, items, font):
    for label, color in items:
        pygame.draw.line(surf, color, (x, y + 8), (x + 18, y + 8), 3)
        img = font.render(label, True, DIM)
        surf.blit(img, (x + 24, y))
        x += 24 + img.get_width() + 18


def draw_plots(screen, link, small, mid):
    plot_w = W - PANEL_W - 60

    # --- plot 1: analog signal ---
    r1 = pygame.Rect(30, 40, plot_w, 300)
    draw_frame(screen, r1, "Photoresistor signal (last %d s)" % WINDOW_S, mid)
    if link.raw:
        lo, hi = np.array(link.lo), np.array(link.hi)
        ymax = max(max(link.raw), max(link.hi), 1000) * 1.08
        draw_series(screen, r1, link.raw, 0, ymax, RAW_C)
        draw_series(screen, r1, list(lo + ON_FRAC * (hi - lo)), 0, ymax, ON_C, 2)
        draw_series(screen, r1, list(lo + OFF_FRAC * (hi - lo)), 0, ymax, OFF_C, 2)
        draw_series(screen, r1, link.filt, 0, ymax, FILT_C, 2)
    legend(screen, r1.x, r1.bottom + 6, [("raw", RAW_C), ("filtered", FILT_C),
                                          ("on threshold", ON_C), ("off threshold", OFF_C)], small)

    # --- plot 2: LED command vs receiver decision, mismatches shaded ---
    r2 = pygame.Rect(30, 410, plot_w, 230)
    draw_frame(screen, r2, "LED command vs receiver decision (RX shifted back %d ms)"
               % (link.lag * 1000 // SAMPLE_HZ), mid)
    n = len(link.tx)
    if n > link.lag + 1:
        tx = np.array(link.tx)
        rx = np.array(link.rx)
        lag = link.lag
        tx_al, rx_al = tx[:n - lag], rx[lag:]
        dx = r2.w / (WIN - 1)
        x0 = r2.right - (n - 1) * dx
        for i in np.nonzero(tx_al != rx_al)[0]:
            x = x0 + i * dx
            pygame.draw.line(screen, ERR_C, (x, r2.y + 1), (x, r2.bottom - 1), max(1, int(dx) + 1))
        top = pygame.Rect(r2.x, r2.y + 15, r2.w, r2.h // 2 - 30)
        bot = pygame.Rect(r2.x, r2.y + r2.h // 2 + 15, r2.w, r2.h // 2 - 30)
        draw_series(screen, top, list(tx_al), 0, 1, TX_C, 2)
        draw_series(screen, bot, list(rx_al), 0, 1, RX_C, 2)
    screen.blit(small.render("TX", True, TX_C), (r2.x + 4, r2.y + 4))
    screen.blit(small.render("RX", True, RX_C), (r2.x + 4, r2.y + r2.h // 2 + 4))
    legend(screen, r2.x, r2.bottom + 6, [("LED command (TX)", TX_C), ("receiver decision (RX)", RX_C),
                                          ("mismatch", ERR_C)], small)

    # --- link quality under the plots ---
    y = r2.bottom + 40
    parts = ["sensor delay %d ms" % (link.lag * 1000 // SAMPLE_HZ)]
    if link.win_err is not None:
        parts.append("window error %.2f %%" % (100 * link.win_err))
    if link.compared:
        parts.append("total error %.2f %% of %d samples" % (100 * link.errors / link.compared, link.compared))
    screen.blit(small.render("Link quality:  " + "   |   ".join(parts), True, DIM), (r2.x, y))
    if link.cal:
        cal = "   ".join("%s %s" % (k, v) for k, v in sorted(link.cal.items()))
        screen.blit(small.render("Calibration:   " + cal, True, DIM), (r2.x, y + 24))


def draw_panel(screen, link, fonts, port):
    small, mid, big = fonts
    x = W - PANEL_W
    y = 18

    def text(s, color=TEXT, font=small, dx=0):
        screen.blit(font.render(s, True, color), (x + dx, y))

    text("Port %s   |   %s" % (port or "none", link.status[:28]), DIM)
    y += 34

    if link.active:
        text("Now sending: LED %d" % link.active, WAIT_C, mid)
        y += 30
        text("Receiving:  " + link.rx_live + "_", RX_C, big)
        y += 44
    else:
        text("Between rounds", DIM, mid)
        y += 74

    def result_color(r):
        return {"OK": OK_C, "WRONG": ERR_C, "MISSED": WAIT_C}.get(r, TEXT)

    # each LED = one dish's copy of the frame, with Choir's checks and trust
    text("Frames  (ID|counter|data|checksum)", TEXT, mid)
    y += 30
    for n in range(1, link.n_leds + 1):
        trust = link.trust[n - 1] if n - 1 < len(link.trust) else 1.0
        text("LED %d" % n, DIM)
        pygame.draw.rect(screen, GRID, (x, y + 22, 50, 8))
        pygame.draw.rect(screen, OK_C if trust > 0.5 else ERR_C, (x, y + 22, int(50 * trust), 8))
        check = link.checks.get(n)
        if n in link.copies:
            frame = link.copies[n][0]
            color = TEXT if check is None else (OK_C if check == "OK" else ERR_C)
            text(frame, color, mid, 70)
            if check is not None:
                y += 24
                text("PASS" if check == "OK" else "REJECT: " + check[:34], color, small, 70)
        else:
            text("receiving: " + link.rx_live + "_" if n == link.active else "waiting", DIM, small, 70)
        y += 30
    screen.blit(small.render("bar = trust, learned only from verified frames", True, DIM), (x, y))
    y += 30

    # the two strategies, same frames
    maj_r, choir_r = link.result if link.result else (None, None)
    text("Majority vote  (trust what agrees)", DIM)
    y += 22
    if link.voted:
        frame, leds = link.voted
        text("%s  from LED %s" % (frame, leds), result_color(maj_r), mid)
        if maj_r:
            text(maj_r, result_color(maj_r), mid, PANEL_W - 90)
    else:
        text("-", DIM, mid)
    y += 34

    text("Choir  (trust what verifies)", DIM)
    y += 22
    if link.accepted:
        payload, frame, leds = link.accepted
        if payload == "-":
            text("nothing logged", WAIT_C, big)
        else:
            text(payload, result_color(choir_r), big)
            text("%s from LED %s" % (frame, leds), DIM, small, 150)
        if choir_r:
            text(choir_r, result_color(choir_r), mid, PANEL_W - 90)
    else:
        text("-", DIM, big)
    y += 44

    if link.reveal:
        bad, fault, truth = link.reveal
        text("Truth: %s on LED %s (real %s)" % (fault, bad, truth), TEXT)
    else:
        text("Truth: hidden until both have decided", DIM)
    y += 34

    # scoreboard over all rounds (like the MATLAB results table)
    if link.rounds:
        n = len(link.rounds)
        maj = sum(1 for r in link.rounds if r[2] == "OK")
        cho = sum(1 for r in link.rounds if r[3] == "OK")
        false_acc = sum(1 for r in link.rounds if r[3] == "WRONG")
        text("Majority %d/%d  Choir %d/%d  false acc %d" % (maj, n, cho, n, false_acc),
             TEXT, mid)
        y += 30
        for i, (fault, bad, m, c) in list(enumerate(link.rounds, 1))[-4:][::-1]:
            text("#%-2d %-9s LED %-4s maj %-6s Choir %s" % (i, fault, bad, m, c),
                 OK_C if c == "OK" else ERR_C)
            y += 22

    screen.blit(small.render("R restart Pico   C clear stats   Esc quit", True, DIM), (x, H - 30))


def draw(screen, link, fonts, port):
    screen.fill(BG)
    draw_plots(screen, link, fonts[0], fonts[1])
    draw_panel(screen, link, fonts, port)
    pygame.display.flip()


# ---------------- main ----------------
def main():
    port = sys.argv[1] if len(sys.argv) > 1 else find_port()
    if not port:
        sys.exit("No serial port found. Is the Pico plugged in and Thonny closed?")
    try:
        ser = serial.Serial(port, BAUD, timeout=0.2)
    except serial.SerialException as e:
        sys.exit("Could not open %s (%s). Close Thonny and try again." % (port, e))

    lines = queue.Queue()
    stop = threading.Event()
    reader_thread = threading.Thread(target=reader, args=(ser, lines, stop), daemon=True)
    reader_thread.start()

    pygame.init()
    screen = pygame.display.set_mode((W, H))
    pygame.display.set_caption("Choir on a breadboard - trust what verifies, not what agrees")
    fonts = (pygame.font.SysFont("consolas", 16),
             pygame.font.SysFont("consolas", 20, bold=True),
             pygame.font.SysFont("consolas", 30, bold=True))
    clock = pygame.time.Clock()
    link = Link()
    next_lag = 0.0

    running = True
    while running:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            elif event.type == pygame.KEYDOWN:
                if event.key == pygame.K_ESCAPE:
                    running = False
                elif event.key == pygame.K_r:
                    ser.write(b"\x03\x03\x04")      # Ctrl-C, Ctrl-C, Ctrl-D: soft reboot, main.py reruns
                    link = Link()
                elif event.key == pygame.K_c:
                    link.reset_stats()

        while True:
            try:
                link.handle(lines.get_nowait())
            except queue.Empty:
                break

        if time.time() >= next_lag:
            link.update_lag()
            next_lag = time.time() + 0.5

        draw(screen, link, fonts, port)
        clock.tick(30)

    stop.set()
    reader_thread.join(timeout=1)               # let the reader finish its last read first
    ser.close()
    pygame.quit()


if __name__ == "__main__":
    main()
