function make_slides(root)
%MAKE_SLIDES Build docs/slides.pdf from the measured results (numbers are read from results/*.csv).
res = fullfile(root, 'results'); figs = fullfile(res, 'figures');
pdf = fullfile(root, 'docs', 'slides.pdf'); if isfile(pdf), delete(pdf); end
I = readtable(fullfile(res, 'interference_summary.csv'), 'TextType', 'string');
Fs = readtable(fullfile(res, 'faults_summary.csv'), 'TextType', 'string');
Fr = readtable(fullfile(res, 'faults_recovery.csv'), 'TextType', 'string');
pick = @(typ, inr, rx) I.success_pct(I.interferer == typ & I.inr_dB == inr & I.receiver == rx);
[~, info] = telemetry_source(1);

slide(pdf, "Choir: an antenna array that trusts what decodes", [ ...
    "MATLAB in Space Hackathon, Track 1: Deep-Space Communication & Signal Intelligence"
    ""
    "8 simulated dishes receive one weak spacecraft signal carrying " + ternary(info.real, "real NASA Curiosity (MSL) telemetry values", "telemetry (synthetic stand-in in this build)")
    "The receiver finds the carrier, lines the dishes up, decodes CCSDS frames, and recovers from hidden faults on its own"
    "Key idea: learn how much to trust each dish only from frames that pass the checksum and carry our spacecraft ID"], "");

slide(pdf, "The problem", [ ...
    "A deep-space signal is far too weak for one dish, so NASA's Deep Space Network combines several (arraying)"
    "Lining them up blindly (JPL's SUMPLE: each dish vs. the sum of the others) follows whatever the dishes agree on"
    "A louder signal that reaches every dish, like another spacecraft or a radio source in the beam, is then what they agree on"
    "DSN demand exceeds supply by up to 40% at times (NASA OIG IG-23-016, 2023); the receiver must also run itself"
    "Track 1 asks for: noisy radio in, automatic filtering and (re)acquisition, decoded telemetry out"], "");

slide(pdf, "How Choir works (all MATLAB)", [ ...
    "Transmit: telemetry -> CCSDS-style frames (spacecraft ID, counter, CRC-16) -> ccsdsTMWaveformGenerator (BPSK, RRC, sync marker, randomizer)"
    "Channel (hidden truth): 8 dishes with their own SNR, delay, phase drift; carrier drift; seeded faults"
    "SEARCH: carrier found by squaring BPSK and summing spectra over dishes"
    "ALIGN: sync-marker search over a full frame period; per-dish delays; frames from other spacecraft rejected by ID"
    "DECODE: weights w = Q^-1 h. h (where the spacecraft is) is learned only from verified frames;"
    "        Q (everything else) comes from all samples, so new interference is cancelled without waiting for a good frame"
    "Health: a dish that stops matching verified frames is re-timed or excluded, and probed until it returns"
    "FALLBACK: 3 bad frames -> re-time every dish on the sync marker, equal weights; 8 bad -> full carrier re-search"], "");

slide(pdf, "Main result: interference that looks like the spacecraft", [ ...
    sprintf("Look-alike spacecraft at +10 dB per dish: Choir %.0f%%, SUMPLE %.0f%%, equal gain %.0f%%, sync-marker only %.0f%% of frames correct", ...
        pick("lookalike", 10, "Choir (verified frames)"), pick("lookalike", 10, "SUMPLE (blind consensus)"), pick("lookalike", 10, "equal gain"), pick("lookalike", 10, "sync-marker only"))
    sprintf("Wide-band source at +10 dB per dish: Choir %.0f%%, SUMPLE %.0f%%", pick("wideband", 10, "Choir (verified frames)"), pick("wideband", 10, "SUMPLE (blind consensus)"))
    sprintf("False accepts across all interference runs: %d", sum(I.sum_false_accepts))], fullfile(figs, 'interference.png'));

c = Fs.receiver == "Choir";
slide(pdf, "Autonomy: six hidden faults per run, nobody touches it", [ ...
    sprintf("20 seeded runs, each with a dead dish, clock glitch, look-alike spacecraft, carrier hop, deep fade and noisy dish at random times"),
    sprintf("Correct frames: Choir %.1f%% (worst run %.1f%%); SUMPLE + same supervisor %.1f%%; Choir with supervisor off %.1f%%", ...
        Fs.correct_pct_mean(c), Fs.correct_pct_worst_run(c), Fs.correct_pct_mean(Fs.receiver == "SUMPLE + same supervisor"), Fs.correct_pct_mean(Fs.receiver == "Choir, supervisor off"))
    sprintf("Median recovery (Choir): carrier hop %g ms, after deep fade %g ms; false accepts: %d", ...
        Fr.hop_median_ms(Fr.receiver == "Choir"), Fr.fade_median_ms(Fr.receiver == "Choir"), Fs.false_accepts_total(c))], fullfile(figs, 'timeline.png'));

slide(pdf, "Before / after spectra (required Track 1 output)", ...
    "Grey: one dish. Green: Choir's combined output. Orange: SUMPLE. Same noise scale.", fullfile(figs, 'spectra.png'));

slide(pdf, "Telemetry log: what actually arrived", ...
    "Logged values from verified frames only; gaps are frames the receiver refused to log", fullfile(figs, 'telemetry.png'));

slide(pdf, "Honest limits and next steps", [ ...
    "The radio link is simulated; the telemetry values are real (MSL, telemanom dataset). No real multi-dish recording was available"
    "Uncoded BPSK: real deep-space links use turbo/LDPC codes, which would shift every curve left by several dB"
    "Interferers are modeled near the spacecraft's direction (shared per-dish delay); far off-axis ones need space-time weights"
    "The checksum protects against noise, not a deliberate spoofer (that needs authenticated frames, e.g. CCSDS SDLS)"
    "Choir needs some verified frames first: interference present before any frame ever verifies is its weak case"
    "Next: elastic arraying (release dishes when margin allows), coding, real SatNOGS recordings, Stateflow supervisor"], "");
fprintf('slides written to %s\n', pdf);
end

function slide(pdf, ttl, lines, img)
fig = figure('Visible', 'off', 'Units', 'pixels', 'Position', [0 0 1600 900], 'Color', [0.07 0.08 0.10]);
annotation(fig, 'textbox', [0.04 0.88 0.92 0.1], 'String', ttl, 'FontSize', 30, 'FontWeight', 'bold', ...
    'EdgeColor', 'none', 'Interpreter', 'none', 'VerticalAlignment', 'middle', 'Color', [0.45 0.9 0.6]);
if strlength(img) > 0
    ax = axes(fig, 'Position', [0.05 0.03 0.9 0.62]); image(ax, imread(img)); axis(ax, 'image', 'off');
    box = [0.05 0.66 0.9 0.22]; fs = 15;
else
    box = [0.05 0.08 0.9 0.78]; fs = 20;
end
annotation(fig, 'textbox', box, 'String', cellstr(lines), 'FontSize', fs, 'EdgeColor', 'none', ...
    'Interpreter', 'none', 'VerticalAlignment', 'top', 'Color', [0.93 0.93 0.93]);
exportgraphics(fig, pdf, 'Append', true, 'ContentType', 'image', 'Resolution', 110);
close(fig);
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end
