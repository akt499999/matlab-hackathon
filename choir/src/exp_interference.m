function S = exp_interference(P, seeds, outDir)
%EXP_INTERFERENCE Main result: interferer strength vs correct Curiosity frames, per receiver.
%   The interferer appears at frame 20 (after lock) and stays; frames 21-60 are scored.
inrs = [-10 -5 0 5 10 15 20];
types = ["wideband", "lookalike"];
[specs, colors, styles] = main_specs();
[I, Ty, Se] = ndgrid(1:numel(inrs), 1:numel(types), 1:numel(seeds));
n = numel(I); nr = numel(specs);
k = zeros(n, nr); fa = zeros(n, nr);
parfor i = 1:n
    sc = make_scenario(seeds(Se(i)), 60, 2, fault(types(Ty(i)), 20, 62, [], inrs(I(i))));
    out = run_scenario(P, sc, specs);
    k(i, :) = arrayfun(@(s) sum(s.ok(21:60)), out.score);
    fa(i, :) = [out.score.falseAccepts];
end
names = [specs.name];
rows = table(repelem(types(Ty(:)).', nr, 1), repelem(inrs(I(:)).', nr, 1), repelem(seeds(Se(:)).', nr, 1), ...
    repmat(names.', n, 1), reshape(k.', [], 1), 40*ones(n*nr, 1), reshape(fa.', [], 1), ...
    'VariableNames', {'interferer', 'inr_dB', 'seed', 'receiver', 'correct_frames', 'frames', 'false_accepts'});
writetable(rows, fullfile(outDir, 'interference_runs.csv'));
S = groupsummary(rows, {'interferer', 'inr_dB', 'receiver'}, 'sum', {'correct_frames', 'frames', 'false_accepts'});
S.success_pct = 100 * S.sum_correct_frames ./ S.sum_frames;
writetable(S, fullfile(outDir, 'interference_summary.csv'));

fig = figure('Visible', 'off', 'Position', [0 0 1300 520]);
tl = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact');
titles = ["Wide-band interferer (radio-source-like, same band)", "Look-alike spacecraft (same CCSDS format, same band)"];
for t = 1:2
    ax = nexttile(tl);
    K = zeros(numel(inrs), nr); N = K;
    for r = 1:nr
        sel = S.interferer == types(t) & S.receiver == names(r);
        [~, o] = sort(S.inr_dB(sel)); kk = S.sum_correct_frames(sel); nn = S.sum_frames(sel);
        K(:, r) = kk(o); N(:, r) = nn(o);
    end
    plot_success(ax, inrs, K, N, names, colors, styles);
    title(ax, titles(t)); xlabel(ax, 'interferer power per dish relative to the spacecraft (dB)');
    if t == 1, legend(ax, 'Location', 'southwest'); end
end
title(tl, sprintf('8 dishes, mean %g dB Es/N0 per dish, %d held-out seeds x 40 frames per point (95%% intervals)', 2, numel(seeds)));
exportgraphics(fig, fullfile(outDir, 'figures', 'interference.png'), 'Resolution', 150);
close(fig);
end
