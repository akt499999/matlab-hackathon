%MAKE_FIGS Slide figures and every slide number (numbers.json) for choir/deck/deck.html.
%   Reads results/*.csv (from run_all) and re-runs only the two short spectra cases and the
%   seed-301 showcase. Uses the technical-slides helpers (slidefig, slidepalette, labelend).
here = fileparts(mfilename('fullpath'));
root = fileparts(here);
addpath(fullfile(root, 'src'));
addpath('/Users/rachnap/.claude-school/skills/technical-slides/matlab');
res = fullfile(root, 'results'); figs = fullfile(here, 'figs');
if ~isfolder(figs), mkdir(figs); end
P = slidepalette(); N = struct(); Pc = choir_params();

% ---------------------------------------------------------------- 1. one dish vs eight
S = readtable(fullfile(res, 'snr_summary.csv'), 'TextType', 'string');
snr = unique(S.EsN0_dB);
pick = @(T, rx) arrayfun(@(e) T.success_pct(T.EsN0_dB == e & T.receiver == rx), snr);
fig = slidefig(8.2, 5.2); ax = axes(fig); hold(ax, 'on'); grid(ax, 'on'); ax.XGrid = 'off';
for rx = ["equal gain", "SUMPLE (blind consensus)", "sync-marker only"]
    plot(ax, snr, pick(S, rx), 'Color', P.context, 'LineWidth', 1.25);
end
yC = pick(S, "Choir (verified frames)"); yB = pick(S, "best single dish");
plot(ax, snr, yC, 'Color', P.s1, 'LineWidth', 2.5);
plot(ax, snr, yB, 'Color', P.s2, 'LineWidth', 2.5);
xlim(ax, [min(snr) max(snr)]); ylim(ax, [0 104]); xticks(ax, snr);
xlabel(ax, 'Mean Es/N0 per dish (dB)'); ylabel(ax, 'Frames delivered bit-exact (%)');
text(ax, -3.7, 86, '8 dishes, Choir', 'Color', P.s1, 'FontWeight', 'bold');
text(ax, 2.4, 74, 'best single dish', 'Color', P.s2, 'FontWeight', 'bold');
slidefig(fig, fullfile(figs, 'snr.svg'));
N.single_8dB = yB(snr == 8); N.single_4dB = yB(snr == 4); N.single_6dB = yB(snr == 6);
N.choir_2dB = yC(snr == 2); N.choir_0dB = yC(snr == 0);

% ---------------------------------------------------------------- 2. look-alike spacecraft
I = readtable(fullfile(res, 'interference_summary.csv'), 'TextType', 'string');
inr = unique(I.inr_dB);
g = @(typ, rx) arrayfun(@(v) I.success_pct(I.interferer == typ & I.inr_dB == v & I.receiver == rx), inr);
fig = slidefig(8.2, 5.2); ax = axes(fig); hold(ax, 'on'); grid(ax, 'on'); ax.XGrid = 'off';
plot(ax, inr, g("lookalike", "equal gain"), 'Color', P.context, 'LineWidth', 1.25);
plot(ax, inr, g("lookalike", "bound: knows the data"), '--', 'Color', P.context, 'LineWidth', 1.25);
plot(ax, inr, g("lookalike", "sync-marker only"), 'Color', P.s3);
plot(ax, inr, g("lookalike", "SUMPLE (blind consensus)"), 'Color', P.s2);
plot(ax, inr, g("lookalike", "Choir (verified frames)"), 'Color', P.s1, 'LineWidth', 2.5);
xlim(ax, [-10 20]); ylim(ax, [0 104]); xticks(ax, inr);
xlabel(ax, 'Look-alike spacecraft power per dish, relative to ours (dB)');
ylabel(ax, 'Frames delivered bit-exact (%)');
text(ax, 19.6, 80, 'Choir', 'Color', P.s1, 'FontWeight', 'bold', 'HorizontalAlignment', 'right');
text(ax, 19.6, 97, 'bound (knows the data)', 'Color', P.muted, 'HorizontalAlignment', 'right');
text(ax, 8.2, 18, 'sync-marker only', 'Color', P.s3, 'FontWeight', 'bold');
text(ax, -9.6, 45, 'SUMPLE', 'Color', P.s2, 'FontWeight', 'bold');
text(ax, 5.6, 30, 'equal gain', 'Color', P.muted);
slidefig(fig, fullfile(figs, 'lookalike.svg'));
c10 = g("lookalike", "Choir (verified frames)"); s10 = g("lookalike", "SUMPLE (blind consensus)");
y10 = g("lookalike", "sync-marker only"); e10 = g("lookalike", "equal gain"); b10 = g("lookalike", "bound: knows the data");
N.look10_choir = c10(inr == 10); N.look10_sumple = s10(inr == 10); N.look10_egc = e10(inr == 10);
N.look10_sync = y10(inr == 10); N.look10_bound = b10(inr == 10);
N.look20_choir = c10(inr == 20); N.look20_sync = y10(inr == 20);
wC = g("wideband", "Choir (verified frames)"); wS = g("wideband", "SUMPLE (blind consensus)");
N.wide10_choir = wC(inr == 10); N.wide10_sumple = wS(inr == 10); N.wide20_choir = wC(inr == 20);
N.false_accepts_interference = sum(I.sum_false_accepts);
N.interference_seeds = numel(unique(readtable(fullfile(res, 'interference_runs.csv')).seed));

% ---------------------------------------------------------------- 3. before / after spectra
cases = {make_scenario(201, 40, 2, []), make_scenario(202, 40, 2, fault("wideband", 15, 42, [], 10))};
ttl = ["No interference", "Wide-band source, +10 dB per dish"];
fig = slidefig(12, 5.2); tl = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
sm = @(p) movmean(10*log10(p*Pc.fs), 9);
for c = 1:2
    out = run_scenario(Pc, cases{c}, rx_spec("choir", true), 25);
    D = out.RX{1}.capture;
    sh = D.dl - min(D.dl); Lc = size(D.x, 2) - max(sh);
    xa = complex(zeros(Pc.nDish, Lc));
    for k = 1:Pc.nDish, xa(k, :) = D.x(k, sh(k) + (1:Lc)); end
    wS = ones(Pc.nDish, 1);
    for it = 1:20
        z = wS' * D.Y;
        for k = 1:Pc.nDish, wS(k) = D.Y(k, :) * (z - wS(k)' * D.Y(k, :))' / size(D.Y, 2); end
        wS = wS / norm(wS);
    end
    [p1, f] = pwelch(D.x(1, :), hann(1024), 512, 1024, Pc.fs, 'centered');
    pS = pwelch((wS' * xa) / norm(wS), hann(1024), 512, 1024, Pc.fs, 'centered');
    pC = pwelch((D.w' * xa) / norm(D.w), hann(1024), 512, 1024, Pc.fs, 'centered');
    out_ = abs(f) > 50e3; in_ = abs(f) < 30e3;
    lv = @(p) [median(10*log10(p(out_)*Pc.fs)), median(10*log10(p(in_)*Pc.fs))];
    L1 = lv(p1); LS = lv(pS); LC = lv(pC);
    tag = ["clean", "wide"]; tag = tag(c);
    N.("spec_" + tag + "_dish_floor_dB") = round(L1(1), 1); N.("spec_" + tag + "_dish_inband_dB") = round(L1(2), 1);
    N.("spec_" + tag + "_sumple_floor_dB") = round(LS(1), 1); N.("spec_" + tag + "_sumple_inband_dB") = round(LS(2), 1);
    N.("spec_" + tag + "_choir_floor_dB") = round(LC(1), 1); N.("spec_" + tag + "_choir_inband_dB") = round(LC(2), 1);
    ax = nexttile(tl); hold(ax, 'on'); grid(ax, 'on'); ax.XGrid = 'off';
    plot(ax, f/1e3, sm(p1), 'Color', P.context, 'LineWidth', 1.5);
    plot(ax, f/1e3, sm(pS), 'Color', P.s2, 'LineWidth', 2);
    plot(ax, f/1e3, sm(pC), 'Color', P.s1, 'LineWidth', 2.5);
    xlim(ax, [-128 128]); ylim(ax, [-4 20]); xticks(ax, -100:50:100);
    title(ax, ttl(c)); xlabel(ax, 'Frequency offset (kHz)');
    if c == 1, ylabel(ax, 'Power density re one dish''s noise (dB)'); end
    if c == 1
        text(ax, -124, 17.5, '8 dishes (Choir, SUMPLE)', 'Color', P.s1, 'FontWeight', 'bold');
        text(ax, 45, 5.2, 'one dish', 'Color', P.muted);
    else
        text(ax, -122, 18.6, 'SUMPLE', 'Color', P.s2, 'FontWeight', 'bold');
        text(ax, -122, 10.3, 'one dish', 'Color', P.muted);
        text(ax, -122, 2.2, 'Choir', 'Color', P.s1, 'FontWeight', 'bold');
    end
end
slidefig(fig, fullfile(figs, 'spectra.svg'));

% ---------------------------------------------------------------- 4. six hidden faults (seed 301)
Fs = readtable(fullfile(res, 'faults_summary.csv'), 'TextType', 'string');
Fr = readtable(fullfile(res, 'faults_recovery.csv'), 'TextType', 'string');
N.faults_choir = round(Fs.correct_pct_mean(Fs.receiver == "Choir"), 1);
N.faults_sumple = round(Fs.correct_pct_mean(Fs.receiver == "SUMPLE + same supervisor"), 1);
N.faults_egc = round(Fs.correct_pct_mean(Fs.receiver == "equal gain + same supervisor"), 1);
N.faults_nosup = round(Fs.correct_pct_mean(Fs.receiver == "Choir, supervisor off"), 1);
N.faults_choir_worst = round(Fs.correct_pct_worst_run(Fs.receiver == "Choir"), 1);
N.faults_false_accepts = sum(Fs.false_accepts_total);
N.hop_ms = Fr.hop_median_ms(Fr.receiver == "Choir");
N.lookalike_sumple_ms = Fr.lookalike_median_ms(Fr.receiver == "SUMPLE + same supervisor");
raw = load(fullfile(res, 'faults_raw.mat'));
N.fault_runs = numel(raw.seeds);
F = 300; seed = 301;
faults = random_faults(seed, F, Pc.nDish);
specs = [rx_spec("choir", true, "Choir"), rx_spec("sumple", true, "SUMPLE"), rx_spec("choir", false, "Choir, supervisor off")];
out = run_scenario(Pc, make_scenario(seed, F, 2, faults), specs);
t = (1:F) * Pc.Tf;
fig = slidefig(12, 5.2); tl = tiledlayout(fig, 7, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax1 = nexttile(tl, [2 1]); hold(ax1, 'on');
names = struct('dead', "dead dish", 'glitch', "clock glitch", 'lookalike', "look-alike", ...
    'hop', "carrier hop", 'fade', "fade", 'noisy', "noisy dish");
[~, ord] = sort([faults.t0]);
for n = 1:numel(ord)
    f = faults(ord(n)); x0 = (f.t0 - 1)*Pc.Tf; x1 = max(f.t1, f.t0 + 1)*Pc.Tf;
    xregion(ax1, x0, x1, 'FaceColor', P.ink2, 'FaceAlpha', 0.18);
    yl = 0.72; if mod(n, 2) == 0, yl = 0.28; end
    text(ax1, x0 + 0.03, yl, names.(f.type), 'Color', P.ink2, 'FontSize', 14, 'VerticalAlignment', 'middle');
end
yticks(ax1, []); ax1.YAxis.Visible = 'off'; ax1.XTickLabel = []; ylim(ax1, [0 1]);
title(ax1, 'Hidden faults (the receiver is never told)');
ax2 = nexttile(tl, [3 1]); hold(ax2, 'on'); grid(ax2, 'on'); ax2.XGrid = 'off';
plot(ax2, t, 1:F, '--', 'Color', P.context, 'LineWidth', 1.25);
cols = {P.s1, P.s2, P.context}; lw = [2.5 2 2]; tags = ["choir", "sumple", "nosup"];
for r = 1:3
    k = cumsum(out.score(r).ok);
    plot(ax2, t, k, 'Color', cols{r}, 'LineWidth', lw(r));
    N.("seed301_" + tags(r)) = k(end);
end
ylabel(ax2, 'Frames delivered'); ax2.XTickLabel = []; ylim(ax2, [0 F]); yticks(ax2, [0 150 300]);
text(ax2, 0.3, 215, 'dashed: all 300 frames sent', 'Color', P.muted);
text(ax2, t(end) + 0.06, 302, sprintf('Choir  %d', N.seed301_choir), 'Color', P.s1, 'FontWeight', 'bold');
text(ax2, t(end) + 0.06, 236, sprintf('SUMPLE  %d', N.seed301_sumple), 'Color', P.s2, 'FontWeight', 'bold');
text(ax2, t(end) + 0.06, 170, sprintf('supervisor off  %d', N.seed301_nosup), 'Color', P.muted);
ax3 = nexttile(tl, [2 1]); hold(ax3, 'on');
[~, sNum] = ismember(out.RX{1}.stateHist(1:F), ["SEARCH", "ALIGN", "DECODE", "FALLBACK"]);
sNum(sNum == 2) = 1;                               % SEARCH and ALIGN shown together as "acquire"
lvl = [1 1 2 3]; sPlot = lvl(max(sNum, 1));
sPlot(sNum == 4) = 3; sPlot(sNum == 3) = 2;
stairs(ax3, t, sPlot, 'Color', P.s1, 'LineWidth', 2);
yticks(ax3, 1:3); yticklabels(ax3, ["acquire", "decode", "safe mode"]); ylim(ax3, [0.6 3.4]);
xlabel(ax3, 'Time (s)'); title(ax3, 'Choir state');
linkaxes([ax1 ax2 ax3], 'x'); xlim(ax3, [0 F*Pc.Tf + 1.9]);
slidefig(fig, fullfile(figs, 'faults.svg'));

% detection delays for the decision-log table (seed 301)
lg = readtable(fullfile(res, sprintf('decision_log_seed%d.csv', seed)), 'TextType', 'string');
hf = readtable(fullfile(res, sprintf('hidden_faults_seed%d.csv', seed)), 'TextType', 'string');
first = @(s0, ev) min(lg.slot(lg.slot >= s0 & ismember(lg.event, ev)));
evmap = struct('lookalike', "interference", 'dead', "dish down", 'noisy', "noisy dish", ...
    'fade', "safe mode", 'glitch', "dish re-aligned", 'hop', "safe mode");
fprintf('\nDecision-log rows (seed %d):\n', seed);
delays = zeros(height(hf), 1);
[~, order] = sort(hf.t0);
for i = order.'
    ev = evmap.(hf.type(i)); s1 = first(hf.t0(i), ev);
    delays(i) = s1 - hf.t0(i);
    r = lg(lg.slot == s1 & lg.event == ev, :);
    fprintf('%-10s fault at frame %3d | logged "%s" at frame %3d (+%d) | %s\n', hf.type(i), hf.t0(i), ev, s1, delays(i), r.reason(1));
end
N.max_detect_frames = max(delays); N.max_detect_ms = round(max(delays) * Pc.Tf * 1000);
N.frame_ms = round(Pc.Tf * 1000, 1);

% ---------------------------------------------------------------- 5. geometry of the failure case
sim = zeros(1, 10);
for s = 301:310
    ch = channel_make(Pc, make_scenario(s, 2, 2, []));
    sim(s - 300) = abs(ch.a' * ch.b2) / (norm(ch.a) * norm(ch.b2));
end
N.sim304 = round(sim(4), 2); others = sim([1:3 5:10]);
N.sim_others_min = round(min(others), 2); N.sim_others_max = round(max(others), 2);
N.simulink_seed301 = round(raw.correct(1, 1) * F);

fid = fopen(fullfile(here, 'numbers.json'), 'w'); fprintf(fid, '%s', jsonencode(N, 'PrettyPrint', true)); fclose(fid);
disp(N);
