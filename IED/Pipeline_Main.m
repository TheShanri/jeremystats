function Pipeline_Main(inputFolder, dataMatPath, varargin)
% Pipeline_Main — orchestrates sub-pipelines and builds TWO master montages
% (SOLID, SPUTTER) at native resolution, plus a merged stats CSV.
%
% Sub-pipelines it tries to run (order = also montage order):
%   1) EventStacks_ampWidth_Avg_Pipeline
%   2) VoltageRaster_EventsAvg_Pipeline
%   3) CSDRaster_Avg_Pipeline
%   4) CSD_CenterSlices_Waveform_AvgGroups_Pipeline
%   5) CSD_TimeAvgSlices_Waveforms_AvgGroups_Pipeline
%
% Robust to missing images/CSVs: warns and continues.

% ---------- Output hub ----------
masterOutDir = fullfile(inputFolder, 'Pipeline Output');
if ~exist(masterOutDir, 'dir'), mkdir(masterOutDir); end
masterPngSOLID   = fullfile(masterOutDir, 'Master_Montage_SOLID.png');
masterPngSPUTTER = fullfile(masterOutDir, 'Master_Montage_SPUTTER.png');
masterCSV        = fullfile(masterOutDir, 'Master_Stats.csv');

% ---------- 0) (optional) spike detection placeholder ----------
% try
%     SpikeDetect_Pipeline(inputFolder, dataMatPath, varargin{:});
% catch ME
%     warning(ME.identifier, 'SpikeDetect_Pipeline failed: %s', ME.message);
% end

% ---------- 1) EventStacks ----------
evtStacksRes = [];
try
    evtStacksRes = EventStacks_ampWidth_Avg_Pipeline(inputFolder, dataMatPath, varargin{:});
catch ME
    warning(ME.identifier, 'EventStacks_ampWidth_Avg_Pipeline failed: %s', ME.message);
end

% ---------- 2) Voltage Raster (averages) ----------
voltRasterRes = [];
try
    voltRasterRes = VoltageRaster_EventsAvg_Pipeline(inputFolder, dataMatPath, varargin{:});
catch ME
    warning(ME.identifier, 'VoltageRaster_EventsAvg_Pipeline failed: %s', ME.message);
end

% ---------- 3) CSD Raster (averages) ----------
csdRasterRes = [];
try
    csdRasterRes = CSDRaster_Avg_Pipeline(inputFolder, dataMatPath, varargin{:});
catch ME
    warning(ME.identifier, 'CSDRaster_Avg_Pipeline failed: %s', ME.message);
end

% ---------- 4) CSD Center Slices + Vertical Waveforms ----------
csdSlicesRes = [];
try
    csdSlicesRes = CSD_CenterSlices_Waveform_AvgGroups_Pipeline(inputFolder, dataMatPath, varargin{:});
catch ME
    warning(ME.identifier, 'CSD_CenterSlices_Waveform_AvgGroups_Pipeline failed: %s', ME.message);
end

% ---------- 5) CSD Time-Avg Slices + Vertical Waveforms ----------
csdTimeAvgRes = [];
try
    csdTimeAvgRes = CSD_TimeAvgSlices_Waveforms_AvgGroups_Pipeline(inputFolder, dataMatPath, varargin{:});
catch ME
    warning(ME.identifier, 'CSD_TimeAvgSlices_Waveforms_AvgGroups_Pipeline failed: %s', ME.message);
end

% ---------- Collect PNGs in fixed order ----------
% Order in montage (top-to-bottom):
%   EventStacks → Voltage Raster → CSD Raster → CSD Center Slices → CSD Time-Avg
pngSOL = {};
pngSPU = {};

resList = {evtStacksRes, voltRasterRes, csdRasterRes, csdSlicesRes, csdTimeAvgRes};
for i = 1:numel(resList)
    R = resList{i};
    pngSOL = addIfExists(pngSOL, getFieldSafe(R,'pngSolid'));
    pngSPU = addIfExists(pngSPU, getFieldSafe(R,'pngSputter'));
end

% ---------- Build two hi-res montages (native resolution, no resampling) ----------
if isempty(pngSOL)
    warning('Pipeline:NoSolidPNGs', 'No SOLID PNGs found; SOLID montage not created.');
else
    try
        makeMontageHiRes(pngSOL, masterPngSOLID);
        fprintf('Master SOLID montage saved: %s\n', masterPngSOLID);
    catch ME
        warning(ME.identifier, 'Failed to build SOLID montage: %s', ME.message);
    end
end

if isempty(pngSPU)
    warning('Pipeline:NoSputterPNGs', 'No SPUTTER PNGs found; SPUTTER montage not created.');
else
    try
        makeMontageHiRes(pngSPU, masterPngSPUTTER);
        fprintf('Master SPUTTER montage saved: %s\n', masterPngSPUTTER);
    catch ME
        warning(ME.identifier, 'Failed to build SPUTTER montage: %s', ME.message);
    end
end

% ---------- Merge available stats into a single CSV ----------
T = table();
T = tryAddCSV(T, evtStacksRes,  'EventStacks');
T = tryAddCSV(T, voltRasterRes, 'VoltageRaster');
T = tryAddCSV(T, csdRasterRes,  'CSDRaster');
T = tryAddCSV(T, csdSlicesRes,  'CSDCenterSlices');
T = tryAddCSV(T, csdTimeAvgRes, 'CSDTimeAvg');

try
    if isempty(T)
        T = table(string(datetime('now')), "EMPTY", 'VariableNames', {'GeneratedAt','Note'});
    end
    writetable(T, masterCSV);
    fprintf('Master stats CSV: %s\n', masterCSV);
catch ME
    warning(ME.identifier, 'Failed writing master stats CSV: %s', ME.message);
end
end

% ================= helpers =================

function v = getFieldSafe(S, fieldName)
% return "" if struct missing field or empty
if ~(isstruct(S) && isfield(S, fieldName))
    v = "";
else
    v = string(S.(fieldName));
end
end

function L = addIfExists(L, pathStr)
% append if it's a non-empty existing file; keep order; avoid duplicates
if strlength(pathStr) > 0
    p = char(pathStr);
    if isfile(p) && ~any(strcmp(L, p))
        L{end+1} = p; %#ok<AGROW>
    end
end
end

function T = tryAddCSV(T, res, tag)
% read res.statsCSV if present; add 'source' column; outer-join schema
try
    if isstruct(res) && isfield(res,'statsCSV') && ~isempty(res.statsCSV) && isfile(res.statsCSV)
        C = readtable(res.statsCSV);
        if ~ismember('source', C.Properties.VariableNames)
            C.source = repmat(string(tag), height(C), 1);
        else
            % ensure it's a string column for consistency
            C.source = string(C.source);
        end
        T = vertcatSafe(T, C);
    end
catch ME
    warning(ME.identifier, 'Failed to merge stats from %s: %s', tag, ME.message);
end
end

function T = vertcatSafe(A, B)
% outer-union by variable names, then vertical concat
if isempty(A), T = B; return; end
if isempty(B), T = A; return; end
allVars = union(A.Properties.VariableNames, B.Properties.VariableNames, 'stable');
A = addMissingVars(A, allVars);
B = addMissingVars(B, allVars);
T = [A; B]; %#ok<AGROW>
end

function T = addMissingVars(T, allVars)
missing = setdiff(allVars, T.Properties.VariableNames, 'stable');
for k = 1:numel(missing)
    T.(missing{k}) = missingDefault();
end
T = T(:, allVars);
end

function x = missingDefault()
x = missing;
end

function makeMontageHiRes(pngList, outPath)
% Stack images vertically at NATIVE resolution (no resampling).
% Pads narrower images to the max width with white. Adds 6 px white spacer.

assert(~isempty(pngList), 'pngList is empty.');

imgs = cell(numel(pngList),1);
widths  = zeros(numel(pngList),1);
heights = zeros(numel(pngList),1);

for i = 1:numel(pngList)
    imgs{i} = imread(pngList{i});
    [h,w,~] = size(imgs{i});
    widths(i)  = w;
    heights(i) = h;
end

Wmax = max(widths);
sep  = 6; % white separator in pixels

cls = class(imgs{1});
switch cls
    case {'uint8'},  whiteVal = uint8(255);
    case {'uint16'}, whiteVal = uint16(65535);
    case {'double'}, whiteVal = 1;
    case {'single'}, whiteVal = single(1);
    otherwise, error('Unsupported image class: %s', cls);
end

totalH = sum(heights) + sep*(numel(imgs)-1);
if size(imgs{1},3) == 1
    out = repmat(whiteVal, [totalH, Wmax, 1]);
else
    out = repmat(reshape(whiteVal,1,1,[]), [totalH, Wmax, size(imgs{1},3)]);
end

y = 1;
for i = 1:numel(imgs)
    I = imgs{i};
    [h,w,c] = size(I);
    out(y:y+h-1, 1:w, 1:c) = I;
    y = y + h;
    if i < numel(imgs), out(y:y+sep-1, :, :) = whiteVal; y = y + sep; end
end

imwrite(out, outPath);
end
