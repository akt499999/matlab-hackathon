function plot_success(ax, x, k, n, names, colors, styles)
%PLOT_SUCCESS Success rate (%) with 95% Clopper-Pearson intervals; k, n are counts (numel(x) x receivers).
hold(ax, 'on'); grid(ax, 'on');
for r = 1:size(k, 2)
    [p, ci] = binofit(k(:, r), n(:, r));
    lw = 1.4; if contains(names(r), "Choir"), lw = 2.6; end
    errorbar(ax, x, 100*p, 100*(p - ci(:, 1)), 100*(ci(:, 2) - p), styles(r), 'Color', colors(r, :), ...
        'LineWidth', lw, 'MarkerSize', 5, 'MarkerFaceColor', colors(r, :), 'CapSize', 3, 'DisplayName', names(r));
end
ylim(ax, [-3 103]); ylabel(ax, 'telemetry frames delivered correctly (%)');
end
