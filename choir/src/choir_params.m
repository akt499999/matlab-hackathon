function P = choir_params(varargin)
%CHOIR_PARAMS All Choir settings in one place. Name-value pairs override the defaults.
%   Receiver thresholds are fixed here before evaluation; nothing is tuned per scenario.

% link and waveform (CCSDS TM, uncoded BPSK)
P.nDish       = 8;
P.sps         = 4;            % samples per symbol
P.rolloff     = 0.35;         % root-raised-cosine roll-off
P.span        = 10;           % RRC span (symbols)
P.Rs          = 64e3;         % symbol rate (symbols/s)
P.nBytes      = 223;          % transfer frame length (bytes)
P.scid        = 42;           % our simulated spacecraft ID (not MSL's real ID)
P.scidOther   = 21;           % the look-alike spacecraft's ID
P.nSamp       = 107;          % int16 telemetry samples per frame

% simulated dishes
P.snrSpreadDB = 3;            % per-dish Es/N0 spread around the run's mean (+/- dB)
P.maxDelay    = 12;           % per-dish arrival delay range (samples)
P.phaseWalkDeg = 2;           % per-dish phase random walk per frame (deg)
P.driftHzPerS = 5;            % slow common Doppler drift (Hz/s)

% receiver (shared by every combining mode)
P.lambda      = 0.7;          % memory of channel estimates between frames
P.loading     = 1e-2;         % diagonal loading for the covariance inverse
P.failToFallback = 3;         % consecutive bad frames before safe mode
P.failToLost  = 8;            % consecutive bad frames before a full re-search
P.searchFrames = 4;           % frame periods per carrier search
P.searchThr   = 12;           % carrier detection: spectral peak / median
P.alignWin    = 24;           % per-dish timing search in ALIGN (samples)
P.realignWin  = 16;           % per-dish timing search when one dish stops matching (samples)
P.fitDrop     = 0.35;         % dish flagged when its fit falls below this share of its usual fit
P.fitOK       = 0.15;         % minimum fit for a re-aligned dish to count as found
P.probeEvery  = 25;           % frames between probes of dishes marked down
P.sumpleIters = 3;

for k = 1:2:numel(varargin), P.(varargin{k}) = varargin{k + 1}; end

P.fs    = P.Rs * P.sps;
P.nBits = P.nBytes * 8;
P.nSym  = P.nBits + 32;                     % sync marker + frame
P.L     = P.nSym * P.sps;                   % samples per frame period
P.Tf    = P.nSym / P.Rs;                    % frame duration (s)
P.asm   = int2bit(hex2dec('1ACFFC1D'), 32); % CCSDS attached sync marker
P.rrc   = rcosdesign(P.rolloff, P.span, P.sps);
pn = comm.PNSequence('Polynomial', 'x^8+x^7+x^5+x^3+1', 'InitialConditions', ones(1, 8), ...
    'SamplesPerFrame', P.nBits);
P.pn    = logical(pn());                    % CCSDS pseudo-randomizer, reset every frame
P.crc   = crcConfig('Polynomial', 'z^16+z^12+z^5+1', 'InitialConditions', 1, 'DirectMethod', true);
end
