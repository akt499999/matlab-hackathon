%MAKE_MATLAB_SHOTS Render the seed-301 decision log as a MATLAB table (uitable) for the slides.
here = fileparts(mfilename('fullpath'));
res = fullfile(fileparts(here), 'results');
lg = readtable(fullfile(res, 'decision_log_seed301.csv'), 'TextType', 'string');
keep = ismember(lg.event, ["interference", "dish down", "noisy dish", "safe mode", "lost", ...
    "carrier found", "dish re-aligned", "dish back"]) & lg.slot > 4;
T = lg(keep, {'time_s', 'state', 'event', 'reason'});
fig = uifigure('Visible', 'off', 'Position', [100 100 1500 384], 'Color', 'w');
t = uitable(fig, 'Data', T, 'Position', [10 10 1480 364], 'FontSize', 15, ...
    'ColumnName', {'time (s)', 'state', 'event', 'reason (program output)'}, ...
    'ColumnWidth', {90, 110, 150, 'auto'}, 'RowName', {});
drawnow;
exportapp(fig, fullfile(here, 'figs', 'matlab_decision_log.png'));
fprintf('decision log rows shown: %d\n', height(T));
