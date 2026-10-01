"""Procedural 4-on-the-floor music + metronome clap generator (numpy/scipy/soundfile).
Renders sample-exact loops (length = bars * 4 * samples-per-beat, integer) so the beat grid is perfect:
sample 0 is beat 0 and the kick lands on every beat. Outputs OGG to assets/music and WAV to assets/sfx.
Run:  python tools/gen_music.py
"""
import os
import numpy as np
from scipy.signal import butter, sosfilt
import soundfile as sf

SR = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
MUSIC = os.path.join(ROOT, 'assets', 'music')
SFX = os.path.join(ROOT, 'assets', 'sfx')
os.makedirs(MUSIC, exist_ok=True)
os.makedirs(SFX, exist_ok=True)
rng = np.random.default_rng(7)

def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12.0)

def lp(x, fc, order=2):
    return sosfilt(butter(order, fc, 'low', fs=SR, output='sos'), x)

def hp(x, fc, order=2):
    return sosfilt(butter(order, fc, 'high', fs=SR, output='sos'), x)

def bp(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], 'band', fs=SR, output='sos'), x)

def tt(n):
    return np.arange(n) / SR

def saw(f, n, ph=0.0):
    return 2.0 * ((f * tt(n) + ph) % 1.0) - 1.0

def square(f, n, duty=0.5):
    return np.where(((f * tt(n)) % 1.0) < duty, 1.0, -1.0)

def sine(f, n):
    return np.sin(2 * np.pi * f * tt(n))

# ---------------- one-shots ----------------
def kick(vol=1.0, punch=1.0):
    n = int(0.42 * SR)
    t = tt(n)
    f = 46 + 130 * np.exp(-t * 32)
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.sin(ph) * np.exp(-t * 9.0)
    click = hp(rng.standard_normal(n), 2500) * np.exp(-t * 400) * 0.35 * punch
    return (y + click) * vol

def clap(vol=1.0):
    n = int(0.35 * SR)
    t = tt(n)
    noise = rng.standard_normal(n)
    env = np.zeros(n)
    for k, d in enumerate([0.0, 0.011, 0.022, 0.034]):
        i = int(d * SR)
        env[i:] += np.exp(-tt(n - i) * (250 if k < 3 else 38)) * (0.7 if k < 3 else 1.0)
    return bp(noise, 900, 3200, 2) * env * 2.2 * vol

def snare(vol=1.0):
    n = int(0.3 * SR)
    t = tt(n)
    body = np.sin(2 * np.pi * (180 - 60 * t * 4) * t) * np.exp(-t * 28)
    nz = hp(rng.standard_normal(n), 1800) * np.exp(-t * 20)
    return (body * 0.6 + nz * 0.9) * vol

def hat(vol=1.0, open_=False):
    n = int((0.28 if open_ else 0.07) * SR)
    t = tt(n)
    return hp(rng.standard_normal(n), 7000) * np.exp(-t * (14 if open_ else 70)) * vol

def rim(vol=1.0):
    n = int(0.12 * SR)
    t = tt(n)
    return (np.sin(2 * np.pi * 1750 * t) * np.exp(-t * 90) * 0.7 + hp(rng.standard_normal(n), 3000) * np.exp(-t * 200) * 0.5) * vol

def wood(vol=1.0):
    n = int(0.15 * SR)
    t = tt(n)
    return (np.sin(2 * np.pi * 880 * t) + 0.5 * np.sin(2 * np.pi * 1320 * t)) * np.exp(-t * 55) * 0.6 * vol

def snap(vol=1.0):
    n = int(0.1 * SR)
    t = tt(n)
    return bp(rng.standard_normal(n), 2200, 6000) * np.exp(-t * 140) * 2.5 * vol

# ---------------- loop renderer ----------------
class Song:
    def __init__(self, bpm, bars):
        self.spb = int(round(60.0 / bpm * SR))
        assert abs(self.spb - 60.0 / bpm * SR) < 1e-6, "pick a BPM with integer samples/beat (%s)" % bpm
        self.bpm = bpm
        self.bars = bars
        self.n = self.spb * 4 * bars
        self.buses = {}

    def bus(self, name):
        if name not in self.buses:
            self.buses[name] = np.zeros((self.n, 2))
        return self.buses[name]

    def step_pos(self, bar, beat, sixteenth=0):
        return int(round((bar * 4 + beat + sixteenth / 4.0) * self.spb))

    def put(self, bus, x, start, gain=1.0, pan=0.0):
        b = self.bus(bus)
        idx = (start + np.arange(len(x))) % self.n
        l = np.cos((pan + 1) * np.pi / 4)
        r = np.sin((pan + 1) * np.pi / 4)
        b[idx, 0] += x * gain * l * 1.4142
        b[idx, 1] += x * gain * r * 1.4142

    def duck_curve(self, kick_starts, depth=0.8, tau=0.14):
        d = np.ones(self.n)
        m = int(0.5 * SR)
        shape = 1.0 - depth * np.exp(-tt(m) / tau)
        for s in kick_starts:
            idx = (s + np.arange(m)) % self.n
            d[idx] = np.minimum(d[idx], shape)
        return d

    def delay(self, x, steps16, fb=0.35, taps=3):
        out = x.copy()
        d = int(self.spb * steps16 / 4.0)
        for k in range(1, taps + 1):
            out += np.roll(x, d * k, axis=0) * (fb ** k)
        return out

def chord_notes(root, minor=True, seventh=False):
    third = 3 if minor else 4
    n = [root, root + third, root + 7]
    if seventh:
        n.append(root + (10 if minor else 11))
    return n

def render(cfg, name):
    s = Song(cfg['bpm'], cfg['bars'])
    kicks = []
    for bar in range(s.bars):
        sec = min(bar // (s.bars // 4), 3)
        for beat in range(4):
            kicks.append(s.step_pos(bar, beat))
    for bar in range(s.bars):
        sec = min(bar // (s.bars // 4), 3)
        # --- drums ---
        for beat in range(4):
            p = s.step_pos(bar, beat)
            s.put('drums', kick(cfg['kick']), p, 1.0)
            s.put('drums', hat(0.55, True), s.step_pos(bar, beat, 2), 0.5 * cfg['hat'], 0.25)
            if sec >= 2 or cfg.get('dense_hats'):
                for sx in (1, 3):
                    s.put('drums', hat(0.4), s.step_pos(bar, beat, sx), 0.32 * cfg['hat'], -0.2)
            if sec >= 1 and beat in (1, 3) and cfg['backbeat'] != 'none':
                if cfg['backbeat'] == 'clap':
                    s.put('drums', clap(0.8), p, 0.55)
                else:
                    s.put('drums', snare(0.8), p, 0.55)
        if sec == 3 and bar == s.bars - 1:  # fill on the last bar
            for k in range(8):
                s.put('drums', snare(0.6 + 0.04 * k), s.step_pos(bar, 3, 0) + int(k * s.spb / 8), 0.4)
        # --- harmony ---
        prog = cfg['prog']
        root = prog[bar % len(prog)]
        notes = chord_notes(root, cfg['minor'], cfg.get('seventh', False))
        # bass
        if sec >= 1:
            pat = cfg['bass_pat']  # 16th steps within a beat group of 4 beats (0..15)
            for st in pat:
                p = s.step_pos(bar, st // 4, st % 4)
                nlen = int(cfg['bass_len'] * s.spb)
                f = midi(root - 24)
                x = saw(f, nlen) * np.exp(-tt(nlen) / (cfg['bass_len'] * s.spb / SR * 0.9))
                x = lp(x, cfg['bass_cut']) * 0.9
                s.put('bass', x, p, 0.55)
                s.put('bass', sine(f, nlen) * np.exp(-tt(nlen) * 6) * 0.5, p, 0.4)
        # pad / chord
        if sec >= 2:
            ln = s.spb * 4
            x = np.zeros(ln)
            for nn in notes:
                f = midi(nn + 12)
                for det in (-0.004, 0.0, 0.004):
                    x += saw(f * (1 + det), ln, rng.random())
            att = np.minimum(1.0, tt(ln) / 0.25) * np.minimum(1.0, (ln / SR - tt(ln)) / 0.08)
            s.put('pad', lp(x, cfg['pad_cut']) * att * 0.07, s.step_pos(bar, 0), 1.0, -0.2)
        # stabs / lead pattern
        if sec >= 1:
            for st in cfg['lead_pat']:
                if sec < 2 and st % 4 != 2:
                    continue
                p = s.step_pos(bar, st // 4, st % 4)
                ln = int(0.22 * SR)
                ni = cfg['arp'][(st // 4 + st) % len(cfg['arp'])]
                nn = notes[ni % len(notes)] + 24 + (12 if ni >= len(notes) else 0)
                f = midi(nn)
                if cfg['lead'] == 'chip':
                    x = square(f, ln, 0.25) * np.exp(-tt(ln) * 9)
                    x = lp(x, 5200)
                else:
                    x = saw(f, ln) * np.exp(-tt(ln) * 12)
                    x = lp(x, 3000)
                s.put('lead', x * 0.5, p, 0.6, 0.15 if (st % 8) < 4 else -0.15)
    duck = s.duck_curve(kicks, cfg['duck'])
    d2 = duck[:, None]
    lead = s.delay(s.bus('lead'), cfg['delay'], 0.38, 3) if 'lead' in s.buses else 0
    mix = (s.bus('drums') * 0.95
           + (s.bus('bass') * d2 * 1.05 if 'bass' in s.buses else 0)
           + (s.bus('pad') * d2 * 1.0 if 'pad' in s.buses else 0)
           + (lead * (0.55 + 0.4 * d2) if 'lead' in s.buses else 0))
    mix = np.tanh(mix * 1.1) * 0.93
    peak = np.max(np.abs(mix))
    mix = mix / peak * 0.78
    out = os.path.join(MUSIC, name + '.ogg')
    data = mix.astype(np.float32)
    with sf.SoundFile(out, 'w', samplerate=SR, channels=2, format='OGG', subtype='VORBIS') as fh:
        for i in range(0, len(data), 4096):  # chunked: one big write overflows the stack on Windows
            fh.write(data[i:i + 4096])
    print('%-14s %3d BPM  %2d bars  %4d beats  %.1fs  %.0f KB' % (name, cfg['bpm'], s.bars, s.bars * 4, s.n / SR, os.path.getsize(out) / 1024))
    return s.bars * 4

A, B, C, D, E, F, G = 57, 59, 48, 50, 52, 53, 55  # root midi (A3..G3 region)

TRACKS = {
    # 4-on-the-floor house, Am-F-C-G
    'neon_drive': dict(bpm=126, bars=16, kick=1.0, hat=1.0, backbeat='clap', prog=[A, F, C, G], minor=True,
                       bass_pat=[2, 6, 10, 14], bass_len=0.5, bass_cut=420, pad_cut=1700, duck=0.8,
                       lead='saw', lead_pat=[0, 3, 6, 10, 12, 14], arp=[0, 1, 2, 3, 2, 1], delay=3),
    # chiptune trance, Em-C-D-B
    'pixel_rave': dict(bpm=135, bars=16, kick=1.0, hat=1.0, backbeat='snare', prog=[E, C, D, 47], minor=True,
                       bass_pat=[2, 3, 6, 7, 10, 11, 14, 15], bass_len=0.25, bass_cut=520, pad_cut=2200, duck=0.85,
                       lead='chip', lead_pat=[0, 2, 3, 5, 6, 8, 10, 11, 13, 14], arp=[0, 1, 2, 3, 2, 1, 4, 2], delay=3,
                       dense_hats=True),
    # driving techno/acid, Dm-Bb-F-C
    'sub_zero': dict(bpm=120, bars=16, kick=1.15, hat=1.1, backbeat='clap', prog=[D, 46, F, C], minor=True,
                     bass_pat=[0, 2, 3, 6, 8, 10, 11, 14], bass_len=0.3, bass_cut=700, pad_cut=1200, duck=0.9,
                     lead='saw', lead_pat=[2, 6, 10, 14, 15], arp=[0, 2, 1, 3], delay=3),
    # boss: hard & fast
    'maestro_rush': dict(bpm=140, bars=16, kick=1.2, hat=1.1, backbeat='snare', prog=[F, 49, 44, 51], minor=True,
                         bass_pat=[0, 2, 3, 4, 6, 7, 8, 10, 11, 12, 14, 15], bass_len=0.2, bass_cut=800, pad_cut=2000, duck=0.9,
                         lead='chip', lead_pat=[0, 3, 4, 7, 8, 11, 12, 14], arp=[0, 1, 2, 3, 4, 3, 2, 1], delay=3,
                         dense_hats=True),
    # menu: calm, 105 BPM, no backbeat, soft
    'starlight': dict(bpm=105, bars=16, kick=0.7, hat=0.6, backbeat='none', prog=[C, A, F, G], minor=False,
                      bass_pat=[0, 6, 10], bass_len=0.6, bass_cut=300, pad_cut=1500, duck=0.5,
                      lead='chip', lead_pat=[0, 6, 10, 12], arp=[0, 1, 2, 1], delay=3),
}

def write_sfx():
    items = {'clap_clap': clap(1.0), 'clap_rim': rim(1.0), 'clap_wood': wood(1.0), 'clap_snap': snap(1.0)}
    for k, v in items.items():
        v = v / max(1e-6, np.max(np.abs(v))) * 0.9
        sf.write(os.path.join(SFX, k + '.wav'), v.astype(np.float32), SR, subtype='PCM_16')
        print('sfx', k, len(v))

if __name__ == '__main__':
    for name, cfg in TRACKS.items():
        render(cfg, name)
    write_sfx()
