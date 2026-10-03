function S = exp_snr(P, seeds, outDir)
%EXP_SNR Frame success vs per-dish Es/N0 with no faults (frames 11-60 scored, after acquisition).
snrs = [-4 -2 0 2 4 6 8];
[specs, colors, styles] = main_specs();
[I, Se] = ndgrid(1:numel(snrs), 1:numel(seeds));
n = numel(I); nr = numel(specs);
k = zeros(n, nr); fa = zeros(n, nr);
parfor i = 1:n
    out = run_scenario(P, make_scenario(seeds(Se(i)), 60, snrs(I(i)), []), specs);
    k(i, :) = arrayfun(@(s) sum(s.ok(11:60)), out.score);
    fa(i, :) = [out.score.falseAccepts];
end
names = [specs.name];
rows = table(repelem(snrs(I(:)).', nr, 1), repelem(seeds(Se(:)).', nr, 1), repmat(names.', n, 1), ...
    reshape(k.', [], 1), 50*ones(n*nr, 1), reshape(fa.', [], 1), ...
    'VariableNames', {'EsN0_dB', 'seed', 'receiver', 'correct_frames', 'frames', 'false_accepts'});
writetable(rows, fullfile(outDir, 'snr_runs.csv'));
S = groupsummary(rows, {'EsN0_dB', 'receiver'}, 'sum', {'correct_frames', 'frames', 'false_accepts'});
S.success_pct = 100 * S.sum_correct_frames ./ S.sum_frames;
writetable(S, fullfile(outDir, 'snr_summary.csv'));

fig = figure('Visible', 'off', 'Position', [0 0 760 520]);
ax = axes(fig);
K = zeros(numel(snrs), nr); N = K;
for r = 1:nr
    sel = S.receiver == names(r); [~, o] = sort(S.EsN0_dB(sel));
    kk = S.sum_correct_frames(sel); nn = S.sum_frames(sel); K(:, r) = kk(o); N(:, r) = nn(o);
end
plot_success(ax, snrs, K, N, names, colors, styles);
xlabel(ax, 'mean Es/N0 per dish (dB), uncoded BPSK');
title(ax, sprintf('No interference: 8 dishes vs one, %d held-out seeds x 50 frames per point', numel(seeds)));
legend(ax, 'Location', 'southeast');
exportgraphics(fig, fullfile(outDir, 'figures', 'snr.png'), 'Resolution', 150);
close(fig);
end
