function out = run_scenario(P, sc, specs, captureFrame)
%RUN_SCENARIO Run several receivers on identical received samples and score them independently.
%   specs: struct array from rx_spec. captureFrame: frame number to keep for spectra (optional).
if nargin < 4, captureFrame = NaN; end
ch = channel_make(P, sc);
RX = cell(1, numel(specs));
for r = 1:numel(specs)
    RX{r} = rx_init(P, specs(r).mode, specs(r).sup);
    RX{r}.captureFrame = captureFrame;
end
genie = struct('Toff', ch.Toff, 'chanBits', ch.tx.chanBits);
for s = 1:sc.F + 2
    [X, ch] = channel_slot(ch, s);
    for r = 1:numel(specs)
        g = []; if specs(r).mode == "genie", g = genie; end
        RX{r} = rx_step(RX{r}, X, s, g);
    end
end
out.ch = ch; out.RX = RX; out.specs = specs;
sc_ = cellfun(@(R) score_run(R, ch), RX, 'UniformOutput', false);
out.score = [sc_{:}];
for r = 1:numel(specs), out.score(r).name = specs(r).name; end
end
