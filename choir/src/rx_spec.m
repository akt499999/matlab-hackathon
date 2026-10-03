function s = rx_spec(mode, sup, name)
%RX_SPEC Describe one receiver to run: combining mode, supervisor on/off, display name.
if nargin < 3, name = mode; end
s = struct('mode', string(mode), 'sup', logical(sup), 'name', string(name));
end
