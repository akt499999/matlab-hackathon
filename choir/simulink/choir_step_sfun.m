function choir_step_sfun(block)
%CHOIR_STEP_SFUN Level-2 MATLAB S-function that steps the ChoirStep System object once per frame period.
%   Used instead of a MATLAB System block because that block needs a Java runtime to load a custom
%   System object, and this MATLAB has none. The receiver code that runs is identical either way.
setup(block);
end

function setup(block)
block.NumInputPorts = 0;
block.NumOutputPorts = 4;   % verified, state, dishes (receiver); correct (scorer, truth)
for k = 1:4
    block.OutputPort(k).Dimensions = 1;
    block.OutputPort(k).DatatypeID = 0;
    block.OutputPort(k).Complexity = 'Real';
    block.OutputPort(k).SamplingMode = 'Sample';
end
block.NumDialogPrms = 0;
P = choir_params();
block.SampleTimes = [P.Tf 0];
block.RegBlockMethod('Start', @start);
block.RegBlockMethod('Outputs', @outputs);
block.RegBlockMethod('Terminate', @terminate);
end

function start(block)
set_param(block.BlockHandle, 'UserData', struct('obj', ChoirStep(), 't', -inf, 'y', zeros(1, 4)));
end

function outputs(block)
ud = get_param(block.BlockHandle, 'UserData');
if block.CurrentTime > ud.t                      % exactly one receiver step per sample hit
    [a, b, c, d] = step(ud.obj);
    ud.y = [a, b, c, d]; ud.t = block.CurrentTime;
    set_param(block.BlockHandle, 'UserData', ud);
end
for k = 1:4, block.OutputPort(k).Data = ud.y(k); end
end

function terminate(block)
ud = get_param(block.BlockHandle, 'UserData');
if isstruct(ud), release(ud.obj); end
set_param(block.BlockHandle, 'UserData', []);
end
