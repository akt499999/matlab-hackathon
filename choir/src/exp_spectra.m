function exp_spectra(P, outDir)
%EXP_SPECTRA Before/after spectra (required Track 1 output): one dish's input vs the combined output.
%   Spectra are in dB relative to one dish's thermal noise; combined outputs are scaled to equal noise.
specs = [rx_spec("choir", true, "Choir"), rx_spec("sumple", true, "SUMPLE")];
cases = {make_scenario(201, 40, 2, []), make_scenario(202, 40, 2, fault("wideband", 15, 42, [], 10))};
ttl = ["No interference (mean 2 dB Es/N0 per dish)", "Wide-band interferer +10 dB per dish (same band)"];
fig = figure('Visible', 'off', 'Position', [0 0 1300 480]);
tl = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact');
for c = 1:2
    out = run_scenario(P, cases{c}, specs(1), 25);
    ax = nexttile(tl); hold(ax, 'on'); grid(ax, 'on');
    D = out.RX{1}.capture;                         % Choir's frame; SUMPLE weights are computed on the same samples
    [p, f] = pwelch(D.x(1, :), hann(1024), 512, 1024, P.fs, 'centered');
    plot(ax, f/1e3, 10*log10(p*P.fs), 'Color', [0.5 0.5 0.5], 'LineWidth', 1.2, 'DisplayName', 'before: one dish');
    sty = {[0.1 0.65 0.3], [0.9 0.4 0.1]};
    sh = D.dl - min(D.dl); Lc = size(D.x, 2) - max(sh);
    xa = complex(zeros(P.nDish, Lc));
    for k = 1:P.nDish, xa(k, :) = D.x(k, sh(k) + (1:Lc)); end
    wS = ones(P.nDish, 1);
    for it = 1:20
        z = wS' * D.Y;
        for k = 1:P.nDish, wS(k) = D.Y(k, :) * (z - wS(k)' * D.Y(k, :))' / size(D.Y, 2); end
        wS = wS / norm(wS);
    end
    W = {D.w, wS};
    for r = [2 1]
        zc = (W{r}' * xa) / max(norm(W{r}), eps);
        [p, f] = pwelch(zc, hann(1024), 512, 1024, P.fs, 'centered');
        plot(ax, f/1e3, 10*log10(p*P.fs), 'Color', sty{r}, 'LineWidth', 1.8, 'DisplayName', "after: " + specs(r).name + " (8 dishes)");
    end
    xline(ax, [-1 1]*P.Rs*(1 + P.rolloff)/2/1e3, ':', 'HandleVisibility', 'off');
    xlabel(ax, 'frequency offset (kHz)'); ylabel(ax, 'power density re one dish''s noise (dB)');
    title(ax, ttl(c)); legend(ax, 'Location', 'south');
end
exportgraphics(fig, fullfile(outDir, 'figures', 'spectra.png'), 'Resolution', 150);
close(fig);
end
