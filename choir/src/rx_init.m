function R = rx_init(P, mode, supervised)
%RX_INIT One receiver. All modes share the same front end and supervisor; only the dish weights differ.
%   mode: "choir"  weights learned only from verified frames (CRC + our spacecraft ID + next count)
%         "sync"   same math, but learned only from the 32-bit sync marker
%         "egc"    equal gains, phases from the sync marker
%         "best"   the single dish with the best sync-marker SNR
%         "sumple" blind consensus weights (Rogstad, JPL IPN PR 42-162, 2005)
%         "genie"  analysis bound: learns from the true transmitted bits of every frame (not a receiver)
%   supervised: false = no re-alignment, safe mode or re-search after the first lock.
R.P = P; R.mode = string(mode); R.sup = supervised;
R.state = "SEARCH"; R.fresh = true;
R.buf = complex(zeros(P.nDish, 0)); R.bufStart = 1; R.nRecv = 0;
R.fhat = 0; R.searchFrom = 1; R.rejectF = []; R.alignTries = 0;
R.t = NaN; R.dl = zeros(P.nDish, 1);
R.h = zeros(P.nDish, 1); R.hAsm = zeros(P.nDish, 1); R.snrEst = zeros(P.nDish, 1);
R.w = ones(P.nDish, 1);
R.up = true(P.nDish, 1); R.fit = nan(P.nDish, 12); R.lastProbe = 0;
R.fails = 0; R.prevVerNA = NaN; R.lastCount = NaN; R.lastT = NaN;
R.nFrames = 0; R.cpu = 0; R.everLocked = false; R.explained = "none";
R.log = table('Size', [0 4], 'VariableTypes', {'double', 'string', 'string', 'string'}, ...
    'VariableNames', {'slot', 'state', 'event', 'reason'});
R.dec = zeros(0, 6);          % [slot, t, count, crcOK, scid, verified]
R.q = {}; R.qT = [];          % telemetry from verified frames and their timing
R.wHist = zeros(P.nDish, 0); R.stateHist = strings(1, 0);
R.captureFrame = NaN; R.capture = [];
end
