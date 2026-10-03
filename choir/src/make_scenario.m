function sc = make_scenario(seed, F, EsN0dB, faults, varargin)
%MAKE_SCENARIO One hidden test case. faults: struct array from fault(); extra name-value pairs override.
if nargin < 4 || isempty(faults)
    faults = struct('type', {}, 't0', {}, 't1', {}, 'dish', {}, 'value', {});
end
sc.seed = seed; sc.F = F; sc.EsN0dB = EsN0dB; sc.cfoHz = 40; sc.lookDf = 150;
sc.faults = reshape(faults, 1, []);
for k = 1:2:numel(varargin), sc.(varargin{k}) = varargin{k + 1}; end
end
