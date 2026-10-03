%RUN_CHOIR_SIM Simulate choir_sim.slx, plot what the scopes show, and check it against the plain MATLAB loop.
here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(fileparts(here), 'src'));
mdl = 'choir_sim';
if ~isfile(fullfile(here, [mdl '.slx'])), build_choir_sim; end
load_system(fullfile(here, [mdl '.slx']));
cfg = ChoirStep(); seed = cfg.Seed; F = cfg.Frames; EsN0dB = cfg.EsN0dB;   % the scenario the block runs

out = sim(mdl);
sig = @(n) squeeze(out.get(n).Data);
t = out.get('sim_state').Time; nSteps = numel(t);
v = sig('sim_verified'); st = sig('sim_state'); nd = sig('sim_dishes'); cc = sig('sim_correct');

P = choir_params();
fig = figure('Visible', 'off', 'Position', [100 100 900 820]);
theme(fig, 'light');
tl = tiledlayout(fig, 4, 1, 'TileSpacing', 'compact');
title(tl, sprintf('choir_sim.slx: Choir receiver in Simulink, one frame per step (seed %d, %d frames, %g dB)', ...
    seed, F, EsN0dB), 'Interpreter', 'none');
ax = nexttile(tl); stairs(ax, t, st, 'LineWidth', 1.5);
ylim(ax, [0.5 4.5]); yticks(ax, 1:4); yticklabels(ax, ["SEARCH", "ALIGN", "DECODE", "FALLBACK"]);
title(ax, 'Receiver state'); grid(ax, 'on');
ax = nexttile(tl); stem(ax, t, v, 'Marker', 'none');
ylim(ax, [0 1.2]); title(ax, 'Verified frame this step (CRC + spacecraft ID + frame count)'); grid(ax, 'on');
ax = nexttile(tl); stairs(ax, t, nd, 'LineWidth', 1.5);
ylim(ax, [0 P.nDish + 0.5]); title(ax, 'Dishes in use'); grid(ax, 'on');
ax = nexttile(tl); plot(ax, t, cc, 'LineWidth', 1.5);
title(ax, 'Cumulative correct frames: scorer (truth), not seen by the receiver'); grid(ax, 'on');
xlabel(ax, 'Simulation time (s)');
exportgraphics(fig, fullfile(here, 'choir_sim_outputs.png'), 'Resolution', 150);
fprintf('Saved choir_sim_outputs.png\n');

try
    print(['-s' mdl], '-dpng', fullfile(here, 'choir_sim_diagram.png'));
    fprintf('Saved choir_sim_diagram.png\n');
catch err
    fprintf('Could not save the block diagram picture: %s\n', err.message);
end

% Same scenario through the plain MATLAB loop (no Simulink), scored by score_run
sc = make_scenario(seed, F, EsN0dB, random_faults(seed, F, P.nDish));
ch = channel_make(P, sc); R = rx_init(P, "choir", true);
for s = 1:sc.F + 2
    [X, ch] = channel_slot(ch, s);
    R = rx_step(R, X, s, []);
    if s == min(nSteps, sc.F + 2), Ssame = score_run(R, ch); end
end
S = score_run(R, ch);
[~, stLoop] = ismember(R.stateHist, ["SEARCH", "ALIGN", "DECODE", "FALLBACK"]);
n = min(nSteps, numel(stLoop));
fprintf('Simulink, %d steps:          %d/%d frames correct (%.1f%%)\n', nSteps, cc(end), F, 100*cc(end)/F);
fprintf('MATLAB loop, same %d slots:  %d/%d frames correct\n', min(nSteps, sc.F + 2), nnz(Ssame.ok), F);
fprintf('MATLAB loop, all %d slots:   %d/%d frames correct (%.1f%%), false accepts %d\n', ...
    sc.F + 2, nnz(S.ok), F, 100*S.correctFrac, S.falseAccepts);
fprintf('Receiver state identical at every one of the first %d steps: %d\n', n, isequal(st(1:n).', stLoop(1:n)));
