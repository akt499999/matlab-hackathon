function f = fault(type, t0, t1, dish, value)
%FAULT One hidden fault: type in dead | fade | noisy | glitch | hop | lookalike | wideband.
%   t0..t1 frame periods; dish = affected dishes; value = gain, noise factor, samples, Hz or dB.
f = struct('type', string(type), 't0', t0, 't1', t1, 'dish', dish, 'value', value);
end
