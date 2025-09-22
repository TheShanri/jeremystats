function Pipeline_Main(inputFolder, dataMatPath, varargin)
% Pipeline_Main
% Orchestrates the analysis and figure creation across multiple sub-pipelines.
%
% INPUTS
%   inputFolder  : path with Solid/ and Sputter/ subfolders + the Excel sheet
%   dataMatPath  : .mat with fields: d [nRows x nSamp], sfx, (optional) kept_channels
%
% NAME-VALUE (forwarded to sub-pipelines where relevant)
%   'excelPath'            : explicit Excel sheet path (auto-detect if omitted)
%   'channelIndices'       : rows to include (default: all)
%   'scaleToMicroV'        : scale factor(s), default 1
%   'halfWidthMs'          : etc... (each sub-pipeline handles its own options)
%
% OUTPUTS & SIDE-EFFECTS
%   - Each sub-pipeline saves its PNGs and MAT stats in its own folder.
%   - This function composes a "master" montage from whatever PNGs exist.
%   - This function writes a CSV that merges *available* stats.
%
% NOTE
%   For now, only EventStacks_ampWidth_Avg_Pipeline is active.
%   Other calls are left as commented placeholders (so this skeleton
%   runs even before those components exist).

opts = struct(varargin{:});

% ---------- Output hub for the master ----------
masterOutDir = fullfile(inputFolder, 'Pipeline Output');
if ~exist(masterOutDir, 'dir'), mkdir(masterOutDir); end
masterPng    = fullfile(masterOutDir, 'Master_Montage.png');
masterCSV    = fullfile(masterOutDir, 'Master_Stats.csv');

% ---------- 1) EventStacks_ampWidth_Avg_Pipeline (ACTIVE) ----------
evtStacksRes = [];
try
    evtStacksRes = EventStacks_ampWidth_Avg_Pipeline(inputFolder, dataMatPath, varargin{:});
catch ME
    warning('EventStacks_ampWidth_Avg_Pipeline failed: %s', ME.message);
end

% ---------- 2) VoltageRaster_EventsAvg_Pipeline ----------
% Place-holder (to be implemented)
% try
%     voltRasterRes = VoltageRaster_EventsAvg_Pipeline(inputFolder, dataMatPath, varargin{:});
% catch ME
%     warning('VoltageRaster_EventsAvg_Pipeline failed: %s', ME.message);
% end

% ---------- 3) CSDRaster_Avg_Pipeline ----------
% Place-holder (to be implemented)
% try
%     csdRasterRes = CSDRaster_Avg_Pipeline(inputFolder, dataMatPath, varargin{:});
% catch ME
%     warning('CSDRaster_Avg_Pipeline failed: %s', ME.message);
% end

% ---------- 4) CSD_CenterSlices_Waveform_AvgGroups_Pipeline ----------
% Place-holder (to be implemented)
% try
%     csdSlicesRes = CSD_CenterSlices_Waveform_AvgGroups_Pipeline(inputFolder, dataMatPath, varargin{:});
% catch ME
%     warning('CSD_CenterSlices_Waveform_AvgGroups_Pipeline failed: %s', ME.message);
% end

% ---------- 5) CSD_TimeAvg_Waveform_AvgGroups_Pipeline ----------
% Place-holder (to be implemented)
% try
%     csdTimeAvgRes = CSD_TimeAvg_Waveform_AvgGroups_Pipeline(inputFolder, dataMatPath, varargin{:});
% catch ME
%     warning('CSD_TimeAvg_Waveform_AvgGroups_Pipeline failed: %s', ME.message);
% end

% ---------- Gather whatever PNGs exist and build a master montage ----------
pngList = {};
lblList = {};

% EventStacks outputs (if present)
if ~isempty(evtStacksRes)
    if isfield(evtStacksRes, 'pngSolid') && isfile(evtStacksRes.pngSolid)
        pngList{end+1} = evtStacksRes.pngSolid; lblList{end+1} = 'EventStacks SOLID'; %#ok<*AGROW>
    end
    if isfield(evtStacksRes, 'pngSputter') && isfile(evtStacksRes.pngSputter)
        pngList{end+1} = evtStacksRes.pngSputter; lblList{end+1} = 'EventStacks SPUTTER';
    end
end

% % Voltage raster (avg) (placeholder)
% if exist('voltRasterRes','var') && ~isempty(voltRasterRes)
%     if isfield(voltRasterRes, 'pngSolid') && isfile(voltRasterRes.pngSolid)
%         pngList{end+1} = voltRasterRes.pngSolid; lblList{end+1} = 'VoltageRaster SOLID';
%     end
%     if isfield(voltRasterRes, 'pngSputter') && isfile(voltRasterRes.pngSputter)
%         pngList{end+1} = voltRasterRes.pngSputter; lblList{end+1} = 'VoltageRaster SPUTTER';
%     end
% end

% % CSD raster (avg) (placeholder)
% if exist('csdRasterRes','var') && ~isempty(csdRasterRes)
%     if isfield(csdRasterRes, 'pngSolid') && isfile(csdRasterRes.pngSolid)
%         pngList{end+1} = csdRasterRes.pngSolid; lblList{end+1} = 'CSDRaster SOLID';
%     end
%     if isfield(csdRasterRes, 'pngSputter') && isfile(csdRasterRes.pngSputter)
%         pngList{end+1} = csdRasterRes.pngSputter; lblList{end+1} = 'CSDRaster SPUTTER';
%     end
% end

% % CSD center slices + waveforms (placeholder)
% if exist('csdSlicesRes','var') && ~isempty(csdSlicesRes)
%     if isfield(csdSlicesRes, 'pngSolid') && isfile(csdSlicesRes.pngSolid)
%         pngList{end+1} = csdSlicesRes.pngSolid; lblList{end+1} = 'CSD Slices SOLID';
%     end
%     if isfield(csdSlicesRes, 'pngSputter') && isfile(csdSlicesRes.pngSputter)
%         pngList{end+1} = csdSlicesRes.pngSputter; lblList{end+1} = 'CSD Slices SPUTTER';
%     end
% end

% % CSD time-avg waveforms (placeholder)
% if exist('csdTimeAvgRes','var') && ~isempty(csdTimeAvgRes)
%     if isfield(csdTimeAvgRes, 'pngSolid') && isfile(csdTimeAvgRes.pngSolid)
%         pngList{end+1} = csdTimeAvgRes.pngSolid; lblList{end+1} = 'CSD TimeAvg SOLID';
%     end
%     if isfield(csdTimeAvgRes, 'pngSputter') && isfile(csdTimeAvgRes.pngSputter)
%         pngList{end+1} = csdTimeAvgRes.pngSputter; lblList{end+1} = 'CSD TimeAvg SPUTTER';
%     end
% end

if isempty(pngList)
    warning('No PNGs found yet; master montage not created.');
else
    try
        makeMontage(pngList, lblList, masterPng);
        fprintf('Master montage saved: %s\n', masterPng);
    catch ME
        warning('Failed to build master montage: %s', ME.message);
    end
end

% ---------- Merge whatever stats exist into CSV ----------
T = table(); % start empty

if ~isempty(evtStacksRes) && isfield(evtStacksRes, 'statsCSV') && isfile(evtStacksRes.statsCSV)
    try
        T1 = readtable(evtStacksRes.statsCSV);
        T = vertcatSafe(T, T1);
    catch ME
        warning('Failed reading EventStacks stats CSV: %s', ME.message);
    end
end

% % Additional components: append their CSVs similarly...
% if exist('voltRasterRes','var') && isfield(voltRasterRes,'statsCSV') && isfile(voltRasterRes.statsCSV)
%     T = vertcatSafe(T, readtable(voltRasterRes.statsCSV));
% end

% Finally write the master CSV (even if empty, we create the file so downstream always finds it)
try
    if isempty(T)
        % Create a minimal empty table with a helpful column
        T = table(string(datetime('now')), "EMPTY", 'VariableNames', {'GeneratedAt','Note'});
    end
    writetable(T, masterCSV);
    fprintf('Master stats CSV: %s\n', masterCSV);
catch ME
    warning('Failed writing master stats CSV: %s', ME.message);
end

end

% ----------------- helpers -----------------

function T = vertcatSafe(A, B)
% VERTCAT two tables, reconciling mismatched variable sets by outer-joining columns
if isempty(A), T = B; return; end
if isempty(B), T = A; return; end
allVars = union(A.Properties.VariableNames, B.Properties.VariableNames);
A = addMissingVars(A, allVars);
B = addMissingVars(B, allVars);
T = [A; B]; %#ok<AGROW>
end

function T = addMissingVars(T, allVars)
missing = setdiff(allVars, T.Properties.VariableNames);
for k = 1:numel(missing)
    T.(missing{k}) = missingDefault();
end
T = T(:, allVars);
end

function x = missingDefault()
x = missing;  % MATLAB missing value (works for string/categorical); for numeric will upcast later as needed
end

function makeMontage(pngList, lblList, outPath)
% Simple vertical montage of available PNGs with labels
n = numel(pngList);
figH = min(350 + 320*n, 9000);
f = figure('Color','w','Position',[80 80 1200 figH],'Visible','off');
t = tiledlayout(f, n, 1, 'Padding','compact','TileSpacing','compact');

for i = 1:n
    ax = nexttile(t); axis(ax,'off'); hold(ax,'on');
    try
        I = imread(pngList{i});
        image(ax, I); axis(ax,'image'); axis(ax,'off');
        title(ax, lblList{i}, 'FontSize', 11, 'FontWeight', 'bold', 'Interpreter','none');
    catch ME
        text(ax, 0.5, 0.5, sprintf('Missing or unreadable: %s\n%s', pngList{i}, ME.message), ...
            'HorizontalAlignment','center','VerticalAlignment','middle', ...
            'FontSize',10, 'Color',[0.7 0 0], 'Interpreter','none');
        axis(ax,'off');
    end
end

exportgraphics(f, outPath, 'Resolution', 220);
close(f);
end
