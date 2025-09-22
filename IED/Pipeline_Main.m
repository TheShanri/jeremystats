function Pipeline_Main(inputFolder, dataMatPath, varargin)
% ... (header unchanged)

masterOutDir = fullfile(inputFolder, 'Pipeline Output');
if ~exist(masterOutDir, 'dir'), mkdir(masterOutDir); end
masterPngSOLID   = fullfile(masterOutDir, 'Master_Montage_SOLID.png');
masterPngSPUTTER = fullfile(masterOutDir, 'Master_Montage_SPUTTER.png');
masterCSV        = fullfile(masterOutDir, 'Master_Stats.csv');

% 1) EventStacks_ampWidth_Avg_Pipeline
evtStacksRes = [];
try
    evtStacksRes = EventStacks_ampWidth_Avg_Pipeline(inputFolder, dataMatPath, varargin{:});
catch ME
    warning(ME.identifier, 'EventStacks_ampWidth_Avg_Pipeline failed: %s', ME.message);
end

% 2) VoltageRaster_EventsAvg_Pipeline
voltRasterRes = [];
try
    voltRasterRes = VoltageRaster_EventsAvg_Pipeline(inputFolder, dataMatPath, varargin{:});
catch ME
    warning(ME.identifier, 'VoltageRaster_EventsAvg_Pipeline failed: %s', ME.message);
end

% 3) CSDRaster_Avg_Pipeline
csdRasterRes = [];
try
    csdRasterRes = CSDRaster_Avg_Pipeline(inputFolder, dataMatPath, varargin{:});
catch ME
    warning(ME.identifier, 'CSDRaster_Avg_Pipeline failed: %s', ME.message);
end

% 4) CSD_CentersSlieces_Waveform_AvgGroups_Pipeline  <-- NEW: enabled
csdSlicesRes = [];
try
    csdSlicesRes = CSD_CentersSlieces_Waveform_AvgGroups_Pipeline(inputFolder, dataMatPath, varargin{:});
catch ME
    warning(ME.identifier, 'CSD_CentersSlieces_Waveform_AvgGroups_Pipeline failed: %s', ME.message);
end

% 5) CSD_TimeAvg_Waveform_AvgGroups_Pipeline
% csdTimeAvgRes = [];
% try
%     csdTimeAvgRes = CSD_TimeAvg_Waveform_AvgGroups_Pipeline(inputFolder, dataMatPath, varargin{:});
% catch ME
%     warning(ME.identifier, 'CSD_TimeAvg_Waveform_AvgGroups_Pipeline failed: %s', ME.message);
% end

% ---------- Collect PNGs ----------
pngSOL = {};
pngSPU = {};

% EventStacks
if ~isempty(evtStacksRes)
    if isfield(evtStacksRes, 'pngSolid')   && isfile(evtStacksRes.pngSolid),   pngSOL{end+1} = evtStacksRes.pngSolid; end
    if isfield(evtStacksRes, 'pngSputter') && isfile(evtStacksRes.pngSputter), pngSPU{end+1} = evtStacksRes.pngSputter; end
end

% Voltage Raster
if ~isempty(voltRasterRes)
    if isfield(voltRasterRes, 'pngSolid')   && isfile(voltRasterRes.pngSolid),   pngSOL{end+1} = voltRasterRes.pngSolid; end
    if isfield(voltRasterRes, 'pngSputter') && isfile(voltRasterRes.pngSputter), pngSPU{end+1} = voltRasterRes.pngSputter; end
end

% CSD Raster
if ~isempty(csdRasterRes)
    if isfield(csdRasterRes, 'pngSolid')   && isfile(csdRasterRes.pngSolid),   pngSOL{end+1} = csdRasterRes.pngSolid; end
    if isfield(csdRasterRes, 'pngSputter') && isfile(csdRasterRes.pngSputter), pngSPU{end+1} = csdRasterRes.pngSputter; end
end

% CSD Center Slices (NEW)
if ~isempty(csdSlicesRes)
    if isfield(csdSlicesRes, 'pngSolid')   && isfile(csdSlicesRes.pngSolid),   pngSOL{end+1} = csdSlicesRes.pngSolid; end
    if isfield(csdSlicesRes, 'pngSputter') && isfile(csdSlicesRes.pngSputter), pngSPU{end+1} = csdSlicesRes.pngSputter; end
end

% ---------- Build two hi-res montages (native res) ----------
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
if ~isempty(evtStacksRes) && isfield(evtStacksRes, 'statsCSV') && isfile(evtStacksRes.statsCSV)
    try, T = vertcatSafe(T, readtable(evtStacksRes.statsCSV)); catch ME, warning(ME.identifier, 'EventStacks CSV read failed: %s', ME.message); end
end
if ~isempty(voltRasterRes) && isfield(voltRasterRes, 'statsCSV') && isfile(voltRasterRes.statsCSV)
    try, T = vertcatSafe(T, readtable(voltRasterRes.statsCSV)); catch ME, warning(ME.identifier, 'VoltageRaster CSV read failed: %s', ME.message); end
end
if ~isempty(csdRasterRes) && isfield(csdRasterRes, 'statsCSV') && isfile(csdRasterRes.statsCSV)
    try, T = vertcatSafe(T, readtable(csdRasterRes.statsCSV)); catch ME, warning(ME.identifier, 'CSDRaster CSV read failed: %s', ME.message); end
end
if ~isempty(csdSlicesRes) && isfield(csdSlicesRes, 'statsCSV') && isfile(csdSlicesRes.statsCSV)
    try, T = vertcatSafe(T, readtable(csdSlicesRes.statsCSV)); catch ME, warning(ME.identifier, 'CSD Center Slices CSV read failed: %s', ME.message); end
end

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
