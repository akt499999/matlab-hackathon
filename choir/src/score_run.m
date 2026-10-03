function S = score_run(R, ch)
%SCORE_RUN Independent scorer: compares what the receiver logged with what was actually sent.
%   Correct = a logged frame whose telemetry equals the transmitted frame bit for bit.
%   False accept = a logged frame whose telemetry is wrong (it passed every check but is not what was sent).
P = ch.P; F = ch.sc.F;
ok = false(1, F); wrong = 0;
for i = 1:numel(R.qT)
    j = round((R.qT(i) - ch.Toff - 41) / P.L) + 1;
    if j >= 1 && j <= F && isequal(R.q{i}(:), ch.tx.q(:, j))
        ok(j) = true;
    else
        wrong = wrong + 1;
    end
end
S.name = R.mode; S.mode = R.mode; S.sup = R.sup;
S.ok = ok; S.correctFrac = mean(ok); S.falseAccepts = wrong;
S.msPerFrame = 1000 * R.cpu / max(R.nFrames, 1);
S.nEvents = height(R.log);
end
