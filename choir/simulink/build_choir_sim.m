%BUILD_CHOIR_SIM Build choir_sim.slx: the existing Choir receiver (ChoirStep System object), one frame per step.
%   The block is a Level-2 MATLAB S-Function (choir_step_sfun.m) that steps ChoirStep. A MATLAB System
%   block would need a Java runtime to load ChoirStep, and this MATLAB has none. Both run interpreted.
here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(fileparts(here), 'src'));
P = choir_params();
mdl = 'choir_sim';
slx = fullfile(here, [mdl '.slx']);
if bdIsLoaded(mdl), close_system(mdl, 0); end
if isfile(slx), delete(slx); end   % previous build output; avoids the name-shadowing warning
new_system(mdl);

blk = [mdl '/Choir receiver'];
add_block('simulink/User-Defined Functions/Level-2 MATLAB S-Function', blk, ...
    'FunctionName', 'choir_step_sfun', 'Position', [60 60 240 260]);

add_block('simulink/Sinks/Scope', [mdl '/Receiver'], 'NumInputPorts', '3', 'Position', [420 50 470 170]);
add_block('simulink/Sinks/Scope', [mdl '/Scorer (truth)'], 'Position', [420 330 470 370]);
scopeCfg = get_param([mdl '/Receiver'], 'ScopeConfiguration');
scopeCfg.LayoutDimensions = [3 1];   % one axes per receiver signal
sigNames = {'verified', 'state', 'dishes', 'correct (scorer, truth)'};
for k = 1:3, add_line(mdl, sprintf('Choir receiver/%d', k), sprintf('Receiver/%d', k), 'autorouting', 'on'); end
add_line(mdl, 'Choir receiver/4', 'Scorer (truth)/1', 'autorouting', 'on');

varNames = {'sim_verified', 'sim_state', 'sim_dishes', 'sim_correct'};
for k = 1:4
    tw = sprintf('To Workspace %d', k);
    add_block('simulink/Sinks/To Workspace', [mdl '/' tw], 'VariableName', varNames{k}, ...
        'SaveFormat', 'Timeseries', 'Position', [560 30 + 70*k 660 60 + 70*k]);
    add_line(mdl, sprintf('Choir receiver/%d', k), [tw '/1'], 'autorouting', 'on');
end
ph = get_param(blk, 'PortHandles');
for k = 1:4, set_param(get_param(ph.Outport(k), 'Line'), 'Name', sigNames{k}); end

set_param(mdl, 'SolverType', 'Fixed-step', 'Solver', 'FixedStepDiscrete', 'FixedStep', 'auto', ...
    'StopTime', sprintf('%.17g', 300*P.Tf));
note = Simulink.Annotation([mdl '/Runs the same Choir MATLAB code as run_all.m, one frame per step.']);
note.Position = [60 300 360 330];
save_system(mdl, slx);
fprintf('Saved %s\n', slx);
