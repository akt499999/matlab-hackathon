function tx = tx_build(P, F, scid, vals)
%TX_BUILD CCSDS TM waveform (Satellite Communications Toolbox) carrying F frames of telemetry.
gen = ccsdsTMWaveformGenerator("ChannelCoding", "none", "Modulation", "BPSK", ...
    "SamplesPerSymbol", P.sps, "RolloffFactor", P.rolloff, "FilterSpanInSymbols", P.span, ...
    "NumBytesInTransferFrame", P.nBytes, "HasRandomizer", true, "HasASM", true);
bits = false(P.nBits, F); q = zeros(P.nSamp, F, 'int16');
for f = 1:F
    [bits(:, f), q(:, f)] = frame_pack(vals((f - 1)*P.nSamp + (1:P.nSamp)), f - 1, scid, P);
end
tx.wave = [gen(double(bits(:))); gen(zeros(P.nBits, 1))];   % second call flushes the filter tail
tx.bits = bits; tx.q = q; tx.F = F; tx.scid = scid;
tx.chanBits = [repmat(P.asm, 1, F); xor(bits, P.pn)];       % what goes on air, per frame
tx.power = mean(abs(tx.wave(1:F*P.L)).^2);
end
