%RUN_ALL Reproduce every number and figure in the README:  matlab -batch run_all
%   Takes a few minutes with Parallel Computing Toolbox (runs serially without it).
root = fileparts(mfilename('fullpath'));
addpath(fullfile(root, 'src'));
resDir = fullfile(root, 'results');
if ~isfolder(fullfile(resDir, 'figures')), mkdir(fullfile(resDir, 'figures')); end
P = choir_params();
[~, info] = telemetry_source(1);
fprintf('Telemetry: %s\n', info.source);
run(fullfile(root, 'tests', 'run_tests.m'));
if license('test', 'Distrib_Computing_Toolbox') && isempty(gcp('nocreate')), parpool('Processes'); end
% Development used seeds 1-30 and 101-120. The code was then frozen and these fresh seeds were run once.
seeds = 301:310;
t0 = tic;
exp_snr(P, seeds, resDir);
exp_interference(P, seeds, resDir);
exp_faults(P, 301:320, resDir);
exp_spectra(P, resDir);
make_slides(root);
fprintf('All results written to %s in %.0f s\n', resDir, toc(t0));
