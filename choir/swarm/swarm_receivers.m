function result = swarm_receivers(message, EsN0dB, freqOffsetHz, phaseDeg, timingFrac, nRx)
%SWARM_RECEIVERS Several receivers learn the exact channel settings together.
%   A typed message is sent as BPSK through a channel with user-set noise and impairments.
%   Every receiver knows the real message and starts from different settings. Each round,
%   each receiver decodes the signal with its current carrier-frequency and timing guess,
%   solves the phase and gain that best match the known message, and scores itself by how
%   far its symbols are from the known ones. Receivers then nudge their settings toward their
%   own best and toward the best receiver so far (particle swarm). Because the noise level is
%   known, the receivers know the best score physically possible and stop when they reach it.
%
%   swarm_receivers                                  % prompts (interactive) or defaults (-batch)
%   swarm_receivers('HELLO MARS', 8, 40, 30, 0.3, 8) % message, Es/N0 dB, freq Hz, phase deg, timing (0-1 symbol), receivers

defaults = {'HELLO FROM MARS', 8, 40, 30, 0.3, 8};
if nargin == 0 && ~batchStartupOptionUsed
    [message, EsN0dB, freqOffsetHz, phaseDeg, timingFrac, nRx] = ask(defaults);
else
    args = defaults;
    given = {};
    if nargin >= 1, given{1} = message; end
    if nargin >= 2, given{2} = EsN0dB; end
    if nargin >= 3, given{3} = freqOffsetHz; end
    if nargin >= 4, given{4} = phaseDeg; end
    if nargin >= 5, given{5} = timingFrac; end
    if nargin >= 6, given{6} = nRx; end
    if nargin >= 1 && nargin <= 2
        rng("shuffle");
        args(3:5) = {round(400 * rand - 200), round(360 * rand - 180), round(rand, 2)};
    end
    args(1:numel(given)) = given;
    [message, EsN0dB, freqOffsetHz, phaseDeg, timingFrac, nRx] = args{:};
end
message = char(message);

P.Rs = 1000;
P.sps = 8;
P.fs = P.Rs * P.sps;
P.h = rrc(0.35, 8, P.sps);
outDir = fullfile(fileparts(mfilename("fullpath")), "results");
if ~isfolder(outDir), mkdir(outDir); end
rng("shuffle");

%% Transmit: message -> bits -> BPSK -> pulse shaping
bits = reshape(dec2bin(double(message), 8).' - '0', [], 1);
sym = 2 * bits - 1;
up = zeros(numel(sym) * P.sps, 1);
up(1:P.sps:end) = sym;
tx = conv(up, P.h);

%% Channel: the user's settings, hidden from the receivers
truth.freq = freqOffsetHz;
truth.phase = deg2rad(phaseDeg);
truth.timing = timingFrac * P.sps;
n = numel(tx);
t = (0:n-1).' / P.fs;
rx = frac_delay(tx, truth.timing) .* exp(1j * (2 * pi * truth.freq * t + truth.phase));
N0 = 1 / 10^(EsN0dB / 10);
rx = rx + sqrt(N0 / 2) * (randn(n, 1) + 1j * randn(n, 1));
floorEVM = N0;

%% Swarm of receivers. Each searches [frequency Hz, timing samples]; phase and gain are solved exactly.
lo = [-250, 0];
hi = [250, P.sps];
X = [lo(1) + ((1:nRx).' - rand(nRx, 1)) * (hi(1) - lo(1)) / nRx, hi(2) * rand(nRx, 1)];
V = zeros(nRx, 2);
pBest = X;
pFit = inf(nRx, 1);
maxIter = 60;
w = 0.6;
c1 = 1.5;
c2 = 1.5;

nSym = numel(sym);
lastBest = inf;
stall = 0;
spreads = 0;
histFit = nan(maxIter, nRx);
histG = nan(maxIter, 4);
fprintf("\n%d receivers, %d-bit message, Es/N0 = %g dB, so the best possible error (EVM) is %.3f\n", nRx, nSym, EsN0dB, floorEVM);
fprintf("Hidden channel: freq %+.1f Hz, phase %+.1f deg, timing %.2f samples\n\n", truth.freq, rad2deg(truth.phase), truth.timing);

for it = 1:maxIter
    K = min(nSym, round(8 * 1.25^(it - 1)));
    for r = 1:nRx
        fit = score(X(r, :), rx, sym, K, P);
        histFit(it, r) = fit;
        if fit < pFit(r)
            pFit(r) = fit;
            pBest(r, :) = X(r, :);
        end
    end
    if K < nSym
        for r = 1:nRx
            pFit(r) = score(pBest(r, :), rx, sym, K, P);
        end
    end
    [~, b] = min(pFit);
    gBest = pBest(b, :);
    [fullFit, fullBER, ~, c] = score(gBest, rx, sym, nSym, P);
    histG(it, :) = [gBest, angle(c), abs(c)];

    done = K == nSym && fullFit < 1.15 * floorEVM;
    if it == 1 || mod(it, 4) == 0 || done
        fprintf("round %2d | %3d/%d symbols | best: receiver %2d | EVM %.3f | bit errors %3d | freq %+8.2f Hz, phase %+6.1f deg, timing %.2f\n", ...
            it, K, nSym, b, fullFit, round(fullBER * nSym), gBest(1), rad2deg(angle(c)), gBest(2));
    end
    if done
        fprintf("\nConverged: within 15%% of the best error possible at this noise level, so these settings are optimal.\n");
        fprintf("Any bit errors left are caused by the noise itself; no setting can remove them.\n");
        break
    end

    if K == nSym
        if fullFit < 0.995 * lastBest
            lastBest = fullFit;
            stall = 0;
        else
            stall = stall + 1;
        end
        if stall >= 4
            if spreads >= 4
                fprintf("\nStopped: no receiver improved after %d spread-outs. Best settings found: EVM %.3f vs the noise limit %.3f.\n", spreads, fullFit, floorEVM);
                break
            end
            spreads = spreads + 1;
            others = setdiff(1:nRx, b);
            move = others(1:ceil(numel(others) / 2));
            X(move, :) = max(min(gBest + randn(numel(move), 2) .* [3, 0.4], hi), lo);
            V(move, :) = 0;
            pFit(move) = inf;
            stall = 0;
            fprintf("round %2d | receivers stalled: %d of them spread out slightly around receiver %d's settings\n", it, numel(move), b);
            continue
        end
    end

    V = w * V + c1 * rand(nRx, 2) .* (pBest - X) + c2 * rand(nRx, 2) .* (gBest - X);
    V = max(min(V, 0.25 * (hi - lo)), -0.25 * (hi - lo));
    X = max(min(X + V, hi), lo);
end
nIt = it;

%% Results
[~, ~, z] = score(gBest, rx, sym, nSym, P);
decodedBits = real(z) > 0;
decoded = char(bin2dec(char(reshape(decodedBits, 8, []).' + '0'))).';
[~, ~, zRaw] = score([0, 0], rx, sym, nSym, P, true);

result.message = string(message);
result.decoded = string(decoded);
result.truth = truth;
result.estimate = struct("freq", gBest(1), "phase", angle(c), "timing", gBest(2), "gain", abs(c));
result.rounds = nIt;
result.bitErrors = sum(decodedBits ~= bits);

fprintf("\n%-14s %10s %10s\n", "setting", "true", "learned");
fprintf("%-14s %10.2f %10.2f\n", "freq (Hz)", truth.freq, gBest(1));
fprintf("%-14s %10.1f %10.1f\n", "phase (deg)", rad2deg(truth.phase), rad2deg(angle(c)));
fprintf("%-14s %10.2f %10.2f\n", "timing (samp)", truth.timing, gBest(2));
fprintf("%-14s %10.2f %10.2f\n", "gain", 1, abs(c));
fprintf("\nSent:    %s\nDecoded: %s\nBit errors: %d of %d after %d rounds\n", message, decoded, result.bitErrors, nSym, nIt);

fig = figure(Visible="off", Position=[100 100 1100 750]);
tiledlayout(2, 2, TileSpacing="compact");
nexttile
semilogy(histFit(1:nIt, :), Color=[0.65 0.65 0.65]);
hold on
semilogy(min(histFit(1:nIt, :), [], 2), "b", LineWidth=2);
yline(floorEVM, "--r", "Best possible at this noise level", LineWidth=1.2);
xlabel("Round");
ylabel("Error vs known message (EVM)");
title("Each receiver (grey) and the best (blue)");
grid on
nexttile
plot(histG(1:nIt, 1), "b", LineWidth=1.5);
yline(truth.freq, "--k", "True");
xlabel("Round");
ylabel("Carrier frequency offset (Hz)");
title("Shared best frequency estimate");
grid on
nexttile
plot(rad2deg(histG(1:nIt, 3)), "b", LineWidth=1.5);
hold on
plot(histG(1:nIt, 2) * 360 / P.sps, "m", LineWidth=1.5);
yline(rad2deg(truth.phase), "--b");
yline(truth.timing * 360 / P.sps, "--m");
xlabel("Round");
ylabel("Degrees");
legend("Phase", "Timing (degrees of a symbol)", Location="best");
title("Shared best phase and timing (dashed = true)");
grid on
nexttile
plot(real(zRaw), imag(zRaw), ".", Color=[0.85 0.33 0.1], MarkerSize=5);
hold on
plot(real(z), imag(z), ".", Color=[0 0.45 0.74], MarkerSize=7);
axis equal
axis([-2.5 2.5 -2.5 2.5]);
grid on
legend("Untuned receiver", "After the swarm converged", Location="southoutside", Orientation="horizontal");
title("Received symbols before and after");
exportgraphics(fig, fullfile(outDir, "swarm_convergence.png"));
writetable(table((1:nIt).', histG(1:nIt, 1), rad2deg(histG(1:nIt, 3)), histG(1:nIt, 2), histG(1:nIt, 4), min(histFit(1:nIt, :), [], 2), ...
    VariableNames=["Round", "Freq_Hz", "Phase_deg", "Timing_samples", "Gain", "BestEVM"]), fullfile(outDir, "swarm_log.csv"));
fprintf("Saved plot and log to %s\n", outDir);
end

function [fit, ber, z, c] = score(s, rx, sym, K, P, raw)
n = numel(rx);
t = (0:n-1).' / P.fs;
y = frac_delay(rx .* exp(-1j * 2 * pi * s(1) * t), -s(2));
y = conv(y, P.h);
idx = numel(P.h) + (0:K-1) * P.sps;
idx = idx(idx <= numel(y));
z = y(idx);
known = sym(1:numel(z));
c = mean(z .* known);
if nargin < 6 || ~raw
    z = z / c;
end
fit = mean(abs(z - known).^2);
ber = mean((real(z) > 0) ~= (known > 0));
end

function y = frac_delay(x, d)
n = numel(x);
f = [0:ceil(n/2)-1, -floor(n/2):-1].' / n;
y = ifft(fft(x) .* exp(-1j * 2 * pi * f * d));
end

function h = rrc(beta, span, sps)
t = (-span * sps / 2 : span * sps / 2).' / sps;
h = zeros(size(t));
for i = 1:numel(t)
    ti = t(i);
    if abs(ti) < 1e-12
        h(i) = 1 - beta + 4 * beta / pi;
    elseif abs(abs(4 * beta * ti) - 1) < 1e-12
        h(i) = beta / sqrt(2) * ((1 + 2/pi) * sin(pi / (4 * beta)) + (1 - 2/pi) * cos(pi / (4 * beta)));
    else
        h(i) = (sin(pi * ti * (1 - beta)) + 4 * beta * ti * cos(pi * ti * (1 + beta))) / (pi * ti * (1 - (4 * beta * ti)^2));
    end
end
h = h / sqrt(sum(h.^2));
end

function [message, EsN0dB, f, ph, tau, nRx] = ask(d)
fprintf("\n--- Swarm receivers: press Enter to keep each default ---\n");
message = input(sprintf("Message [%s]: ", d{1}), "s");
if isempty(strtrim(message)), message = d{1}; end
EsN0dB = num(input(sprintf("Noise: signal strength Es/N0 in dB, lower = noisier [%g]: ", d{2}), "s"), d{2});
f = num(input(sprintf("Carrier frequency offset in Hz, -250 to 250 [%g]: ", d{3}), "s"), d{3});
ph = num(input(sprintf("Phase offset in degrees [%g]: ", d{4}), "s"), d{4});
tau = num(input(sprintf("Timing offset as a fraction of a symbol, 0 to 1 [%g]: ", d{5}), "s"), d{5});
nRx = round(num(input(sprintf("Number of receivers [%g]: ", d{6}), "s"), d{6}));
end

function v = num(s, d)
v = str2double(s);
if isnan(v), v = d; end
end
