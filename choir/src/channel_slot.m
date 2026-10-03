function [X, ch] = channel_slot(ch, s)
%CHANNEL_SLOT Samples received by every dish during frame period s (nDish x L complex).
%   Applies the hidden fault schedule: dead, fade, noisy, glitch, hop, lookalike, wideband.
P = ch.P; N = P.nDish; L = P.L; rs = ch.rs;
a = ch.a; sig2 = ch.sig2; inrL = -inf; inrW = -inf;
for f = ch.sc.faults
    on = s >= f.t0 && s <= f.t1;
    switch f.type
        case "dead",      if on, a(f.dish) = 0; end
        case "fade",      if on, a = a * f.value; end
        case "noisy",     if on, sig2(f.dish) = sig2(f.dish) * f.value; end
        case "glitch"
            if s == f.t0
                ch.d(f.dish) = ch.d(f.dish) + f.value;
                ch.phi(f.dish) = ch.phi(f.dish) + pi/2 + pi*rand(rs, numel(f.dish), 1);
            end
        case "hop",       if s == f.t0, ch.fc = ch.fc + f.value; end
        case "lookalike", if on, inrL = f.value; end
        case "wideband",  if on, inrW = f.value; end
    end
end
fc = ch.fc + P.driftHzPerS * (s - 1) * P.Tf;
ph = ch.Phi + 2*pi*fc*(1:L)/P.fs; ch.Phi = mod(ph(end), 2*pi);
ch.phi = ch.phi + deg2rad(P.phaseWalkDeg) * randn(rs, N, 1);
n = (s - 1)*L + (1:L);
X = complex(zeros(N, L));
w = ch.tx.wave;
for k = 1:N
    m = n - ch.Toff - ch.d(k);
    ok = m >= 1 & m <= numel(w);
    sk = zeros(1, L); sk(ok) = w(m(ok));
    X(k, :) = a(k) * exp(1j*(ch.phi(k) + ph)) .* sk;
end
ph2 = ch.Phi2 + 2*pi*(fc + ch.sc.lookDf)*(1:L)/P.fs; ch.Phi2 = mod(ph2(end), 2*pi);
if isfinite(inrL)
    c2 = sqrt(10^(inrL/10) * ch.meanSig / ch.tx2.power);
    for k = 1:N
        m = n - ch.Toff2 - ch.d(k); ok = m >= 1 & m <= numel(ch.tx2.wave);
        s2 = zeros(1, L); s2(ok) = ch.tx2.wave(m(ok));
        X(k, :) = X(k, :) + c2 * ch.b2(k) * exp(1j*ch.phi(k)) * (exp(1j*ph2) .* s2);
    end
end
wNew = complex(zeros(1, L));
if isfinite(inrW), wNew = sqrt(10^(inrW/10) * ch.meanSig / 2) * complex(randn(rs, 1, L), randn(rs, 1, L)); end
full = [ch.wTail, wNew]; T = numel(ch.wTail);
if any(full)
    for k = 1:N
        X(k, :) = X(k, :) + ch.bw(k) * exp(1j*ch.phi(k)) * full(T + (1:L) - ch.d(k));
    end
end
ch.wTail = full(end - T + 1:end);
X = X + sqrt(sig2/2) .* complex(randn(rs, N, L), randn(rs, N, L));
ch.truth(s).slot = s; ch.truth(s).fc = fc; ch.truth(s).a = a; ch.truth(s).d = ch.d;
end
