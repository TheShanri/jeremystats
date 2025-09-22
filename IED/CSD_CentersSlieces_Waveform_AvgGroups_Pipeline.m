function out = CSD_CentersSlieces_Waveform_AvgGroups_Pipeline(inputFolder, dataMatPath, varargin)
% CSD_CentersSlieces_Waveform_AvgGroups_Pipeline
% Wrapper that builds the per-event CSD center-slice tiles + vertical
% waveforms (contributors in gray, mean in black) for SOLID & SPUTTER,
% saves PNGs, and writes a tiny stats CSV for each group.
%
% RETURNS struct:
%   out.pngSolid, out.pngSputter
%   out.statsCSV  (merged SOLID/SPUTTER CSV for this module)
%
% Notes:
% - Preserves native PNG resolution (no resampling here; caller montage stays native).
% - Proper warning() formatting with ME.identifier and %s.

% ---------------- Args (subset mirrored for convenience) ----------------
p = inputParser;
p.addRequired('inputFolder', @(s)ischar(s)||isstring(s));
p.addRequired('dataMatPath', @(s)ischar(s)||isstring(s));

p.addParameter('excelPath', "", @(s)ischar(s)||isstring(s));
p.addParameter('channelIndices', [], @(v) isempty(v) || (isnumeric(v) && all(v>=1)));
p.addParameter('scaleToMicroV', 1, @(x)isnumeric(x) && all(isfinite(x)) && all(x>0));

p.addParameter('winHalfWidthMs',    20e-3, @(x)isfinite(x)&&x>0);   % ±20 ms around anchor
p.addParameter('anchorHalfWidthMs',  5e-3, @(x)isfinite(x)&&x>0);   % ±5 ms anchor search

p.addParameter('sliceThickness', 6, @(x)isfinite(x) && x>=1 && mod(x,1)==0);
p.addParameter('robustPct',    99.5, @(x) isfinite(x) && x>0 && x<100);
p.addParameter('padFrac',       0.12, @(x) isfinite(x) && x>=0 && x<=0.5);

p.addParameter('maxEventsPerGroup', [], @(x) isempty(x) || (isscalar(x) && x>0));

p.parse(inputFolder, dataMatPath, varargin{:});

% ---------------- Call the core generator ----------------
pngSolid   = "";
pngSputter = "";
statsRows  = table();

try
    % We reuse your existing implementation (unchanged behavior)
    CSD_CenterSlices_Waveforms_AvgGroups(inputFolder, dataMatPath, varargin{:});

    outRoot   = fullfile(inputFolder, "CSD Center Slices Output");
    pngSolid  = fullfile(outRoot, "CSD_CenterSlices_SOLID.png");
    pngSputter= fullfile(outRoot, "CSD_CenterSlices_SPUTTER.png");

    % Build small stats table if the PNGs exist
    statsRows = local_collect_stats(outRoot, pngSolid, pngSputter, varargin{:});

catch ME
    warning(ME.identifier, 'CSD_CentersSlieces_Waveform_AvgGroups_Pipeline: generation failed: %s', ME.message);
end

% Write the module CSV (even if empty, we still produce a stub)
statsCSV = fullfile(inputFolder, "CSD Center Slices Output", "CSD_CenterSlices_stats.csv");
try
    if ~isempty(statsRows)
        writetable(statsRows, statsCSV);
    else
        T = table(string(datetime('now')), "EMPTY", 'VariableNames', {'GeneratedAt','Note'});
        writetable(T, statsCSV);
    end
catch ME
    warning(ME.identifier, 'CSD_CentersSlieces_Waveform_AvgGroups_Pipeline: failed to write stats CSV: %s', ME.message);
end

% Return struct for the master pipeline
out = struct( ...
    'pngSolid',   string(pngSolid), ...
    'pngSputter', string(pngSputter), ...
    'statsCSV',   string(statsCSV) ...
);

end

% ------------------------------ helpers ------------------------------

function T = local_collect_stats(outRoot, pngSolid, pngSputter, varargin)
% Creates a minimal stats table per existing PNG, then concatenates.

P = inputParser;
P.addParameter('winHalfWidthMs',    20e-3);
P.addParameter('anchorHalfWidthMs',  5e-3);
P.addParameter('sliceThickness', 6);
P.addParameter('robustPct', 99.5);
P.addParameter('padFrac',  0.12);
P.parse(varargin{:});
prm = P.Results;

rows = [];

if isfile(pngSolid)
    rows = [rows; { "SOLID", string(pngSolid), prm.winHalfWidthMs, prm.anchorHalfWidthMs, prm.sliceThickness, prm.robustPct, prm.padFrac }]; %#ok<AGROW>
end
if isfile(pngSputter)
    rows = [rows; { "SPUTTER", string(pngSputter), prm.winHalfWidthMs, prm.anchorHalfWidthMs, prm.sliceThickness, prm.robustPct, prm.padFrac }]; %#ok<AGROW>
end

if isempty(rows)
    T = table();
else
    T = cell2table(rows, 'VariableNames', ...
        {'Group','PNG','WinHalfWidthSec','AnchorHalfWidthSec','SliceThickness','RobustPct','PadFrac'});
end

end
