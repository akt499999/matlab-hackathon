function [summary, recTable] = exp_faults(P, seeds, outDir)
%EXP_FAULTS Hidden-fault runs: six faults per run at seeded random times and dishes (random_faults).
%   Every receiver uses the same supervisor except the last one, which has it switched off.
F = 300;
specs = [rx_spec("choir", true, "Choir"), rx_spec("sumple", true, "SUMPLE + same supervisor"), ...
         rx_spec("egc", true, "equal gain + same supervisor"), rx_spec("choir", false, "Choir, supervisor off")];
types = ["dead", "glitch", "lookalike", "hop", "fade", "noisy"];
nr = numel(specs); ns = numel(seeds); nt = numel(types);
correct = zeros(ns, nr); fa = zeros(ns, nr); ms = zeros(ns, nr); rec = nan(ns, nr, nt);
parfor i = 1:ns
    faults = random_faults(seeds(i), F, P.nDish);
    out = run_scenario(P, make_scenario(seeds(i), F, 2, faults), specs);
    correct(i, :) = [out.score.correctFrac];
    fa(i, :) = [out.score.falseAccepts];
    ms(i, :) = [out.score.msPerFrame];
    r = nan(nr, nt);
    for q = 1:nr, r(q, :) = recovery(out.score(q).ok, faults, types); end
    rec(i, :, :) = r;
end
names = [specs.name].';
summary = table(names, 100*mean(correct, 1).', 100*min(correct, [], 1).', sum(fa, 1).', median(ms, 1).', ...
    'VariableNames', {'receiver', 'correct_pct_mean', 'correct_pct_worst_run', 'false_accepts_total', 'ms_per_frame_median'});
recTable = table(names, 'VariableNames', {'receiver'});
for t = 1:nt
    v = squeeze(rec(:, :, t));
    recTable.(types(t) + "_median_ms") = round(1000*P.Tf*median(v, 1, 'omitnan')).';
    recTable.(types(t) + "_recovered_pct") = round(100*mean(~isnan(v), 1)).';
end
writetable(summary, fullfile(outDir, 'faults_summary.csv'));
writetable(recTable, fullfile(outDir, 'faults_recovery.csv'));
save(fullfile(outDir, 'faults_raw.mat'), 'correct', 'fa', 'ms', 'rec', 'seeds', 'types', 'names');
showcase(P, seeds(1), F, specs, outDir);
end

function r = recovery(ok, faults, types)
% Frames from fault onset (end of a fade) until five frames in a row are delivered correctly again.
r = nan(1, numel(types)); F = numel(ok);
for f = faults
    j0 = f.t0; if f.type == "fade", j0 = f.t1 + 1; end
    for j = j0:min(F - 4, j0 + 100)
        if all(ok(j:j + 4)), r(types == f.type) = j - j0; break; end
    end
end
end

function showcase(P, seed, F, specs, outDir)
faults = random_faults(seed, F, P.nDish);
out = run_scenario(P, make_scenario(seed, F, 2, faults), specs);
R = out.RX{1}; ch = out.ch;
lg = R.log; lg.time_s = round((lg.slot - 1) * P.Tf, 3);
writetable(lg(:, {'time_s', 'slot', 'state', 'event', 'reason'}), fullfile(outDir, sprintf('decision_log_seed%d.csv', seed)));
% telemetry log: what the receiver outputs (verified frames only)
rows = cell(numel(R.qT), 1);
for i = 1:numel(R.qT)
    q = double(R.q{i}) / 32767;
    rows{i} = [repmat([round(R.qT(i)/P.fs, 4), i], numel(q), 1), (1:numel(q)).', q];
end
M = vertcat(rows{:});
writetable(array2table(M, 'VariableNames', {'time_s', 'logged_frame', 'sample_in_frame', 'value'}), ...
    fullfile(outDir, sprintf('telemetry_log_seed%d.csv', seed)));
truthFaults = struct2table(faults, 'AsArray', true);
truthFaults.dish = cellfun(@mat2str, truthFaults.dish, 'UniformOutput', false);
writetable(truthFaults, fullfile(outDir, sprintf('hidden_faults_seed%d.csv', seed)));

% timeline figure
tF = (1:F) * P.Tf; nr = numel(specs);
fig = figure('Visible', 'off', 'Position', [0 0 1400 900]);
tl = tiledlayout(fig, 4, 1, 'TileSpacing', 'compact');
ax = nexttile(tl); hold(ax, 'on');
cols = lines(numel(faults));
for i = 1:numel(faults)
    f = faults(i); x0 = (f.t0 - 1)*P.Tf; x1 = max(f.t1, f.t0 + 1)*P.Tf;
    patch(ax, [x0 x1 x1 x0], [i-0.4 i-0.4 i+0.4 i+0.4], cols(i, :), 'EdgeColor', 'none', 'FaceAlpha', 0.7);
    lbl = f.type; if ~isempty(f.dish), lbl = lbl + " (dish " + f.dish + ")"; end
    if f.type == "hop", lbl = lbl + sprintf(" %+d Hz", f.value); end
    if f.type == "glitch", lbl = lbl + sprintf(" %+d samples", f.value); end
    text(ax, x1 + 0.05, i, lbl, 'FontSize', 9);
end
set(ax, 'YTick', [], 'XLim', [0 F*P.Tf]); title(ax, 'Hidden faults (truth; the receiver never sees this)');
ax = nexttile(tl);
st = ["SEARCH", "ALIGN", "DECODE", "FALLBACK"];
[~, sNum] = ismember(R.stateHist, st);
imagesc(ax, (1:numel(sNum))*P.Tf, 1, sNum); colormap(ax, [0.85 0.3 0.3; 0.95 0.75 0.2; 0.2 0.65 0.35; 0.95 0.55 0.1]);
clim(ax, [0.5 4.5]); set(ax, 'YTick', [], 'XLim', [0 F*P.Tf]);
cb = colorbar(ax, 'Ticks', 1:4, 'TickLabels', st); cb.Label.String = '';
title(ax, 'Choir supervisor state (decided on its own)');
ax = nexttile(tl);
okM = vertcat(out.score.ok);
imagesc(ax, tF, 1:nr, okM); colormap(ax, [0.9 0.3 0.3; 0.2 0.65 0.35]); clim(ax, [0 1]);
set(ax, 'YTick', 1:nr, 'YTickLabel', [specs.name], 'XLim', [0 F*P.Tf]);
title(ax, 'Telemetry frames delivered correctly (green) per receiver, same received samples');
ax = nexttile(tl);
W = abs(R.wHist); W = W ./ max(sum(W, 1), eps);
jW = round((R.dec(:, 2) - ch.Toff - 41) / P.L) + 1;
imagesc(ax, jW*P.Tf, 1:P.nDish, W); colormap(ax, parula); colorbar(ax);
set(ax, 'XLim', [0 F*P.Tf]); ylabel(ax, 'dish'); xlabel(ax, 'time (s)');
title(ax, 'Choir: share of each dish in the combined signal');
exportgraphics(fig, fullfile(outDir, 'figures', 'timeline.png'), 'Resolution', 130);
close(fig);

% telemetry: sent vs logged
fig = figure('Visible', 'off', 'Position', [0 0 1400 520]);
ax = axes(fig); hold(ax, 'on'); grid(ax, 'on');
nS = P.nSamp; sent = double(ch.tx.q(:)) / 32767; tS = ((1:numel(sent)) - 1) / nS * P.Tf;
srcName = "synthetic stand-in"; if ch.info.real, srcName = "NASA MSL values"; end
plot(ax, tS, sent, 'Color', [0.75 0.75 0.75], 'LineWidth', 3, 'DisplayName', "sent (" + srcName + ")");
offs = [0, -2.2];
for r = 1:2
    v = nan(size(sent));
    okr = out.score(r).ok;
    for j = find(okr), v((j - 1)*nS + (1:nS)) = sent((j - 1)*nS + (1:nS)); end
    plot(ax, tS, v + offs(r), 'LineWidth', 1.2, 'DisplayName', specs(r).name + sprintf(' (logged, %.0f%% of frames; offset %g)', 100*mean(okr), offs(r)));
end
xlabel(ax, 'time (s)'); ylabel(ax, 'telemetry value (dataset units, -1..1)');
title(ax, sprintf('Telemetry received through 8 simulated dishes with six hidden faults (seed %d)', seed));
src = "synthetic stand-in"; if ch.info.real, src = "real NASA Curiosity (MSL) telemetry, telemanom test set"; end
subtitle(ax, "Payload: " + src, 'Interpreter', 'none');
legend(ax, 'Location', 'southoutside', 'Orientation', 'horizontal');
exportgraphics(fig, fullfile(outDir, 'figures', 'telemetry.png'), 'Resolution', 130);
close(fig);
end
