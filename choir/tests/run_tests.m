%RUN_TESTS Checks that Choir's claims depend on. Run from anywhere: run('tests/run_tests.m').
here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, '..', 'src'));
P = choir_params();
pass = @(msg) fprintf('PASS  %s\n', msg);

% 1. CRC: x^16+x^12+x^5+1, register preset to ones -> standard check value 0x29B1 for "123456789"
cw = crcGenerate(int2bit(double('123456789').', 8), P.crc);
v = bit2int(cw(end - 15:end), 16);
assert(v == hex2dec('29B1'), 'CRC check value 0x%04X, expected 0x29B1', v);
pass('CRC-16/CCITT-FALSE check value 0x29B1');

% 2. frame round trip; a single flipped bit is caught
[b, q] = frame_pack(linspace(-0.9, 0.9, P.nSamp).', 300, P.scid, P);
f = frame_parse(b, P);
assert(f.crcOK && f.scid == P.scid && f.count == mod(300, 256) && isequal(f.q, q));
b(100) = ~b(100);
assert(~frame_parse(b, P).crcOK);
pass('frame pack/parse round trip; one flipped bit is rejected');

% 3. SNR calibration: one dish, known timing, bit error rate vs BPSK theory at Es/N0 = 4 dB
tx = tx_build(P, 40, P.scid, zeros(40*P.nSamp, 1));
rs = RandStream('twister', 'Seed', 5); EsN0 = 10^(4/10);
a = sqrt(EsN0 / (tx.power * P.sps));
x = a*tx.wave + sqrt(0.5)*complex(randn(rs, size(tx.wave)), randn(rs, size(tx.wave)));
y = filter(P.rrc, 1, x);
sym = y(41 + (0:40*P.nSym - 1)*P.sps);
ber = mean((real(sym) > 0) ~= reshape(tx.chanBits, [], 1));
theory = 0.5*erfc(sqrt(EsN0));
assert(abs(ber/theory - 1) < 0.2, 'BER %.4g vs theory %.4g', ber, theory);
pass(sprintf('noise calibration: BER %.4f vs BPSK theory %.4f at 4 dB', ber, theory));

% 4. full receiver, one clean dish: every frame after acquisition is logged and exact
P1 = choir_params('nDish', 1);
out = run_scenario(P1, make_scenario(11, 30, 15, []), rx_spec("choir", true));
assert(all(out.score.ok(8:end)) && out.score.falseAccepts == 0);
pass(sprintf('clean loopback through the full receiver: %d/30 frames exact (first ones spent on acquisition)', sum(out.score.ok)));

% 5. pure noise never produces a logged frame (supervised: stays in SEARCH; unsupervised: decodes noise)
out = run_scenario(P, make_scenario(12, 40, -100, []), rx_spec("choir", true));
assert(isempty(out.RX{1}.qT));
out = run_scenario(P, make_scenario(13, 70, 4, fault("fade", 15, 72, [], 0)), rx_spec("choir", false));
noiseTries = sum(out.RX{1}.dec(:, 1) > 16);
assert(out.score.falseAccepts == 0 && ~any(out.RX{1}.dec(out.RX{1}.dec(:, 1) > 16, 6)));
pass(sprintf('pure noise: 0 frames logged (and 0 of %d forced decode attempts on noise accepted)', noiseTries));

% 6. fairness: without interference SUMPLE and equal gain are close to the bound
k = zeros(1, 3);
for s = 1:3
    out = run_scenario(P, make_scenario(20 + s, 50, 1, []), [rx_spec("sumple", true), rx_spec("egc", true), rx_spec("genie", true)]);
    k = k + arrayfun(@(sc) sum(sc.ok(11:50)), out.score);
end
assert(all(k(1:2) >= k(3) - 6), 'baselines unexpectedly weak: %s', mat2str(k));
pass(sprintf('fair baselines: SUMPLE %d, equal gain %d, bound %d of 120 frames at 1 dB, no interference', k));

% 7. the receiver cannot be handed the truth
try
    rx_step(rx_init(P, "choir", true), complex(zeros(P.nDish, P.L)), 1, struct('Toff', 1));
    error('choir:test', 'truth was accepted');
catch e
    assert(~strcmp(e.identifier, 'choir:test'));
end
pass('only the analysis bound may receive the true bits');
