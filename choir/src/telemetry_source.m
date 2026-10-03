function [vals, info] = telemetry_source(nNeeded)
%TELEMETRY_SOURCE Real Curiosity (MSL) telemetry from the telemanom dataset if it is under res/,
%   otherwise a clearly labeled synthetic stand-in. Values are the dataset's pre-scaled (-1, 1) units.
persistent cacheVals cacheInfo
if isempty(cacheVals)
    root = fileparts(fileparts(mfilename('fullpath')));
    lab = dir(fullfile(root, 'res', '**', 'labeled_anomalies.csv'));
    v = []; names = strings(0, 1);
    if ~isempty(lab)
        T = readtable(fullfile(lab(1).folder, lab(1).name), 'TextType', 'string');
        chans = unique(T.chan_id(T.spacecraft == "MSL"), 'stable');
        for c = chans.'
            f = dir(fullfile(root, 'res', '**', 'test', c + ".npy"));
            if isempty(f), continue; end
            a = read_npy(fullfile(f(1).folder, f(1).name));
            v = [v; double(a(:, 1))]; names(end + 1) = c; %#ok<AGROW>
            if numel(v) >= 60000, break; end
        end
    end
    if ~isempty(v)
        cacheInfo.real = true;
        cacheInfo.source = "NASA MSL (Curiosity) telemetry, telemanom test set, channels " + strjoin(names, ", ");
    else
        t = (0:59999).';
        v = 0.6*sin(2*pi*t/900) + 0.25*sin(2*pi*t/77) + 0.05*randn(RandStream('twister', 'Seed', 7), 60000, 1);
        cacheInfo.real = false;
        cacheInfo.source = "SYNTHETIC stand-in (telemanom MSL files not found under res/)";
    end
    cacheVals = max(min(v, 1), -1);
end
vals = cacheVals(1 + mod(0:nNeeded - 1, numel(cacheVals)));
vals = vals(:);
info = cacheInfo;
end

function a = read_npy(file)
% Minimal .npy reader (little-endian numeric arrays, C or Fortran order).
fid = fopen(file, 'r', 'l'); cleaner = onCleanup(@() fclose(fid));
magic = fread(fid, 6, 'uint8=>char').';
assert(strcmp(magic(2:6), 'NUMPY'), 'not a .npy file: %s', file);
ver = fread(fid, 2, 'uint8');
if ver(1) == 1, hlen = fread(fid, 1, 'uint16'); else, hlen = fread(fid, 1, 'uint32'); end
hdr = fread(fid, hlen, 'uint8=>char').';
tok = regexp(hdr, '''descr'':\s*''[<|=]?([fiu])(\d+)''', 'tokens', 'once');
shp = str2double(regexp(char(extractBetween(string(hdr), "'shape': (", ")")), '\d+', 'match'));
nb = str2double(tok{2});
switch tok{1}
    case 'f', types = {'single', 'double'}; t = types{nb/4};
    case 'i', t = sprintf('int%d', 8*nb);
    otherwise, t = sprintf('uint%d', 8*nb);
end
a = fread(fid, prod(shp), ['*' t]);
if numel(shp) > 1
    if contains(hdr, "'fortran_order': True"), a = reshape(a, shp);
    else, a = reshape(a, fliplr(shp)).'; end
end
end
