function R = rx_step(R, X, slot, genie)
%RX_STEP Feed one frame period of samples (nDish x L) to the receiver and let it act on its own.
%   States: SEARCH (find the carrier) -> ALIGN (find frames and dish delays) -> DECODE
%   -> FALLBACK (safe mode) -> SEARCH. genie is [] for every real receiver.
assert(isempty(genie) || R.mode == "genie", 'only the genie bound may see the truth');
P = R.P;
R.buf = [R.buf, X]; R.nRecv = R.nRecv + size(X, 2);
keep = (P.searchFrames + 1)*P.L + 600;
if size(R.buf, 2) > keep
    drop = size(R.buf, 2) - keep;
    R.buf(:, 1:drop) = []; R.bufStart = R.bufStart + drop;
end
c0 = tic;
if R.state == "SEARCH", R = do_search(R, slot); end
if R.state == "ALIGN", R = do_align(R, slot, genie); end
while any(R.state == ["DECODE", "FALLBACK"]) && R.t + max(R.dl) + (P.nSym - 1)*P.sps + 2 <= R.nRecv
    R = do_frame(R, slot, genie);
end
R.cpu = R.cpu + toc(c0);
R.stateHist(slot) = R.state;
end

% ---------------------------------------------------------------- SEARCH
function R = do_search(R, slot)
% Carrier search: squaring BPSK leaves a tone at twice the carrier offset; sum spectra over dishes.
P = R.P; nWin = P.searchFrames * P.L;
if R.nRecv - max(R.searchFrom, R.bufStart) + 1 < nWin, return; end
x = R.buf(:, end - nWin + 1:end);
nfft = 2^nextpow2(nWin);
S = sum(abs(fft(x.^2, nfft, 2)).^2, 1);
b = 0:nfft - 1; f = (b - (b >= nfft/2)*nfft) * P.fs / nfft / 2;
for fr = R.rejectF, S(abs(f - fr) < 60) = 0; end
[pk, i] = max(S); ratio = pk / median(S);
R.searchFrom = R.nRecv + 1;
if ratio < P.searchThr
    R = logit(R, slot, "no carrier", sprintf('spectral peak/median %.1f < %g', ratio, P.searchThr));
    return
end
il = mod(i - 2, nfft) + 1; ir = mod(i, nfft) + 1;
den = S(il) - 2*S(i) + S(ir); dlt = 0;
if den ~= 0, dlt = 0.5*(S(il) - S(ir))/den; end
R.fhat = f(i) + dlt * P.fs / nfft / 2;
R = logit(R, slot, "carrier found", sprintf('%+.1f Hz (spectral peak/median %.0f)', R.fhat, ratio));
R.state = "ALIGN"; R.alignTries = 0;
end

% ---------------------------------------------------------------- ALIGN
function R = do_align(R, slot, genie)
% Find frame timing (sync marker over one full frame period) and each dish's delay.
P = R.P; L = P.L; need = 2*L + 200;
if R.nRecv - R.bufStart + 1 < need, return; end
nA = R.nRecv - need + 1;
x = R.buf(:, nA - R.bufStart + 1:end);
x = x .* exp(-2j*pi*R.fhat*(0:size(x, 2) - 1)/P.fs);
y = filter(P.rrc, 1, x, [], 2);
a = zeros(1, 31*P.sps + 1); a(1:P.sps:end) = 2*double(P.asm.') - 1;
lag = numel(a) - 1;
c = filter(fliplr(a), 1, y, [], 2);            % c(:, u + lag): sync-marker match for a frame starting at u
u = 41:(40 + L);
M = sum(movmax(abs(c(:, u + lag)).^2, 2*P.maxDelay + 1, 2), 1);
[~, order] = sort(M, 'descend');
picked = []; foreign = false;
for cand = order
    if numel(picked) == 3, break; end
    if any(abs(u(cand) - picked) < 64), continue; end
    u0 = u(cand); picked(end + 1) = u0; %#ok<AGROW>
    dl = zeros(P.nDish, 1); g = zeros(P.nDish, 1);
    for k = 1:P.nDish
        win = (u0 - P.alignWin):(u0 + P.alignWin);
        win = win(win >= 41 & win + lag <= size(c, 2));
        [~, j] = max(abs(c(k, win + lag)));
        dl(k) = win(j) - u0; g(k) = c(k, win(j) + lag) / 32;
    end
    t = nA - 1 + u0;
    R2 = R; R2.t = t; R2.dl = dl; R2.hAsm = g; R2.up = true(P.nDish, 1);
    D = decode_at(R2, t, dl, genie, true);
    if D.ours
        R = R2; R.state = "DECODE"; R.fresh = true; R.fails = 0; R.w = g;
        R.snrEst = asm_snr(D.Y, g, P);
        R.lastCount = NaN; R.h = zeros(P.nDish, 1); R.prevVerNA = NaN; R.fit(:) = NaN;
        R = logit(R, slot, "aligned", sprintf('frame found; relative dish delays %s samples', mat2str(dl.' - min(dl))));
        return
    elseif D.crcOK
        foreign = true;
        R = logit(R, slot, "foreign frame", sprintf('valid frame from spacecraft %d, not ours (%d): ignored', D.scid, P.scid));
    end
end
R.alignTries = R.alignTries + 1;
if foreign
    R.rejectF(end + 1) = R.fhat;
    R = logit(R, slot, "carrier rejected", sprintf('%+.1f Hz belongs to another spacecraft; searching elsewhere', R.fhat));
    R = to_search(R);
elseif R.alignTries >= 3
    R = logit(R, slot, "align failed", 'no verified frame after 3 tries');
    R = to_search(R);
end
end

% ---------------------------------------------------------------- DECODE / FALLBACK
function R = do_frame(R, slot, genie)
P = R.P; t = R.t;
D = decode_at(R, t, R.dl, genie, R.state == "FALLBACK");
R.nFrames = R.nFrames + 1;
expected = mod(R.lastCount + round((t - R.lastT)/P.L), 256);
verified = D.ours && (isnan(R.lastCount) || D.count == expected);
R.dec(end + 1, :) = [slot, t, D.count, D.crcOK, D.scid, verified];
R.hAsm = blend(R.hAsm, D.gA, P.lambda);
R.snrEst = 0.9*R.snrEst + 0.1*asm_snr(D.Y, D.gA, P);
if R.mode == "sumple", R.w = D.w; end
R.wHist(:, end + 1) = D.w;
if R.captureFrame == R.nFrames, R.capture = D; R.capture.dl = R.dl; R.capture.fhat = R.fhat; end
R = explain_covariance(R, slot, D.qInfo);
if verified
    s = 2*double([P.asm.', D.air]) - 1;           % the verified frame, re-modulated: a clean reference
    hNew = D.Y * s.' / P.nSym;
    if any(R.h) && abs(D.nA - R.prevVerNA - P.L) <= 2*P.realignWin
        dn = D.nA - R.prevVerNA;                  % fine carrier tracking between consecutive verified frames
        fres = angle(exp(1j*(angle(R.h' * hNew) - 2*pi*R.fhat*dn/P.fs))) / (2*pi*dn/P.fs);
        R.fhat = R.fhat + 0.5*fres;
    end
    if R.state == "FALLBACK", R.h = hNew; else, R.h = blend(R.h, hNew, P.lambda); end
    R.q{end + 1} = D.q; R.qT(end + 1) = t;
    if R.state ~= "DECODE" || R.fresh
        R = logit(R, slot, "locked", sprintf('verified frame (count %d, spacecraft %d); weights now learned from verified frames', D.count, D.scid));
    end
    R.state = "DECODE"; R.fresh = false; R.fails = 0; R.everLocked = true;
    R.lastCount = D.count; R.lastT = t; R.prevVerNA = D.nA;
    if R.sup, R = health(R, slot, D, s, hNew); end
else
    R.fails = R.fails + 1;
    if D.crcOK && D.scid ~= P.scid
        R = logit(R, slot, "foreign frame", sprintf('valid frame from spacecraft %d, not ours: not learned from', D.scid));
    end
    if R.fresh && R.fails >= 2 && (R.sup || ~R.everLocked)
        R = logit(R, slot, "lost after align", 'first frames did not verify');
        R = to_search(R);
    elseif R.sup && R.state == "DECODE" && R.fails >= P.failToFallback
        R = realign_asm(R);
        R.state = "FALLBACK";
        R = logit(R, slot, "safe mode", sprintf('%d bad frames in a row: re-aligned every dish on the sync marker, equal weights', R.fails));
    elseif R.sup && R.state == "FALLBACK" && R.fails >= P.failToLost
        R = logit(R, slot, "lost", sprintf('%d bad frames in a row: full carrier re-search', R.fails));
        R = to_search(R);
    end
end
if any(R.state == ["DECODE", "FALLBACK"]), R.t = t + P.L; end
end

function D = decode_at(R, t, dl, genie, safe)
% Demodulate the frame whose reference sync marker starts at sample t, using the mode's weights.
P = R.P;
nA = t + min(dl) - 40; nB = t + max(dl) + (P.nSym - 1)*P.sps;
x = R.buf(:, nA - R.bufStart + 1:nB - R.bufStart + 1);
x = x .* exp(-2j*pi*R.fhat*(0:nB - nA)/P.fs);
y = filter(P.rrc, 1, x, [], 2);
Y = complex(zeros(P.nDish, P.nSym));
for k = 1:P.nDish
    Y(k, :) = y(k, t + dl(k) - nA + 1 + (0:P.nSym - 1)*P.sps);
end
sA = 2*double(P.asm.') - 1;
gA = Y(:, 1:32) * sA.' / 32;                       % this frame's sync-marker estimate per dish
up = R.up; Yu = Y(up, :); nu = nnz(up); qInfo = nan(1, 3);
hA = blend(R.hAsm, gA, P.lambda); hAu = hA(up);
if safe || (R.mode == "choir" && R.fresh)
    wu = gA(up) ./ max(abs(gA(up)), eps);
else
    switch R.mode
        case "choir"
            % verified signature, but a dish whose sync-marker match collapsed this frame
            % (sudden timing or hardware change) sits out until the health check re-times it
            hU = R.h(up); use = abs(gA(up)) >= 0.35*abs(hU);
            if nnz(use) < 2, use(:) = true; end
            [wTmp, qi] = mvdr(Yu(use, :), hU(use));
            wu = zeros(nu, 1); wu(use) = wTmp;
            idxUp = find(up); idxUse = idxUp(use); qi(3) = idxUse(qi(3)); qInfo = qi;
        case "sync",   wu = mvdr(Yu, hAu);
        case "egc",    wu = hAu ./ max(abs(hAu), eps);
        case "best"
            snr = R.snrEst(up);
            [~, kb] = max(snr); wu = zeros(nu, 1); wu(kb) = hAu(kb) / max(abs(hAu(kb)), eps);
        case "sumple", wu = sumple(Yu, R.w(up), P.sumpleIters);
        case "genie"
            j = min(max(round((t - genie.Toff - 41) / P.L) + 1, 1), size(genie.chanBits, 2));
            sT = 2*double(genie.chanBits(:, j).') - 1;
            wu = mvdr(Yu, Yu * sT.' / P.nSym);
    end
end
w = zeros(P.nDish, 1); w(up) = wu;
z = w' * Y;
cA = z(1:32) * sA.';
z = z * conj(cA) / max(abs(cA), eps);              % resolve the common phase on the sync marker
edges = round(linspace(33, P.nSym + 1, 9));
for b = 1:8                                        % clean up residual carrier rotation within the frame
    idx = edges(b):edges(b + 1) - 1;
    z(idx) = z(idx) * exp(-1j*angle(sum(z(idx) .* sign(real(z(idx))))));
end
air = real(z(33:end)) > 0;
fr = frame_parse(xor(air.', P.pn), P);
D.Y = Y; D.gA = gA; D.nA = nA; D.w = w; D.z = z; D.air = air; D.x = x; D.qInfo = qInfo;
D.crcOK = fr.crcOK; D.scid = fr.scid; D.count = fr.count; D.q = fr.q;
D.ours = fr.crcOK && fr.scid == P.scid;
end

% ---------------------------------------------------------------- dish health
function R = health(R, slot, D, s, hNew)
% A dish whose match to the verified frame collapses (while the others hold) is re-aligned or excluded.
P = R.P;
fit = abs(hNew) ./ sqrt(mean(abs(D.Y).^2, 2));
R.fit = [R.fit(:, 2:end), fit];
usual = median(R.fit, 2, 'omitnan');
rel = fit ./ usual;
others = median(rel(R.up), 'omitnan');
bad = find(R.up & rel < P.fitDrop & others > 0.7 & sum(~isnan(R.fit), 2) >= 4);
for k = bad.'
    [R, ok, shift, f2] = realign_ref(R, k, s, D.nA);
    if ok
        R = logit(R, slot, "dish re-aligned", sprintf('dish %d stopped matching verified frames (fit %.2f -> %.2f); timing moved %+d samples, fit now %.2f', k, usual(k), fit(k), shift, f2));
        R.fit(k, :) = NaN;
    else
        R.up(k) = false;
        R = logit(R, slot, "dish down", sprintf('dish %d stopped matching verified frames (fit %.2f -> %.2f) and was not found nearby: excluded', k, usual(k), fit(k)));
    end
end
if any(~R.up) && R.nFrames - R.lastProbe >= P.probeEvery
    R.lastProbe = R.nFrames;
    for k = find(~R.up).'
        [R2, ok, shift, f2] = realign_ref(R, k, s, D.nA);
        if ok && f2 > 0.5*median(fit(R.up))
            R = R2; R.up(k) = true; R.fit(k, :) = NaN;
            R = logit(R, slot, "dish back", sprintf('probe found dish %d again (fit %.2f, timing %+d samples): re-included', k, f2, shift));
        end
    end
end
end

function [R, ok, shift, fitv] = realign_ref(R, k, s, nRef)
% Search dish k's timing (+/- realignWin samples) against the full verified frame; on success the
% dish's signature is re-measured in the same phase reference (nRef) as the rest of the array.
P = R.P; W = P.realignWin; t = R.t;
nA = t + R.dl(k) - 40 - W; nB = t + R.dl(k) + (P.nSym - 1)*P.sps + W;
ok = false; shift = 0; fitv = 0;
if nA < R.bufStart || nB > R.nRecv, return; end
x = R.buf(k, nA - R.bufStart + 1:nB - R.bufStart + 1) .* exp(-2j*pi*R.fhat*((0:nB - nA) + nA - nRef)/P.fs);
y = filter(P.rrc, 1, x);
base = t + R.dl(k) - nA + 1 + (0:P.nSym - 1)*P.sps;
v = complex(zeros(1, 2*W + 1));
for dd = -W:W, v(dd + W + 1) = y(base + dd) * s.'; end
[best, j] = max(abs(v));
fitv = best / P.nSym / sqrt(mean(abs(y(41:end)).^2));
shift = j - W - 1;
ok = fitv > P.fitOK;
if ok, R.dl(k) = R.dl(k) + shift; R.h(k) = v(j) / P.nSym; end
end

function R = realign_asm(R)
% Safe mode entry: re-find every dish's timing on the current frame's sync marker.
P = R.P; W = P.realignWin; t = R.t;
nA = t + min(R.dl) - 40 - W; nB = t + max(R.dl) + 31*P.sps + W;
if nA < R.bufStart || nB > R.nRecv, return; end
x = R.buf(:, nA - R.bufStart + 1:nB - R.bufStart + 1) .* exp(-2j*pi*R.fhat*(0:nB - nA)/P.fs);
y = filter(P.rrc, 1, x, [], 2);
sA = 2*double(P.asm.') - 1;
for k = 1:P.nDish
    base = t + R.dl(k) - nA + 1 + (0:31)*P.sps;
    v = zeros(1, 2*W + 1);
    for dd = -W:W, v(dd + W + 1) = abs(y(k, base + dd) * sA.'); end
    [~, j] = max(v);
    R.dl(k) = R.dl(k) + j - W - 1;
    R.hAsm(k) = y(k, base + j - W - 1) * sA.' / 32;
end
R.up = true(P.nDish, 1); R.fit(:) = NaN;
end

% ---------------------------------------------------------------- helpers
function R = explain_covariance(R, slot, qi)
% Log (only) what the weights are reacting to: a source reaching many dishes, or one noisy dish.
if any(isnan(qi)), return; end
kind = "none";
if qi(1) > 10 && qi(2) > R.P.nDish/2, kind = "interference";
elseif qi(1) > 6 && qi(2) < 2, kind = "noisy dish"; end
if kind == R.explained, return; end
if kind == "interference"
    R = logit(R, slot, "interference", sprintf('a strong extra source reaches %.0f dishes (%.0f dB over noise); weights now cancel it', qi(2), qi(1)));
elseif kind == "noisy dish"
    R = logit(R, slot, "noisy dish", sprintf('dish %d is %.0f dB noisier than the floor; its weight drops', qi(3), qi(1)));
elseif qi(1) < 5
    R = logit(R, slot, "all clear", sprintf('no extra source above %.0f dB', qi(1)));
else
    return
end
R.explained = kind;
end

function snr = asm_snr(Y, g, P)
% Per-dish SNR from the sync marker: signal from the fit, noise from what the fit leaves over.
sA = 2*double(P.asm.') - 1;
snr = abs(g).^2 ./ max(mean(abs(Y(:, 1:32) - g*sA).^2, 2), 1e-12);
end

function R = to_search(R)
R.state = "SEARCH"; R.searchFrom = R.nRecv + 1; R.fresh = true; R.fails = 0;
end

function h = blend(h, hNew, lambda)
% Exponential memory of a channel estimate; the old estimate is rotated to the new common phase first.
if ~any(h), h = hNew; return; end
h = lambda * h * exp(1j*angle(h' * hNew)) + (1 - lambda) * hNew;
end

function [w, info] = mvdr(Y, h)
% Weights that keep the spacecraft (signature h) and minimize everything else. Everything else is
% estimated as the frame's covariance minus the spacecraft's own part, floored at the noise level,
% so a slightly-off h cannot make the array cancel the spacecraft itself.
% info = [strongest extra component over the noise floor (dB), number of dishes it spans, main dish]
Rx = (Y*Y') / size(Y, 2);
Q = Rx - h*h'; Q = (Q + Q')/2;
[V, E] = eig(Q);
e = max(real(diag(E)), min(real(eig(Rx))));
w = (V * diag(1./e) * V') * h;
[eMax, i] = max(e); v = V(:, i);
[~, kMax] = max(abs(v));
info = [10*log10(eMax/min(e)), 1/sum(abs(v).^4), kMax];
end

function w = sumple(Y, w, iters)
% SUMPLE: each dish is correlated with the sum of the others (blind; no knowledge of the data).
for it = 1:iters
    z = w' * Y;
    for k = 1:size(Y, 1)
        w(k) = Y(k, :) * (z - w(k)' * Y(k, :))' / size(Y, 2);
    end
    w = w / max(norm(w), eps) * sqrt(numel(w));
end
end

function R = logit(R, slot, event, reason)
R.log(end + 1, :) = {slot, R.state, string(event), string(reason)};
end
