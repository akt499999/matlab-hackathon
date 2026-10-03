classdef ChoirStep < matlab.System
    %CHOIRSTEP The existing Choir receiver (choir/src) as a Simulink block: one frame period per step.
    %   Each step calls channel_slot then rx_step, exactly like the loop in run_scenario.m.
    %   Outputs 1-3 come from the receiver only. Output 4 is the scorer (truth): it compares the frames
    %   the receiver logged with what was transmitted, the same test as score_run. The receiver never sees it.
    %   Uses strings, tables and RandStream, so it only runs interpreted (no code generation).
    %   choir_sim.slx steps it from choir_step_sfun.m; a MATLAB System block would need a Java runtime.

    properties (Nontunable)
        Seed = 301      % scenario seed (also seeds random_faults)
        Frames = 300    % frames transmitted
        EsN0dB = 2      % mean per-dish Es/N0 (dB)
    end

    properties (Access = private)
        P; sc; ch; R; slot = 0; ok
    end

    methods (Access = protected)
        function setupImpl(obj)
            obj.P = choir_params();
            obj.sc = make_scenario(obj.Seed, obj.Frames, obj.EsN0dB, random_faults(obj.Seed, obj.Frames, obj.P.nDish));
            startRun(obj);
        end

        function resetImpl(obj)
            startRun(obj);
        end

        function [verifiedThisFrame, stateCode, dishesInUse, cumulativeCorrect] = stepImpl(obj)
            obj.slot = obj.slot + 1;
            nDec = size(obj.R.dec, 1); nQ = numel(obj.R.qT);
            [X, obj.ch] = channel_slot(obj.ch, obj.slot);
            obj.R = rx_step(obj.R, X, obj.slot, []);
            % receiver outputs
            verifiedThisFrame = double(any(obj.R.dec(nDec + 1:end, 6)));
            stateCode = find(obj.R.state == ["SEARCH", "ALIGN", "DECODE", "FALLBACK"]);
            dishesInUse = nnz(obj.R.up);
            % scorer (truth): score_run's test, applied to the frames logged during this step
            for i = nQ + 1:numel(obj.R.qT)
                j = round((obj.R.qT(i) - obj.ch.Toff - 41) / obj.P.L) + 1;
                if j >= 1 && j <= obj.sc.F && isequal(obj.R.q{i}(:), obj.ch.tx.q(:, j)), obj.ok(j) = true; end
            end
            cumulativeCorrect = nnz(obj.ok);
        end

        function st = getSampleTimeImpl(obj)
            P = choir_params();
            st = createSampleTime(obj, 'Type', 'Discrete', 'SampleTime', P.Tf);
        end

        function [a, b, c, d] = getOutputNamesImpl(~)
            a = 'verified'; b = 'state'; c = 'dishes'; d = 'correct (scorer, truth)';
        end

        function [a, b, c, d] = getOutputSizeImpl(~), [a, b, c, d] = deal([1 1]); end
        function [a, b, c, d] = getOutputDataTypeImpl(~), [a, b, c, d] = deal('double'); end
        function [a, b, c, d] = isOutputComplexImpl(~), [a, b, c, d] = deal(false); end
        function [a, b, c, d] = isOutputFixedSizeImpl(~), [a, b, c, d] = deal(true); end
    end

    methods (Access = private)
        function startRun(obj)
            obj.ch = channel_make(obj.P, obj.sc);
            obj.R = rx_init(obj.P, "choir", true);
            obj.slot = 0; obj.ok = false(1, obj.sc.F);
        end
    end
end
