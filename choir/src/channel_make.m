function ch = channel_make(P, sc)
%CHANNEL_MAKE Hidden truth for one run: our spacecraft's waveform, the dishes, the interferers and
%   the fault schedule. Only channel_slot reads this; the receiver never sees it.
%   sc fields: seed, F (frames), EsN0dB (mean per-dish Es/N0), cfoHz, lookDf (Hz), faults (struct array).
rs = RandStream('twister', 'Seed', sc.seed);
N = P.nDish;
[vals, info] = telemetry_source(sc.F * P.nSamp);
ch.P = P; ch.sc = sc; ch.rs = rs; ch.info = info; ch.vals = vals;
ch.tx = tx_build(P, sc.F, P.scid, vals);
ch.EsN0dB = sc.EsN0dB + P.snrSpreadDB * (2*rand(rs, N, 1) - 1);
ch.a = sqrt(10.^(ch.EsN0dB/10) / (ch.tx.power * P.sps));     % unit noise power per sample
ch.d = 16 + randi(rs, [0 P.maxDelay], N, 1);                 % residual per-dish delay (cables, clocks)
ch.phi = 2*pi*rand(rs, N, 1);
ch.Toff = randi(rs, [1 P.L]);                                 % unknown start of the first frame
ch.fc = sc.cfoHz; ch.Phi = 0;
ch.sig2 = ones(N, 1);
ch.meanSig = mean(ch.a.^2) * ch.tx.power;
other = 0.5*sin(2*pi*(0:sc.F*P.nSamp - 1).'/313);
ch.tx2 = tx_build(P, sc.F, P.scidOther, other);               % look-alike spacecraft, same format and band
ch.b2 = exp(2j*pi*rand(rs, N, 1));
ch.Toff2 = randi(rs, [1 P.L]); ch.Phi2 = 0;
ch.bw = exp(2j*pi*rand(rs, N, 1));                            % wide-band point source (radio-source-like)
ch.wTail = complex(zeros(1, 64));                             % wide-band source history for per-dish delays
% Interferers come from near the spacecraft's direction, so they share each dish's residual delay and
% instrumental phase; their own geometry shows up only as a different RF phase per dish (b2, bw).
ch.truth = struct('slot', {}, 'fc', {}, 'a', {}, 'd', {});
end
